(function () {
  "use strict";

  var bridge = window.Open77;
  var $ = function (id) { return document.getElementById(id); };
  var CELL = 56;
  var LEFT_WEAR = ["Head", "Face", "OuterChest", "InnerChest"];

  var state = { cols: 6, rows: 12, money: 0, items: [], weapons: [], weaponSlots: 3, wear: [], wearSlots: [], cyber: [] };
  var open = false;
  var trade = null;  // состояние обмена с сервера или null
  var box = null;    // открытое хранилище (багажник) с сервера или null
  var view = "gear";
  var drag = null;   // { item, from: "bag"|"weapon"|"wear", key, offX, offY, startX, startY, moved }

  function emit(event, payload) { if (bridge && bridge.emit) bridge.emit("inv:" + event, payload || {}); }
  function on(event, handler) { if (bridge && bridge.on) bridge.on("inv:" + event, handler); }
  function act(type, payload) { payload = payload || {}; payload.type = type; emit("action", payload); }

  function esc(text) {
    return String(text == null ? "" : text).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  function icon(name) {
    var def = window.RppIcons[name] || window.RppIcons.junk;
    return '<svg viewBox="' + def.box + '" preserveAspectRatio="xMidYMid meet"><path class="ico" d="' + def.d + '"/></svg>';
  }

  function money(value) {
    return String(Math.floor(value || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
  }

  // ------------------------------------------------------------------
  // Отрисовка
  // ------------------------------------------------------------------
  function render() {
    $("money").textContent = money(state.money);
    renderGrid();
    renderWear();
    renderWeapons();
    renderCyber();
  }

  function renderGrid() {
    var grid = $("grid");
    grid.style.width = (state.cols * CELL + 2) + "px";
    grid.style.height = (state.rows * CELL + 2) + "px";
    var used = 0;
    var html = "";
    state.items.forEach(function (it) {
      used += it.w * it.h;
      html += '<div class="item kind-' + esc(it.kind) + (it.offered ? " offered" : "") + '" data-uid="' + it.uid + '" style="left:' + (it.x * CELL + 1) +
        'px;top:' + (it.y * CELL + 1) + 'px;width:' + (it.w * CELL) + 'px;height:' + (it.h * CELL) + 'px">' +
        '<div class="box">' + icon(it.icon) + (it.w * it.h > 1 ? '<span class="name">' + esc(it.label) + "</span>" : "") +
        "</div></div>";
    });
    grid.innerHTML = html;
    $("capacity").textContent = used + " / " + state.cols * state.rows + " ячеек";
  }

  function slotHtml(label, item, extra) {
    var body = item
      ? '<div class="slot-icon">' + icon(item.icon) + '</div><div class="slot-name">' + esc(item.label) + "</div>"
      : '<span class="slot-empty">ПУСТО</span>';
    return '<span class="slot-label">' + esc(label) + '</span><div class="slot-body">' + body + "</div>" + (extra || "");
  }

  function findWorn(slot) {
    for (var i = 0; i < state.wear.length; i++) if (state.wear[i].wornSlot === slot) return state.wear[i];
    return null;
  }
  function findWeapon(slot) {
    for (var i = 0; i < state.weapons.length; i++) if (state.weapons[i].equippedSlot === slot) return state.weapons[i];
    return null;
  }

  function renderWear() {
    var left = "", right = "";
    state.wearSlots.forEach(function (row) {
      var item = findWorn(row.slot);
      var html = '<div class="slot' + (item ? " filled" : "") + '" data-where="wear" data-key="' + esc(row.slot) +
        '" data-slot="' + esc(row.slot) + '">' + slotHtml(row.label, item) + "</div>";
      if (LEFT_WEAR.indexOf(row.slot) >= 0) left += html; else right += html;
    });
    $("wearLeft").innerHTML = left;
    $("wearRight").innerHTML = right;
  }

  function renderWeapons() {
    var html = "";
    for (var slot = 1; slot <= state.weaponSlots; slot++) {
      var item = findWeapon(slot);
      html += '<div class="slot' + (item ? " filled" : "") + '" data-where="weapon" data-key="' + slot + '">' +
        slotHtml(item ? item.sub : "Слот оружия", item, '<span class="slot-num">' + slot + "</span>") + "</div>";
    }
    $("weaponSlots").innerHTML = html;
  }

  function renderCyber() {
    var zones = state.cyber || [];
    var on = 0, html = "";
    zones.forEach(function (z) {
      if (z.item) on++;
      html += '<div class="cyber ' + (z.item ? "on" : "empty") + '"><span class="cz">' + esc(z.label) + "</span>" +
        (z.item
          ? '<span class="cn">' + esc(z.item.name) + "</span>" + (z.item.grade ? '<span class="cg">Класс: ' + esc(z.item.grade) + "</span>" : "")
          : '<span class="cn">НЕ УСТАНОВЛЕНО</span>') + "</div>";
    });
    $("cyberGrid").innerHTML = html;
    $("cyberCount").textContent = on + " / " + zones.length;
  }

  function setView(next) {
    view = next;
    var t = view === "trade", b = view === "container";
    $("viewGear").classList.toggle("hidden", view !== "gear");
    $("viewCyber").classList.toggle("hidden", view !== "cyber");
    $("viewTrade").classList.toggle("hidden", !t);
    $("viewContainer").classList.toggle("hidden", !b);
    $("switchView").classList.toggle("hidden", t || b);
    $("leftTitle").textContent = t ? "Обмен" : b ? (box && box.label || "Хранилище") : view === "gear" ? "Экипировка" : "Киберимпланты";
    $("leftHint").textContent = t ? "Обмен произойдёт, когда оба нажмут «Готов»"
      : b ? "Вещи здесь видят все, у кого есть доступ"
      : view === "gear" ? "ПКМ или клик по предмету: снять или выбросить" : "Установленные импланты по зонам тела";
    document.querySelectorAll(".switch-opt").forEach(function (el) {
      el.classList.toggle("active", el.getAttribute("data-view") === view);
    });
    hideMenu();
  }

  // ------------------------------------------------------------------
  // Поиск предметов
  // ------------------------------------------------------------------
  function bagItem(uid) {
    for (var i = 0; i < state.items.length; i++) if (state.items[i].uid === uid) return state.items[i];
    return null;
  }

  function lookup(where, key) {
    if (where === "bag") return bagItem(Number(key));
    if (where === "weapon") return findWeapon(Number(key));
    if (where === "wear") return findWorn(key);
    return null;
  }

  function showInfo(item) {
    if (!item) {
      $("info").innerHTML = '<span class="info-name">Наведите на предмет</span><span class="info-sub">ЛКМ — перетащить, ПКМ — действия</span>';
      return;
    }
    var kind = window.RppKinds[item.kind] || "";
    var sub = [item.sub || kind, item.w + "×" + item.h];
    if (item.price) sub.push("≈ " + item.price + " €$");
    $("info").innerHTML = '<span class="info-name">' + esc(item.label) + '</span><span class="info-sub">' + esc(sub.join(" · ")) + "</span>";
  }

  // ------------------------------------------------------------------
  // Меню ПКМ
  // ------------------------------------------------------------------
  var menu = $("menu"), submenu = $("submenu");

  function hideMenu() {
    menu.classList.add("hidden");
    submenu.classList.add("hidden");
  }

  function place(el, x, y) {
    el.classList.remove("hidden");
    var w = el.offsetWidth, h = el.offsetHeight;
    el.style.left = Math.min(x, window.innerWidth - w - 8) + "px";
    el.style.top = Math.min(y, window.innerHeight - h - 8) + "px";
  }

  function entry(label, action, opts) {
    opts = opts || {};
    return { label: label, action: action, sub: opts.sub, hint: opts.hint, danger: opts.danger, submenu: opts.submenu };
  }

  function buildMenu(el, title, entries) {
    el.innerHTML = (title ? '<div class="mh">' + esc(title) + "</div>" : "") + entries.map(function (e, i) {
      return '<div class="mi' + (e.danger ? " danger" : "") + '" data-i="' + i + '"><span>' + esc(e.label) + "</span>" +
        (e.hint ? "<small>" + esc(e.hint) + "</small>" : e.submenu ? "<small>▸</small>" : "") + "</div>";
    }).join("");
    el._entries = entries;
  }

  function showMenu(x, y, where, key) {
    var item = lookup(where, key);
    if (!item) return;
    var entries = [];
    if (trade && where === "bag") {
      // Во время обмена из рюкзака можно только предлагать.
      if (item.offered) entries.push(entry("Убрать из обмена", function () { act("tradeRemove", { uid: item.uid }); }));
      else entries.push(entry("Предложить в обмен", function () { act("tradeAdd", { uid: item.uid }); }));
    } else if (trade) {
      return; // экипированное во время обмена не трогаем
    } else if (box && where === "bag") {
      entries.push(entry("Положить: " + (box.label || "хранилище"), function () { act("containerPut", { uid: item.uid }); }));
      entries.push(entry("Выбросить", function () { act("drop", { where: "bag", key: item.uid }); }, { danger: true }));
    } else if (where === "bag") {
      if (item.kind === "weapon") {
        entries.push(entry("Экипировать", null, { submenu: weaponSlotEntries(item) }));
      } else if (item.kind === "clothing") {
        entries.push(entry("Надеть", function () { act("equipClothing", { uid: item.uid }); }));
      }
      entries.push(entry("Выбросить", function () { act("drop", { where: "bag", key: item.uid }); }, { danger: true }));
    } else {
      entries.push(entry("Снять", function () { act("unequip", { where: where, key: key }); }));
      entries.push(entry("Выбросить", function () { act("drop", { where: where, key: key }); }, { danger: true }));
    }
    buildMenu(menu, item.label, entries);
    submenu.classList.add("hidden");
    place(menu, x, y);
  }

  function weaponSlotEntries(item) {
    var list = [];
    for (var slot = 1; slot <= state.weaponSlots; slot++) {
      (function (s) {
        var current = findWeapon(s);
        list.push(entry("Слот " + s, function () { act("equipWeapon", { uid: item.uid, slot: s }); },
          { hint: current ? "замена: " + current.label : "свободен" }));
      })(slot);
    }
    return list;
  }

  function openSubmenu(row, entries) {
    buildMenu(submenu, "Слот оружия", entries);
    var rect = row.getBoundingClientRect();
    submenu.classList.remove("hidden");
    var x = rect.right + 2;
    if (x + submenu.offsetWidth > window.innerWidth - 8) x = menu.getBoundingClientRect().left - submenu.offsetWidth - 2;
    place(submenu, x, rect.top - 4);
    Array.prototype.forEach.call(menu.querySelectorAll(".mi"), function (el) { el.classList.toggle("open", el === row); });
  }

  function menuEvents(el) {
    el.addEventListener("mouseover", function (ev) {
      var row = ev.target.closest(".mi");
      if (!row || el !== menu) return;
      var e = el._entries[Number(row.getAttribute("data-i"))];
      if (e && e.submenu) openSubmenu(row, e.submenu);
      else {
        submenu.classList.add("hidden");
        Array.prototype.forEach.call(menu.querySelectorAll(".mi"), function (r) { r.classList.remove("open"); });
      }
    });
    el.addEventListener("mousedown", function (ev) { ev.stopPropagation(); });
    el.addEventListener("pointerdown", function (ev) { ev.stopPropagation(); });
    el.addEventListener("mouseup", function (ev) {
      ev.stopPropagation();
      if (ev.button !== 0) return;
      var row = ev.target.closest(".mi");
      if (!row) return;
      var e = el._entries[Number(row.getAttribute("data-i"))];
      if (!e) return;
      if (e.submenu) { openSubmenu(row, e.submenu); return; }
      hideMenu();
      if (e.action) e.action();
    });
  }
  menuEvents(menu);
  menuEvents(submenu);

  // ------------------------------------------------------------------
  // Мышь: наведение, ПКМ, перетаскивание
  // ------------------------------------------------------------------
  function targetOf(el) {
    var it = el.closest(".item");
    if (it) return { where: "bag", key: Number(it.getAttribute("data-uid")), el: it };
    var slot = el.closest(".slot");
    if (slot) return { where: slot.getAttribute("data-where"), key: slot.getAttribute("data-key"), el: slot };
    return null;
  }

  document.addEventListener("mouseover", function (ev) {
    var t = targetOf(ev.target);
    if (drag) return;
    showInfo(t ? lookup(t.where, t.key) : null);
  });

  // Окно Open77 не всегда присылает событие contextmenu, поэтому меню
  // открывается по самому нажатию правой кнопки (mousedown / pointerdown /
  // mouseup / contextmenu — что придёт первым, повтор в течение 300 мс игнорируется).
  var lastRight = 0;
  function rightClick(ev) {
    if (ev.cancelable) ev.preventDefault();
    if (!open || drag) return;
    var now = Date.now();
    if (now - lastRight < 300) return;
    lastRight = now;
    var el = document.elementFromPoint(ev.clientX, ev.clientY) || ev.target;
    if (el && el.closest && el.closest(".menu")) return;
    var t = el && el.closest ? targetOf(el) : null;
    if (t && lookup(t.where, t.key)) showMenu(ev.clientX, ev.clientY, t.where, t.key);
    else hideMenu();
  }
  function isRight(ev) { return ev.button === 2 || (ev.buttons & 2) === 2 || ev.which === 3; }
  document.addEventListener("contextmenu", function (ev) { rightClick(ev); });
  document.addEventListener("pointerdown", function (ev) { if (isRight(ev)) rightClick(ev); });
  document.addEventListener("mouseup", function (ev) { if (ev.button === 2) rightClick(ev); });

  var ghost = $("ghost");
  var preview = null;

  function clearHighlights() {
    if (preview) { preview.remove(); preview = null; }
    document.querySelectorAll(".slot.drop-ok, .slot.drop-bad, .trade-col.drop-ok, .trade-col.drop-bad").forEach(function (el) { el.classList.remove("drop-ok", "drop-bad"); });
  }

  function overlaps(x, y, w, h, ignoreUid) {
    if (x < 0 || y < 0 || x + w > state.cols || y + h > state.rows) return true;
    return state.items.some(function (o) {
      return o.uid !== ignoreUid && x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h;
    });
  }

  function gridCell(clientX, clientY) {
    var rect = $("grid").getBoundingClientRect();
    if (clientX < rect.left || clientX > rect.right || clientY < rect.top || clientY > rect.bottom) return null;
    return {
      x: Math.round((clientX - rect.left - 1 - drag.offX) / CELL),
      y: Math.round((clientY - rect.top - 1 - drag.offY) / CELL),
    };
  }

  // Куда можно бросить перетаскиваемый предмет.
  function dropTarget(ev) {
    var item = drag.item;
    var cell = gridCell(ev.clientX, ev.clientY);
    if (cell) {
      // Край сетки: предмет прижимается внутрь, а не отклоняется.
      var x = Math.max(0, Math.min(state.cols - item.w, cell.x));
      var y = Math.max(0, Math.min(state.rows - item.h, cell.y));
      var self = drag.from === "bag" ? item.uid : -1;
      if (!overlaps(x, y, item.w, item.h, self)) return { type: "grid", x: x, y: y, ok: true };
      // Поверх одного другого предмета — обмен местами (та же проверка, что на сервере).
      if (drag.from === "bag") {
        var hits = state.items.filter(function (o) {
          return o.uid !== item.uid && x < o.x + o.w && o.x < x + item.w && y < o.y + o.h && o.y < y + item.h;
        });
        if (hits.length === 1) {
          var b = hits[0];
          var rest = state.items.filter(function (o) { return o.uid !== item.uid && o.uid !== b.uid; })
            .concat([{ uid: item.uid, x: x, y: y, w: item.w, h: item.h }]);
          var fitsBack = item.x + b.w <= state.cols && item.y + b.h <= state.rows && !rest.some(function (o) {
            return item.x < o.x + o.w && o.x < item.x + b.w && item.y < o.y + o.h && o.y < item.y + b.h;
          });
          if (fitsBack) return { type: "grid", x: x, y: y, ok: true, swap: b };
        }
      }
      return { type: "grid", x: x, y: y, ok: false };
    }
    var el = document.elementFromPoint(ev.clientX, ev.clientY);
    if (trade && drag.from === "bag") {
      var zone = el && el.closest("#tradeMine");
      if (zone) return { type: "trade", el: zone, ok: !item.offered && !trade.mine.ready };
      return null;
    }
    if (box && drag.from === "bag") {
      var boxZone = el && el.closest("#boxZone");
      if (boxZone) return { type: "box", el: boxZone, ok: box.used + item.w * item.h <= box.capacity };
    }
    var slot = el && el.closest(".slot");
    if (slot && drag.from === "bag") {
      var where = slot.getAttribute("data-where");
      if (where === "weapon") return { type: "weapon", el: slot, slot: Number(slot.getAttribute("data-key")), ok: item.kind === "weapon" };
      if (where === "wear") return { type: "wear", el: slot, ok: item.kind === "clothing" && item.slot === slot.getAttribute("data-key") };
    }
    return null;
  }

  document.addEventListener("mousedown", function (ev) {
    if (!open) return;
    if (isRight(ev)) { rightClick(ev); return; }
    if (ev.button !== 0) { hideMenu(); return; }
    hideMenu();
    if (ev.target.closest && ev.target.closest("button")) return;
    var t = targetOf(ev.target);
    if (t) ev.preventDefault(); // не выделять текст и не запускать «родное» перетаскивание
    if (!t) return;
    var item = lookup(t.where, t.key);
    if (!item) return;
    var rect = t.el.getBoundingClientRect();
    drag = {
      item: item, from: t.where, key: t.key, el: t.el,
      offX: t.where === "bag" ? ev.clientX - rect.left : (item.w * CELL) / 2,
      offY: t.where === "bag" ? ev.clientY - rect.top : (item.h * CELL) / 2,
      startX: ev.clientX, startY: ev.clientY, moved: false,
    };
  });

  document.addEventListener("mousemove", function (ev) {
    if (!drag) return;
    if (!drag.moved) {
      if (Math.abs(ev.clientX - drag.startX) + Math.abs(ev.clientY - drag.startY) < 6) return;
      drag.moved = true;
      if (drag.from === "bag") drag.el.classList.add("dragging");
      ghost.innerHTML = '<div class="box">' + icon(drag.item.icon) + "</div>";
      ghost.style.width = drag.item.w * CELL + "px";
      ghost.style.height = drag.item.h * CELL + "px";
      ghost.classList.remove("hidden");
    }
    ghost.style.left = ev.clientX - drag.offX + "px";
    ghost.style.top = ev.clientY - drag.offY + "px";
    clearHighlights();
    var target = dropTarget(ev);
    if (!target) return;
    if (target.type === "grid") {
      preview = document.createElement("div");
      preview.className = "preview" + (!target.ok ? " bad" : target.swap ? " swap" : "");
      preview.style.left = target.x * CELL + 1 + "px";
      preview.style.top = target.y * CELL + 1 + "px";
      preview.style.width = drag.item.w * CELL + "px";
      preview.style.height = drag.item.h * CELL + "px";
      $("grid").appendChild(preview);
    } else {
      target.el.classList.add(target.ok ? "drop-ok" : "drop-bad");
    }
  });

  document.addEventListener("mouseup", function (ev) {
    if (!drag || ev.button !== 0) return;
    var d = drag;
    // Место сброса считается до обнуления drag: dropTarget читает drag.
    var target = null;
    try { target = d.moved ? dropTarget(ev) : null; } catch (err) { target = null; }
    drag = null;
    ghost.classList.add("hidden");
    if (d.el) d.el.classList.remove("dragging");
    clearHighlights();
    if (!d.moved) {
      // Клик по экипированному предмету открывает меню «Снять / Выбросить».
      if (d.from !== "bag") showMenu(ev.clientX, ev.clientY, d.from, d.key);
      return;
    }
    if (!target || !target.ok) return;
    if (target.type === "grid") {
      if (d.from === "bag") {
        if (target.x !== d.item.x || target.y !== d.item.y) {
          // Сразу на экране, сервер подтвердит или вернёт как было.
          if (target.swap) { target.swap.x = d.item.x; target.swap.y = d.item.y; }
          d.item.x = target.x; d.item.y = target.y;
          renderGrid();
          act("move", { uid: d.item.uid, x: target.x, y: target.y });
        }
      } else {
        act("unequip", { where: d.from, key: d.key });
      }
    } else if (target.type === "trade") {
      act("tradeAdd", { uid: d.item.uid });
    } else if (target.type === "box") {
      act("containerPut", { uid: d.item.uid });
    } else if (target.type === "weapon") {
      act("equipWeapon", { uid: d.item.uid, slot: target.slot });
    } else if (target.type === "wear") {
      act("equipClothing", { uid: d.item.uid });
    }
  });

  // ------------------------------------------------------------------
  // Открытие / закрытие
  // ------------------------------------------------------------------
  function show(next) {
    if (next && typeof next === "object" && next.items) state = next;
    open = true;
    $("root").classList.remove("hidden");
    render();
  }

  function hide() {
    open = false;
    drag = null;
    hideMenu();
    clearHighlights();
    ghost.classList.add("hidden");
    $("root").classList.add("hidden");
  }

  function close() {
    if (!open) return;
    hide();
    emit("close");
  }

  $("close").addEventListener("click", close);
  $("sort").addEventListener("click", function () { act("sort"); });
  $("switchView").addEventListener("click", function () { setView(view === "gear" ? "cyber" : "gear"); });
  document.addEventListener("keydown", function (ev) {
    if (!open) return;
    var key = (ev.key || "").toLowerCase();
    var typing = ev.target && ev.target.tagName === "INPUT";
    if (typing && key === "enter") { ev.preventDefault(); setTradeMoney(); return; }
    if (typing && key !== "escape") return; // в поле суммы буквы и цифры — это ввод
    if (key === "escape") {
      if (!menu.classList.contains("hidden")) { hideMenu(); return; }
      close();
    } else if (key === "i" || key === "ш" || key === "tab") {
      ev.preventDefault();
      close();
    }
  });

  // ------------------------------------------------------------------
  // Обмен
  // ------------------------------------------------------------------
  var tradeTimer = null, countdownEnd = 0;

  function tradeItemHtml(it, mine) {
    return '<div class="trade-item"' + (mine ? ' data-uid="' + it.uid + '" title="Нажмите, чтобы убрать из обмена"' : "") + ">" +
      icon(it.icon) + '<div><div class="ti-name">' + esc(it.label) + '</div><div class="ti-sub">' +
      esc((it.sub || window.RppKinds[it.kind] || "") + " · " + it.w + "×" + it.h) + "</div></div></div>";
  }

  function tradeStatus() {
    var el = $("tradeStatus");
    if (!trade) return;
    var left = countdownEnd ? Math.max(0, (countdownEnd - Date.now()) / 1000) : 0;
    el.classList.toggle("count", !!countdownEnd);
    if (countdownEnd) el.textContent = "ОБМЕН ЧЕРЕЗ " + Math.ceil(left) + "…  (снимите «Готов», чтобы остановить)";
    else if (trade.mine.ready && !trade.theirs.ready) el.textContent = "Вы готовы. Ждём партнёра. Пока вы готовы, предложение менять нельзя.";
    else if (!trade.mine.ready && trade.theirs.ready) el.textContent = "Партнёр готов. Проверьте, что он отдаёт, и нажмите «Готов».";
    else el.textContent = "Перетащите вещи из рюкзака в «Вы отдаёте» или нажмите на них ПКМ. Любое изменение сбрасывает готовность.";
  }

  function renderTrade() {
    if (!trade) return;
    $("tradePartner").textContent = String(trade.partner || "ПАРТНЁР").toUpperCase() + " ОТДАЁТ";
    $("tradeMineList").innerHTML = trade.mine.items.length
      ? trade.mine.items.map(function (it) { return tradeItemHtml(it, true); }).join("")
      : '<div class="trade-empty">Пусто. Перетащите сюда вещи из рюкзака.</div>';
    $("tradeTheirsList").innerHTML = trade.theirs.items.length
      ? trade.theirs.items.map(function (it) { return tradeItemHtml(it, false); }).join("")
      : '<div class="trade-empty">Партнёр пока ничего не положил.</div>';
    $("tradeTheirsMoney").textContent = money(trade.theirs.money);
    var input = $("tradeMoney");
    if (document.activeElement !== input) input.value = String(trade.mine.money || 0);
    input.disabled = trade.mine.ready;
    $("tradeMoneySet").disabled = trade.mine.ready;
    $("mineReady").classList.toggle("on", trade.mine.ready);
    $("mineReady").textContent = trade.mine.ready ? "ГОТОВ" : "НЕ ГОТОВ";
    $("theirsReady").classList.toggle("on", trade.theirs.ready);
    $("theirsReady").textContent = trade.theirs.ready ? "ГОТОВ" : "НЕ ГОТОВ";
    var btn = $("tradeReady");
    btn.classList.toggle("on", trade.mine.ready);
    btn.textContent = trade.mine.ready ? "Готов ✓ (отменить)" : "Готов";
    countdownEnd = typeof trade.countdown === "number" ? Date.now() + trade.countdown * 1000 : 0;
    if (tradeTimer) { clearInterval(tradeTimer); tradeTimer = null; }
    if (countdownEnd) tradeTimer = setInterval(tradeStatus, 200);
    tradeStatus();
  }

  function setTradeMoney() {
    if (!trade || trade.mine.ready) return;
    var value = Math.floor(Number($("tradeMoney").value) || 0);
    if (value < 0) value = 0;
    act("tradeMoney", { amount: value });
    $("tradeMoney").blur();
  }

  $("tradeMoneySet").addEventListener("click", setTradeMoney);
  $("tradeReady").addEventListener("click", function () { if (trade) act("tradeReady", { ready: !trade.mine.ready }); });
  $("tradeCancel").addEventListener("click", function () { if (trade) act("tradeCancel"); });
  $("tradeMineList").addEventListener("click", function (ev) {
    var row = ev.target.closest(".trade-item");
    if (!row || !trade || trade.mine.ready) return;
    act("tradeRemove", { uid: Number(row.getAttribute("data-uid")) });
  });

  on("trade", function (next) {
    if (!next || !next.mine) return;
    var first = !trade;
    trade = next;
    if (first) setView("trade");
    renderTrade();
  });
  on("tradeClosed", function () {
    trade = null;
    countdownEnd = 0;
    if (tradeTimer) { clearInterval(tradeTimer); tradeTimer = null; }
    setView("gear");
  });

  // ------------------------------------------------------------------
  // Хранилище (багажник)
  // ------------------------------------------------------------------
  function renderBox() {
    if (!box) return;
    $("boxLabel").textContent = String(box.label || "Хранилище").toUpperCase();
    $("boxUsed").textContent = box.used + " / " + box.capacity + " ячеек";
    $("leftTitle").textContent = box.label || "Хранилище";
    $("boxList").innerHTML = box.items.length
      ? box.items.map(function (it) {
          return '<div class="trade-item" data-uid="' + it.uid + '" title="Нажмите, чтобы забрать в рюкзак">' +
            icon(it.icon) + '<div><div class="ti-name">' + esc(it.label) + '</div><div class="ti-sub">' +
            esc((it.sub || window.RppKinds[it.kind] || "") + " · " + it.w + "×" + it.h) + "</div></div></div>";
        }).join("")
      : '<div class="trade-empty">Пусто. Перетащите сюда вещи из рюкзака.</div>';
  }
  $("boxList").addEventListener("click", function (ev) {
    var row = ev.target.closest(".trade-item");
    if (!row || !box) return;
    act("containerTake", { uid: Number(row.getAttribute("data-uid")) });
  });
  $("boxClose").addEventListener("click", function () { if (box) act("containerClose"); });
  on("container", function (next) {
    if (!next || !next.items) return;
    var first = !box;
    box = next;
    if (first) setView("container");
    renderBox();
  });
  on("containerClosed", function () {
    box = null;
    if (view === "container") setView("gear");
  });

  on("show", show);
  on("hide", hide);
  on("state", function (next) {
    if (!next || !next.items) return;
    state = next;
    if (open && !drag) render();
  });

  emit("ready");
})();
