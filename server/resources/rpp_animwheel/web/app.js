(function () {
  "use strict";
  var bridge = window.Open77;
  var $ = function (id) { return document.getElementById(id); };
  var SLOTS = 12, CX = 300, CY = 300, R_IN = 104, R_OUT = 292, R_LABEL = 200;
  var CATS = {
    onthemove: "В движении", postures: "Позы", gestures: "Жесты", social: "Общение", dance: "Танцы",
    emotions: "Эмоции", relaxation: "Отдых", seated: "Сидя", consumables: "Еда и напитки", work: "Работа",
    music: "Музыка", interactions: "Взаимодействие"
  };

  var open = false;
  var profiles = {}, order = [];          // каталог
  var pendingCatalog = null;              // пачки, пока не пришли все
  var slots = [];                         // [i] = { profile, label, category, missing } | false
  var category = "all";
  var drag = null;                        // { id, label, startX, startY, moved }
  var lastClick = { id: null, at: 0 };

  function emit(event, payload) { if (bridge && bridge.emit) bridge.emit("wheel:" + event, payload || {}); }
  function on(event, handler) { if (bridge && bridge.on) bridge.on("wheel:" + event, handler); }
  function esc(text) {
    return String(text == null ? "" : text).replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }
  function catLabel(id) { return CATS[id] || ""; }

  // ------------------------------------------------------------------
  // Колесо
  // ------------------------------------------------------------------
  function polar(r, deg) {
    var a = deg * Math.PI / 180;
    return [CX + r * Math.cos(a), CY + r * Math.sin(a)];
  }
  function sectorPath(i) {
    var gap = 1.2, from = -90 - 15 + i * 30 + gap, to = -90 + 15 + i * 30 - gap;
    var a = polar(R_OUT, from), b = polar(R_OUT, to), c = polar(R_IN, to), d = polar(R_IN, from);
    return "M" + a + " A" + R_OUT + " " + R_OUT + " 0 0 1 " + b + " L" + c + " A" + R_IN + " " + R_IN + " 0 0 0 " + d + " Z";
  }
  function buildWheel() {
    var svg = "";
    svg += '<circle class="ring-deco" cx="300" cy="300" r="298"/>';
    for (var i = 0; i < SLOTS; i++) svg += '<path class="sector" data-slot="' + (i + 1) + '" d="' + sectorPath(i) + '"/>';
    svg += '<circle class="ring-deco" cx="300" cy="300" r="98"/>';
    $("wheel").innerHTML = svg;
  }
  function renderSlots() {
    var html = "";
    for (var i = 0; i < SLOTS; i++) {
      var s = slots[i];
      var p = polar(R_LABEL, -90 + i * 30);
      var cls = "slot-label" + (s ? (s.missing ? " missing" : "") : " empty");
      html += '<div class="' + cls + '" style="left:' + p[0] + "px;top:" + p[1] + 'px">' +
        '<span class="num">' + String(i + 1).padStart(2, "0") + "</span>" +
        '<span class="name">' + (s ? esc(s.label) : "ПУСТО") + "</span>" +
        (s && catLabel(s.category) ? '<span class="scat">' + esc(catLabel(s.category)) + "</span>" : "") + "</div>";
      var path = document.querySelector('.sector[data-slot="' + (i + 1) + '"]');
      if (path) path.classList.toggle("filled", !!s);
    }
    $("labels").innerHTML = html;
    renderItems();
  }
  function sectorAt(x, y) {
    var el = document.elementFromPoint(x, y);
    var sector = el && el.closest ? el.closest(".sector") : null;
    return sector ? Number(sector.getAttribute("data-slot")) : 0;
  }
  function clearSectorMarks() {
    document.querySelectorAll(".sector.hover, .sector.drop-ok, .sector.drop-swap").forEach(function (el) {
      el.classList.remove("hover", "drop-ok", "drop-swap");
    });
  }
  function hoverText(slot) {
    var s = slot ? slots[slot - 1] : null;
    $("hover").textContent = slot ? (s ? s.label : "Слот " + slot + " пуст — перетащите сюда анимацию") : "Выберите слот";
  }

  // ------------------------------------------------------------------
  // Список
  // ------------------------------------------------------------------
  function pinnedSet() {
    var set = {};
    slots.forEach(function (s) { if (s) set[s.profile] = true; });
    return set;
  }
  // Где можно проиграть анимацию (из каталога open77_animations).
  var PLACES = { ground: "на земле", chair: "нужен стул", wall: "нужна стена", bed: "нужна кровать",
    counter: "нужна стойка", barstool: "нужен барный стул", ripperdoc_chair: "нужно кресло риппердока" };
  // Категории не из списка CATS (например, у анимаций NPC amb_*) — во вкладке «Прочее».
  function catKey(p) { return CATS[p.category] ? p.category : "other"; }
  function renderCats() {
    var present = {};
    order.forEach(function (id) { present[catKey(profiles[id])] = true; });
    var html = '<span class="cat' + (category === "all" ? " on" : "") + '" data-cat="all">Все</span>';
    Object.keys(CATS).forEach(function (key) {
      if (present[key]) html += '<span class="cat' + (category === key ? " on" : "") + '" data-cat="' + key + '">' + esc(CATS[key]) + "</span>";
    });
    if (present.other) html += '<span class="cat' + (category === "other" ? " on" : "") + '" data-cat="other">Прочее</span>';
    $("cats").innerHTML = html;
  }
  function renderItems() {
    var q = $("search").value.trim().toLowerCase();
    var pinned = pinnedSet();
    var shown = order.filter(function (id) {
      var p = profiles[id];
      if (category !== "all" && catKey(p) !== category) return false;
      if (!q) return true;
      return (p.label + " " + p.id + " " + catLabel(p.category)).toLowerCase().indexOf(q) >= 0;
    });
    $("count").textContent = shown.length + " / " + order.length;
    $("items").innerHTML = (shown.length ? shown.map(function (id) {
      var p = profiles[id];
      var place = PLACES[p.placement] || "";
      return '<div class="item" data-id="' + esc(id) + '"><span class="i-name">' + esc(p.label) + "</span>" +
        (pinned[id] ? '<span class="i-pin">В КОЛЕСЕ</span>' : "") +
        (place ? '<span class="i-place">' + esc(place) + "</span>" : "") +
        '<span class="i-cat">' + esc(catLabel(p.category) || p.category) + (p.once ? " · один раз" : "") + "</span></div>";
    }).join("") : '<div class="empty-list">' + (order.length ? "Ничего не найдено." : "Загрузка списка…") + "</div>");
  }
  function flash(id) {
    var el = document.querySelector('.item[data-id="' + CSS.escape(id) + '"]');
    if (!el) return;
    el.classList.add("flash");
    setTimeout(function () { el.classList.remove("flash"); }, 400);
  }

  // ------------------------------------------------------------------
  // Мышь. Окно Open77 присылает не все браузерные события (contextmenu,
  // dblclick), поэтому клик, двойной клик и ПКМ считаются по mousedown/up.
  // ------------------------------------------------------------------
  var ghost = $("ghost");
  function isRight(ev) { return ev.button === 2 || ev.which === 3; }

  document.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });

  document.addEventListener("mousedown", function (ev) {
    if (!open) return;
    if (isRight(ev)) {
      var slot = sectorAt(ev.clientX, ev.clientY);
      if (slot && slots[slot - 1]) emit("assign", { slot: slot, profile: false });
      return;
    }
    if (ev.button !== 0) return;
    var item = ev.target.closest && ev.target.closest(".item");
    if (item) {
      ev.preventDefault();
      var id = item.getAttribute("data-id");
      drag = { id: id, label: profiles[id] ? profiles[id].label : id, startX: ev.clientX, startY: ev.clientY, moved: false };
    }
  });

  document.addEventListener("mousemove", function (ev) {
    if (!open) return;
    var slot = sectorAt(ev.clientX, ev.clientY);
    clearSectorMarks();
    if (drag) {
      if (!drag.moved && Math.abs(ev.clientX - drag.startX) + Math.abs(ev.clientY - drag.startY) > 6) {
        drag.moved = true;
        ghost.textContent = drag.label;
        ghost.classList.remove("hidden");
      }
      if (drag.moved) {
        ghost.style.left = ev.clientX + "px";
        ghost.style.top = ev.clientY + "px";
        if (slot) {
          var el = document.querySelector('.sector[data-slot="' + slot + '"]');
          if (el) el.classList.add(slots[slot - 1] ? "drop-swap" : "drop-ok");
          $("hover").textContent = slots[slot - 1] ? "Заменить: " + slots[slot - 1].label : "Закрепить в слот " + slot;
        } else hoverText(0);
      }
      return;
    }
    if (slot) {
      var s = document.querySelector('.sector[data-slot="' + slot + '"]');
      if (s) s.classList.add("hover");
    }
    hoverText(slot);
  });

  document.addEventListener("mouseup", function (ev) {
    if (!open || ev.button !== 0) return;
    var d = drag;
    drag = null;
    ghost.classList.add("hidden");
    clearSectorMarks();
    var slot = sectorAt(ev.clientX, ev.clientY);
    if (d) {
      if (d.moved) {
        if (slot) emit("assign", { slot: slot, profile: d.id });
        return;
      }
      // Клик по пункту списка: второй клик подряд — проиграть.
      var now = Date.now();
      if (lastClick.id === d.id && now - lastClick.at < 400) {
        lastClick = { id: null, at: 0 };
        flash(d.id);
        emit("play", { profile: d.id, close: false });
      } else {
        lastClick = { id: d.id, at: now };
      }
      return;
    }
    if (slot) {
      var s = slots[slot - 1];
      if (s && !s.missing) emit("play", { profile: s.profile, close: true });
      return;
    }
    if (ev.target.closest && ev.target.closest("#stop")) { emit("stop"); return; }
    if (ev.target.closest && ev.target.closest("#toggleList")) { toggleList(); return; }
    var chip = ev.target.closest && ev.target.closest(".cat");
    if (chip) { category = chip.getAttribute("data-cat"); renderCats(); renderItems(); }
  });

  function toggleList() {
    var hidden = $("list").classList.toggle("hidden");
    $("toggleList").classList.toggle("on", !hidden);
    if (!hidden) { renderCats(); renderItems(); }
  }

  $("search").addEventListener("input", renderItems);

  document.addEventListener("keydown", function (ev) {
    if (!open) return;
    var key = (ev.key || "").toLowerCase();
    var typing = ev.target && ev.target.tagName === "INPUT";
    if (key === "escape") {
      if (typing && $("search").value) { $("search").value = ""; renderItems(); return; }
      close();
      return;
    }
    if (typing) return;
    if (key === "u" || key === "г") { ev.preventDefault(); close(); }
  });

  // ------------------------------------------------------------------
  // Открытие / данные
  // ------------------------------------------------------------------
  function show() {
    open = true;
    $("root").classList.remove("hidden");
    hoverText(0);
    renderSlots();
  }
  function hide() {
    open = false;
    drag = null;
    ghost.classList.add("hidden");
    clearSectorMarks();
    $("root").classList.add("hidden");
  }
  function close() {
    if (!open) return;
    hide();
    emit("close");
  }

  on("show", show);
  on("hide", hide);
  on("slots", function (p) {
    slots = [];
    var list = p && Array.isArray(p.slots) ? p.slots : [];
    for (var i = 0; i < SLOTS; i++) slots[i] = list[i] && typeof list[i] === "object" ? list[i] : false;
    renderSlots();
  });
  on("catalog", function (p) {
    if (!p || !Array.isArray(p.profiles)) return;
    if (p.batch === 1 || !pendingCatalog) pendingCatalog = [];
    pendingCatalog = pendingCatalog.concat(p.profiles);
    if (p.batch < p.total) return;
    profiles = {}; order = [];
    pendingCatalog.forEach(function (x) {
      if (!x || typeof x.id !== "string") return;
      profiles[x.id] = x;
      order.push(x.id);
    });
    pendingCatalog = null;
    order.sort(function (a, b) { return String(profiles[a].label).localeCompare(String(profiles[b].label)); });
    renderCats();
    renderItems();
  });

  buildWheel();
  renderSlots();
  emit("ready");
})();
