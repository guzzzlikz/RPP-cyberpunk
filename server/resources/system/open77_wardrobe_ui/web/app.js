(function() {
  "use strict";
  const M=WardrobeModel, $=id=>document.getElementById(id), emit=(name,value={})=>Open77.emit(name,value);
  let baseline, draft, confirmed, catalogue=[], lookup={}, mode="equipment", outfit=0, slot="Head", page=0, yaw=180;
  // Layered outfits (Equipment-EX slots, outfit-slots.js): the chosen body area and layer.
  const LAYERS=Array.isArray(globalThis.OutfitSlots)?globalThis.OutfitSlots:[];
  const AREAS=[...new Set(LAYERS.map(l=>l.area))];
  let area=AREAS[0] || "Head", layer=(LAYERS[0] || {}).name || "";
  const layerInfo=name=>LAYERS.find(l=>l.name===name) || {};
  let busy=false, previewPending=false, pendingConfirm=null, favoritesOnly=false, favoritesReady=false, favorites=new Set();
  const PAGE_SIZE=24;
  const errors={save_timeout:"Сервер не подтвердил сохранение. Можно повторить, примерка не потерялась.",presentation_revision_conflict:"Гардероб изменился в другом месте. Восстановлен последний сохранённый образ. Повтори изменения.",revision_conflict:"Гардероб изменился в другом месте. Восстановлен последний сохранённый образ.",presentation_database_error:"Образ не сохранился. Прежний гардероб не пострадал.",incompatible_body_family:"Эта вещь не подходит к твоему типу тела.",restricted_record:"Эта одежда недоступна на сервере.",item_unavailable:"Эта одежда недоступна. Возвращена прошлая примерка.",presentation_character_changed:"Персонаж изменился. Закрой гардероб и открой снова."};
  function message(text,kind="") { $("status").textContent=text; $("status").className="status "+kind; }
  function reason(text) { return errors[text] || "Не удалось применить изменение ("+String(text || "неизвестная ошибка").replace(/_/g," ")+")."; }
  function visualValue(value) { return value && (lookup[String(value).toLowerCase()] || {}).nonvisual === true ? false : value; }
  function catalogTitle(item) { return item.label || M.title(item.record); }
  function itemName(value) { value=visualValue(value);return value ? catalogTitle(lookup[String(value).toLowerCase()] || {record:value}) : "Ничего не надето"; }
  function currentSlots() { return mode==="layers"?draft.layers.slots:mode==="equipment"?draft.equipment:draft.wardrobe.outfits[outfit]; }
  function currentKey() { return mode==="layers"?layer:slot; }
  function editSlot(value) {
    if(mode==="layers") {
      // Any clothing goes in any layer (Equipment-EX remapping); choosing one turns the look on.
      if(value) { draft.layers.slots[layer]=value; draft.layers.active=true; }
      else delete draft.layers.slots[layer];
      return;
    }
    currentSlots()[slot]=value;
    if(mode==="outfits") draft.wardrobe.active=outfit;
    else {
      // Editing worn clothing must show the selected garment, not an overlay
      // or a full-body suit covering it. These remain unsaved draft changes.
      draft.wardrobe.active=false;
      if(slot!=="Outfit") draft.equipment.Outfit=false;
    }
  }
  function canonical(value) { return value ? ((lookup[String(value).toLowerCase()] || {}).record || value) : value; }
  function dirty() { return baseline && M.dirty(baseline,draft); }
  function updateControls() {
    const changed=dirty();
    $("saved-state").textContent=busy?"СОХРАНЕНИЕ":changed?"НЕ СОХРАНЕНО":"СОХРАНЕНО";
    $("saved-state").className=changed?"dirty":"";
    $("save").disabled=busy || previewPending || !changed;
    $("save").textContent=busy?"СОХРАНЕНИЕ":"СОХРАНИТЬ";
    document.querySelectorAll(".item .choose,.slot-actions button,.outfit-actions button,#rename,#disable-overlay").forEach(el=>el.disabled=busy || previewPending);
  }
  function preview(change, text) {
    if(busy || previewPending) return;
    confirmed=M.clone(draft);
    change();
    previewPending=true;
    emit("wardrobe:preview",{equipment:draft.equipment,wardrobe:draft.wardrobe,layers:draft.layers});
    render();
    message(text || "Примерка. Сохрани, чтобы оставить образ.");
  }
  function confirmAction(title,text,action,label="ОТМЕНИТЬ") {
    $("confirm-title").textContent=title;$("confirm-text").textContent=text;
    $("confirm-yes").textContent=label;$("confirm").hidden=false;pendingConfirm=action;$("confirm-no").focus();
  }
  function requestClose() {
    if(busy) { confirmAction("СОХРАНЕНИЕ ЕЩЁ ИДЁТ","Сервер может завершить сохранение уже после закрытия. Закрыть примерочную?",()=>emit("wardrobe:close"),"ЗАКРЫТЬ"); return; }
    if(dirty()) confirmAction("ОТМЕНИТЬ ИЗМЕНЕНИЯ?","Несохранённая примерка пропадёт, вернётся последний сохранённый образ.",()=>emit("wardrobe:close"));
    else emit("wardrobe:close");
  }
  function renderItems() {
    const q=$("search").value.trim().toLowerCase();
    const fallback=layerInfo(layer).fallback;
    let entries=catalogue.filter(item=>(mode==="layers" || item.slot===slot) && (!favoritesOnly || favorites.has(item.record)) && (!q || (catalogTitle(item)+" "+item.record).toLowerCase().includes(q)));
    if(mode==="layers" && fallback) entries=entries.filter(i=>i.slot===fallback).concat(entries.filter(i=>i.slot!==fallback));
    const maxPage=Math.max(0,Math.ceil(entries.length/PAGE_SIZE)-1);page=Math.min(page,maxPage);
    const grid=$("catalogue");grid.replaceChildren();
    entries.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE).forEach(item=>{
      const row=document.createElement("div");row.className="item";row.setAttribute("role","listitem");
      const selected=canonical(currentSlots()[currentKey()])===item.record;row.classList.toggle("selected",selected);
      const choose=document.createElement("button");choose.className="choose catalog-card";choose.dataset.record=item.record;choose.setAttribute("aria-pressed",String(selected));
      choose.title=catalogTitle(item);const title=document.createElement("strong");title.textContent=catalogTitle(item);
      const subtitle=document.createElement("small");subtitle.textContent=selected?"ВЫБРАНО":(M.labels[item.slot] || M.layerTitle(item.slot)).toUpperCase();
      choose.append(title,subtitle);choose.onclick=()=>preview(()=>editSlot(item.record));
      const favorite=document.createElement("button");favorite.className="favorite";favorite.classList.toggle("on",favorites.has(item.record));favorite.textContent=favorites.has(item.record)?"★":"☆";
      favorite.setAttribute("aria-label",(favorites.has(item.record)?"Убрать из избранного ":"В избранное ")+catalogTitle(item));
      favorite.disabled=!favoritesReady;favorite.onclick=()=>{favoritesReady=false;document.querySelectorAll(".favorite").forEach(button=>button.disabled=true);emit("wardrobe:favorite",{record:item.record,enabled:!favorites.has(item.record)});};
      row.append(choose,favorite);grid.append(row);
    });
    if(!entries.length){const empty=document.createElement("p");empty.className="empty";empty.textContent=favoritesOnly?"В этой категории нет избранного. Отметь одежду звёздочкой.":"Ничего не нашлось. Попробуй другой запрос или категорию.";grid.append(empty);}
    $("count").textContent=entries.length?`${page*PAGE_SIZE+1}–${Math.min(entries.length,(page+1)*PAGE_SIZE)} / ${entries.length} ШТ.`:"0 ШТ.";
    $("previous").disabled=page===0;$("next").disabled=page===maxPage;
  }
  function render() {
    if(!draft)return;
    for(const name of ["equipment","outfits","layers"]){$(name+"-tab").classList.toggle("selected",mode===name);$(name+"-tab").setAttribute("aria-pressed",String(mode===name));}
    $("outfit-tools").hidden=mode!=="outfits";
    $("layer-tools").hidden=mode!=="layers" || LAYERS.length===0;
    $("layers-toggle").textContent=draft.layers.active?"СЛОИ: ВКЛ":"СЛОИ: ВЫКЛ";
    const areas=$("areas");areas.replaceChildren();
    AREAS.forEach(name=>{const b=document.createElement("button");const worn=LAYERS.filter(l=>l.area===name && draft.layers.slots[l.name]).length;b.textContent=M.areaTitle(name).toUpperCase()+(worn?" · "+worn:"");b.classList.toggle("selected",name===area);b.setAttribute("aria-pressed",String(name===area));b.onclick=()=>{area=name;layer=(LAYERS.find(l=>l.area===name) || {}).name || layer;page=0;render();};areas.append(b);});
    const outfits=$("outfits");outfits.replaceChildren();
    for(let i=0;i<7;i++){const b=document.createElement("button");b.textContent=String(i+1).padStart(2,"0");b.title=draft.wardrobe.names[i];b.setAttribute("aria-label",draft.wardrobe.names[i]);b.classList.toggle("selected",i===outfit);b.classList.toggle("active",draft.wardrobe.active===i);b.onclick=()=>{outfit=i;render();};outfits.append(b);}
    $("outfit-name").value=draft.wardrobe.names[outfit];
    const active=draft.wardrobe.active;$("overlay-banner").hidden=active===false;
    $("overlay-text").textContent=active===false?"":"Надет «"+draft.wardrobe.names[active]+"» поверх снаряжения.";
    $("wear").textContent=active===outfit?"НАРЯД НАДЕТ":"НАДЕТЬ НАРЯД";
    const nav=$("slots");nav.replaceChildren();
    if(mode==="layers") LAYERS.filter(l=>l.area===area).forEach(l=>{const b=document.createElement("button");b.textContent=M.layerTitle(l.name).toUpperCase()+(draft.layers.slots[l.name]?" ●":"");b.classList.toggle("selected",l.name===layer);b.setAttribute("aria-pressed",String(l.name===layer));b.onclick=()=>{layer=l.name;page=0;render();};nav.append(b);});
    else M.slots.forEach(name=>{const b=document.createElement("button");b.textContent=M.labels[name].toUpperCase();b.classList.toggle("selected",name===slot);b.setAttribute("aria-pressed",String(name===slot));b.onclick=()=>{slot=name;page=0;render();};nav.append(b);});
    $("slot-label").textContent=mode==="layers"?("СЛОЙ · "+M.layerTitle(layer)).toUpperCase():M.labels[slot].toUpperCase();
    const value=visualValue(currentSlots()[currentKey()]);$("selected-name").textContent=mode==="layers"?(value?itemName(value):"Слой пуст"):mode==="outfits" && value===undefined?"Из снаряжения · "+itemName(draft.equipment[slot]):mode==="outfits" && value===false?"Скрыто в этом наряде":itemName(value);
    $("inherit").hidden=mode!=="outfits";$("remove").textContent=mode==="outfits"?"СКРЫТЬ СЛОТ":mode==="layers"?"ОЧИСТИТЬ СЛОЙ":"СНЯТЬ";
    $("semantics").textContent=mode==="layers"?"Слои надеваются друг на друга по порядку: нижний, внутренний, средний, внешний. Когда слои включены, они заменяют надетую одежду, бельё остаётся.":mode==="outfits"?"«Скрыть слот» ничего не показывает. «Из снаряжения» показывает надетую одежду.":"Снаряжение — то, что персонаж носит под нарядом.";
    renderItems();updateControls();
  }
  for(const name of ["equipment","outfits","layers"]) $(name+"-tab").onclick=()=>{mode=name;page=0;render();};
  $("layers-toggle").onclick=()=>preview(()=>{draft.layers.active=!draft.layers.active;},draft.layers.active?"Слои выключены: снова видна надетая одежда.":"Слои включены.");
  $("layers-copy").onclick=()=>preview(()=>{for(const s of M.slots){const v=visualValue(draft.equipment[s]);if(v && M.layerOf[s])draft.layers.slots[M.layerOf[s]]=v;}draft.layers.active=true;},"Надетая одежда скопирована в слои. Добавь вещи поверх и сохрани.");
  $("layers-clear").onclick=()=>confirmAction("ОЧИСТИТЬ ВСЕ СЛОИ?","Все слои очистятся, а слои выключатся. Сохрани, чтобы оставить.",()=>preview(()=>{draft.layers={active:false,slots:{}};}),"ОЧИСТИТЬ СЛОИ");
  $("search").oninput=()=>{page=0;renderItems();updateControls();};$("filter").onclick=()=>{favoritesOnly=!favoritesOnly;$("filter").textContent=favoritesOnly?"ИЗБРАННОЕ":"ВСЯ ОДЕЖДА";$("filter").setAttribute("aria-pressed",String(favoritesOnly));page=0;renderItems();updateControls();};
  $("previous").onclick=()=>{page--;renderItems();updateControls();};$("next").onclick=()=>{page++;renderItems();updateControls();};
  $("remove").onclick=()=>preview(()=>editSlot(false));
  $("inherit").onclick=()=>preview(()=>{delete currentSlots()[slot];draft.wardrobe.active=outfit;});
  $("wear").onclick=()=>preview(()=>{draft.wardrobe.active=outfit;if(draft.outfitLayers[outfit])draft.layers=M.clone(draft.outfitLayers[outfit]);});
  $("disable-overlay").onclick=()=>preview(()=>{draft.wardrobe.active=false;});
  $("capture").onclick=()=>preview(()=>{const items={};for(const s of M.slots)items[s]=visualValue(draft.equipment[s]) || false;draft.wardrobe.outfits[outfit]=items;draft.wardrobe.active=outfit;draft.outfitLayers[outfit]=Object.keys(draft.layers.slots).length?M.clone(draft.layers):null;},"Надетая одежда скопирована в наряд. Сохрани, чтобы оставить.");
  $("delete").onclick=()=>confirmAction("СБРОСИТЬ НАРЯД?","Одежда и название наряда очистятся. Надетые вещи останутся. Сохрани, чтобы применить сброс.",()=>preview(()=>{draft.wardrobe.outfits[outfit]={};draft.outfitLayers[outfit]=null;draft.wardrobe.names[outfit]=`Outfit ${outfit+1}`;if(draft.wardrobe.active===outfit)draft.wardrobe.active=false;}),"СБРОСИТЬ НАРЯД");
  $("rename").onclick=()=>{const name=$("outfit-name").value.trim();if(!name || [...name].length>48 || /[\x00-\x1f\x7f]/.test(name)){message("Название наряда — от 1 до 48 символов.","error");return;}draft.wardrobe.names[outfit]=name;render();message("Название изменено. Сохрани, чтобы оставить.");};
  $("outfit-name").onkeydown=e=>{if(e.key==="Enter"){e.preventDefault();$("rename").click();}};
  $("save").onclick=()=>{if(busy || previewPending || !dirty())return;busy=true;updateControls();message("Сохраняем образ…");emit("wardrobe:save",M.patch(baseline,draft));};
  $("close").onclick=requestClose;$("cancel").onclick=requestClose;
  $("confirm-no").onclick=()=>{$("confirm").hidden=true;pendingConfirm=null;$("cancel").focus();};
  $("confirm-yes").onclick=()=>{const action=pendingConfirm;$("confirm").hidden=true;pendingConfirm=null;if(action)action();};
  function rotate(degrees){yaw=((degrees+180)%360+360)%360-180;emit("wardrobe:orbit",{degrees:yaw});}
  $("front").onclick=()=>rotate(180);$("back").onclick=()=>rotate(0);$("rotate-left").onclick=()=>rotate(yaw-45);$("rotate-right").onclick=()=>rotate(yaw+45);
  for(const name of ["appearance","barber"]) $(name).onclick=()=>{if(busy)return;const action=()=>emit("wardrobe:appearance",{mode:name});if(dirty())confirmAction("ОТМЕНИТЬ ИЗМЕНЕНИЯ?","Редактор внешности вернёт сохранённую одежду и отменит эту примерку.",action);else action();};
  let lastActivitySent=-Infinity;
  function activity(){
    if($("room").hidden)return;
    const now=performance.now();
    if(now-lastActivitySent<2000)return;
    lastActivitySent=now;emit("wardrobe:activity");
  }
  for(const name of ["keydown","pointerdown","input","wheel"])
    document.addEventListener(name,activity,{capture:true,passive:true});
  document.addEventListener("keydown",e=>{
    if($("room").hidden)return;
    if(e.key==="Escape"){e.preventDefault();if(!$("confirm").hidden)$("confirm-no").click();else requestClose();}
    if(e.key==="Tab"){const root=$("confirm").hidden?$("room"):$("confirm");const focusable=[...root.querySelectorAll("button:not(:disabled),input,select")].filter(el=>el.offsetParent!==null);const first=focusable[0],last=focusable[focusable.length-1];if(e.shiftKey && document.activeElement===first){e.preventDefault();last?.focus();}else if(!e.shiftKey && document.activeElement===last){e.preventDefault();first?.focus();}}
  });
  Open77.on("wardrobe:open",value=>{
    baseline=M.normalize(value);draft=M.clone(baseline);catalogue=(value.catalogue || []).filter(item=>item.nonvisual !== true);lookup={};
    (value.catalogue || []).forEach(item=>{lookup[item.record.toLowerCase()]=item;if(item.tweakDbId)lookup[item.tweakDbId.toLowerCase()]=item;});
    busy=false;previewPending=false;favoritesReady=false;favorites=new Set();confirmed=null;mode="equipment";outfit=draft.wardrobe.active===false?0:draft.wardrobe.active;slot="Head";page=0;yaw=180;
    $("search").value="";favoritesOnly=false;$("filter").textContent="ВСЯ ОДЕЖДА";$("filter").setAttribute("aria-pressed","false");$("room").hidden=false;$("confirm").hidden=true;
    $("family").textContent=(value.family || "").toUpperCase()+" · "+(value.persistence==="ready"?"ГАРДЕРОБ ПЕРСОНАЖА":"ГАРДЕРОБ СЕССИИ");
    $("camera-controls").hidden=!value.orbitAvailable;render();$("search").focus();message("Загрузка каталога одежды…");
  });
  Open77.on("wardrobe:favorites",value=>{
    if(!draft)return;
    favorites=new Set(Array.isArray(value.items)?value.items:[]);favoritesReady=value.available===true;
    renderItems();updateControls();
    if(value.error)message(value.error==="favorite_limit"?"В избранном не больше 256 вещей.":"Избранное не сохранилось на этом устройстве. Попробуй после переподключения.","error");
  });
  Open77.on("wardrobe:catalogue",value=>{
    if(!draft)return;
    const first=catalogue.length===0;
    for(const item of value.items || []){if(item.nonvisual !== true)catalogue.push(item);lookup[item.record.toLowerCase()]=item;if(item.tweakDbId)lookup[item.tweakDbId.toLowerCase()]=item;}
    if(value.complete){catalogue.sort((a,b)=>catalogTitle(a).localeCompare(catalogTitle(b)));render();if(!dirty())message("Выбери одежду, чтобы примерить. Сохрани, когда образ готов.");}
    else if(first)render();
  });
  Open77.on("wardrobe:closed",()=>{$("room").hidden=true;$("confirm").hidden=true;baseline=null;draft=null;busy=false;previewPending=false;});
  Open77.on("wardrobe:status",value=>message(value.message,value.kind));
  Open77.on("wardrobe:previewResult",value=>{if(!draft)return;previewPending=false;if(!value.ok && confirmed){draft=confirmed;message(reason(value.reason),"error");}confirmed=null;render();});
  Open77.on("wardrobe:saveFailed",value=>{busy=false;updateControls();message(reason(value.reason),"error");});
  Open77.on("wardrobe:committed",value=>{if(!draft)return;busy=false;baseline=M.normalize(value.state);draft=M.clone(baseline);render();message(value.ok?"Образ сохранён.":reason(value.reason),value.ok?"success":"error");});
  Open77.on("wardrobe:probe",()=>emit("wardrobe:ready"));
  Open77.ready();
  emit("wardrobe:ready");
})();
