(() => {
  "use strict";

  const body = document.getElementById("freeroam-menu");
  const toast = document.getElementById("toast");
  let toastTimer = null;
  let state = {
    locations: [], spawns: [],
    vehicles: { catalog: [], allowCustomModels: false },
    weapons: { catalog: [], enabled: false, defaultReserve: 500, maximumReserve: 5000 },
    player: {},
  };
  let selectedSlot = 1;
  let vehicleCategory = "All";
  let weaponCategory = "All";
  let weaponSlots = [];
  let garageState = { count: 0, maximum: 0 };
  let playerState = { available: false };

  const send = (type, extra) => Open77.emit(
    "freeroam:action", Object.assign({ type }, extra || {}));
  const close = () => Open77.emit("freeroam:close", {});
  // An empty Lua table crosses the bridge as {}, not []; never iterate raw.
  const asArray = value => Array.isArray(value) ? value : [];
  const text = value => String(value || "").toLocaleLowerCase();

  function showToast(ok, message) {
    toast.textContent = message;
    toast.classList.toggle("error", !ok);
    toast.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove("show"), 3600);
  }

  // Tabs -----------------------------------------------------------------

  const navigation = [...body.querySelectorAll(".tab")];
  const pages = body.querySelector(".pages");
  function activatePage(name) {
    const page = document.getElementById("page-" + name);
    if (!page) return;
    const changed = !page.classList.contains("active");
    body.classList.toggle("animation-mode", name === "animations");
    for (const tab of navigation) {
      const active = tab.dataset.tab === name;
      tab.classList.toggle("active", active);
      if (active) tab.setAttribute("aria-current", "page");
      else tab.removeAttribute("aria-current");
    }
    for (const other of body.querySelectorAll(".page")) other.classList.toggle("active", other === page);
    if (changed) pages.scrollTop = 0;
    body.querySelector(".foot-search").hidden = !page.querySelector("input.search, #travel-search");
  }
  // Activities can also open via slash commands. Keep the same selection and
  // layout path without emitting another Lua open request.
  body.addEventListener("freeroam:navigate", event => activatePage(event.detail));
  document.getElementById("tabs").addEventListener("keydown", event => {
    const visible = navigation.filter(tab => !tab.hidden && !tab.disabled);
    const current = visible.indexOf(document.activeElement);
    if (current < 0 || !["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return;
    event.preventDefault();
    const index = event.key === "Home" ? 0 : event.key === "End" ? visible.length - 1
      : (current + (event.key === "ArrowDown" ? 1 : -1) + visible.length) % visible.length;
    visible[index].focus(); // Enter/Space activates; arrows never launch an activity.
  });

  for (const tab of body.querySelectorAll(".tab")) {
    tab.addEventListener("click", () => {
      if (tab.dataset.tab === "animations") {
        Open77.emit("animations:open", {});
        return;
      }
      if (tab.dataset.tab === "race" || tab.dataset.tab === "footrace") {
        body.classList.remove("animation-mode");
        Open77.emit("freeroam:race", { mode: tab.dataset.tab === "footrace" ? "foot" : "vehicle" });
        return;
      }
      activatePage(tab.dataset.tab);
      if (tab.dataset.tab === "weapons") send("weaponSnapshot", {});
      if (tab.dataset.tab === "pvp") Open77.emit("pvp:open", {});
    });
  }

  // Catalog rendering ----------------------------------------------------

  function categories(items) {
    return ["All", ...new Set(asArray(items).map(item => item.category || "Other"))];
  }

  function renderFilters(id, items, active, select) {
    const host = document.getElementById(id);
    const values = categories(items);
    const signature = JSON.stringify(values);
    if (host.dataset.signature === signature) {
      for (const button of host.children) {
        const chosen = button.textContent === active;
        button.classList.toggle("active", chosen);
        button.setAttribute("aria-pressed", String(chosen));
      }
      return;
    }
    host.dataset.signature = signature;
    host.replaceChildren();
    for (const category of values) {
      const button = document.createElement("button");
      button.textContent = category;
      button.classList.toggle("active", category === active);
      button.setAttribute("aria-pressed", String(category === active));
      button.addEventListener("click", () => select(category));
      host.append(button);
    }
  }

  function matches(item, category, query) {
    if (category !== "All" && item.category !== category) return false;
    if (!query) return true;
    return text(`${item.label} ${item.key} ${item.category} ${item.record}`).includes(query);
  }

  function card(item, action) {
    const button = document.createElement("button");
    button.className = "catalog-card";
    button.title = item.record || "";
    const label = document.createElement("strong");
    label.textContent = item.label || item.key;
    const meta = document.createElement("small");
    meta.textContent = item.category || "Other";
    button.append(label, meta);
    button.addEventListener("click", action);
    return button;
  }

  function emptyState(host, message, reset) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    const copy = document.createElement("p");
    copy.textContent = message;
    empty.append(copy);
    if (reset) {
      const button = document.createElement("button");
      button.className = "btn";
      button.textContent = "Сбросить поиск и фильтры";
      button.addEventListener("click", reset);
      empty.append(button);
    }
    host.append(empty);
  }

  function renderVehicles() {
    const vehicles = state.vehicles && typeof state.vehicles === "object" ? state.vehicles : {};
    const items = asArray(vehicles.catalog);
    const query = text(document.getElementById("vehicle-search").value.trim());
    const grid = document.getElementById("vehicle-grid");
    renderFilters("vehicle-filters", items, vehicleCategory, category => {
      vehicleCategory = category;
      renderVehicles();
    });
    const shown = items.filter(item => matches(item, vehicleCategory, query));
    const signature = JSON.stringify([shown, vehicleCategory, query]);
    if (grid.dataset.signature !== signature) {
      grid.dataset.signature = signature;
      grid.replaceChildren();
      grid.scrollTop = 0;
      for (const item of shown) grid.append(card(item, () => send("car", { model: item.key })));
      if (!shown.length) emptyState(grid, items.length ? "Транспорт по запросу не найден." : "На сервере не настроен транспорт.", items.length ? () => {
        vehicleCategory = "All";
        document.getElementById("vehicle-search").value = "";
        renderVehicles();
        document.getElementById("vehicle-search").focus();
      } : null);
    }
    document.getElementById("vehicle-count").textContent = `${shown.length} / ${items.length} models`;

    document.getElementById("vehicle-custom").style.display =
      vehicles.allowCustomModels ? "" : "none";
    const max = Number(vehicles.maxPerPlayer) || 0;
    const count = Number(garageState.count) || 0;
    const effectiveMax = Number(garageState.maximum) || max;
    document.getElementById("vehicle-hint").textContent = effectiveMax > 0
      ? `Choose a model to spawn. Garage: ${count} / ${effectiveMax}. Oldest replaced when full.`
      : "Выбери модель — она появится рядом. Лимита машин в гараже нет.";
    const latest = garageState.latest && typeof garageState.latest === "object"
      ? garageState.latest : null;
    const identity = latest && (latest.label || latest.record || `VEHICLE ${latest.id}`);
    document.getElementById("vehicle-latest").textContent = latest
      ? `LATEST · ${identity} · ${latest.engineOn ? "ДВИГАТЕЛЬ ВКЛ" : "ДВИГАТЕЛЬ ВЫКЛ"} · ` +
        `${latest.locked ? "LOCKED" : "UNLOCKED"} · ` +
        `${latest.lightsOn ? "ФАРЫ ВКЛ" : "ФАРЫ ВЫКЛ"}`
      : "Гараж пуст. Выбери первую машину ниже.";
  }

  function renderWeapons() {
    const weapons = state.weapons && typeof state.weapons === "object" ? state.weapons : {};
    const items = asArray(weapons.catalog);
    const query = text(document.getElementById("weapon-search").value.trim());
    const grid = document.getElementById("weapon-grid");
    renderFilters("weapon-filters", items, weaponCategory, category => {
      weaponCategory = category;
      renderWeapons();
    });
    const shown = items.filter(item => matches(item, weaponCategory, query));
    const equipped = weaponSlots.find(value => Number(value.slot) === selectedSlot) || {};
    const signature = JSON.stringify([shown, weaponCategory, query, equipped.record]);
    if (grid.dataset.signature !== signature) {
      grid.dataset.signature = signature;
      grid.replaceChildren();
      for (const item of shown) {
      const button = card(item, () => send("weaponEquip", {
        key: item.key,
        slot: selectedSlot,
      }));
      button.classList.toggle("equipped", equipped.record === item.record);
      button.setAttribute("aria-pressed", String(equipped.record === item.record));
      grid.append(button);
      }
      if (!shown.length) emptyState(grid, items.length ? "Оружие по запросу не найдено." : "На сервере не настроено оружие.", items.length ? () => {
        weaponCategory = "All";
        document.getElementById("weapon-search").value = "";
        renderWeapons();
        document.getElementById("weapon-search").focus();
      } : null);
    }
    document.getElementById("weapon-count").textContent = `${shown.length} / ${items.length} weapons`;
    document.getElementById("ammo-reserve").placeholder =
      `reserve 0-${Number(weapons.maximumReserve) || 5000}`;
    if (!document.getElementById("ammo-reserve").value)
      document.getElementById("ammo-reserve").value = String(Number(weapons.defaultReserve) || 500);
  }

  function renderLoadout() {
    const host = document.getElementById("weapon-loadout");
    host.replaceChildren();
    for (let slot = 1; slot <= 3; slot += 1) {
      const value = weaponSlots.find(item => Number(item.slot) === slot) || {};
      const row = document.createElement("button");
      row.className = "loadout-row";
      row.classList.toggle("selected", slot === selectedSlot);
      const name = document.createElement("strong");
      const record = value.record || value.tweakDbId || "";
      const configured = asArray(state.weapons && state.weapons.catalog)
        .find(item => item.record === value.record);
      const display = configured && configured.label ? configured.label : record || "Empty";
      name.textContent = `SLOT ${slot} · ${display}`;
      row.title = record;
      const status = document.createElement("small");
      const ammo = value.ammo && typeof value.ammo === "object" ? value.ammo : {};
      const flags = [value.active ? "ACTIVE" : "", value.drawn ? "DRAWN" : ""]
        .filter(Boolean).join(" · ") || "INACTIVE";
      status.textContent = Number(ammo.total) >= 0
        ? `${flags} · reserve ${ammo.reserve} · mag ${ammo.magazine}/${ammo.capacity}`
        : flags;
      row.append(name, status);
      row.addEventListener("click", () => selectSlot(slot));
      host.append(row);
    }
  }

  function selectSlot(slot) {
    selectedSlot = slot;
    for (const button of body.querySelectorAll("#weapon-slots button")) {
      button.classList.toggle("active", Number(button.dataset.slot) === slot);
      button.setAttribute("aria-pressed", String(Number(button.dataset.slot) === slot));
    }
    renderLoadout();
    renderWeapons();
  }

  function renderTravel() {
    const query = text(document.getElementById("travel-search").value.trim());
    const locations = document.getElementById("location-list");
    locations.replaceChildren();
    for (const location of asArray(state.locations)) {
      if (query && !text(`${location.label} ${location.name} ${location.district}`).includes(query)) continue;
      const button = document.createElement("button");
      const label = document.createElement("span");
      label.textContent = location.label || location.name;
      const detail = document.createElement("i");
      const p = location.position || {};
      detail.textContent = `${location.district || "Найт-Сити"} · ${Math.round(p.x)}, ${Math.round(p.y)}, ${Math.round(p.z)}`;
      button.append(label, detail);
      button.addEventListener("click", () => send("goto", { name: location.name }));
      locations.append(button);
    }
    if (!locations.childElementCount) emptyState(locations, query ? "Мест по запросу не найдено." : "Места не настроены.");

    const spawns = document.getElementById("spawn-list");
    spawns.replaceChildren();
    for (const point of asArray(state.spawns)) {
      if (query && !text(`${point.label} ${point.name}`).includes(query)) continue;
      const button = document.createElement("button");
      const label = document.createElement("span");
      label.textContent = point.label || point.name;
      const coords = document.createElement("i");
      const p = point.position || {};
      coords.textContent = `${Math.round(p.x)}, ${Math.round(p.y)}, ${Math.round(p.z)}`;
      button.append(label, coords);
      button.addEventListener("click", () => send("spawn", { name: point.name }));
      spawns.append(button);
    }
    if (!spawns.childElementCount) emptyState(spawns, query ? "Точек появления по запросу не найдено." : "Точки появления не настроены.");
  }

  function render() {
    renderVehicles();
    renderWeapons();
    renderLoadout();
    renderTravel();
    const player = state.player && typeof state.player === "object" ? state.player : {};
    document.getElementById("player-restore").style.display = player.allowRestore ? "" : "none";
    document.getElementById("godmode-controls").style.display = player.allowGodMode ? "" : "none";
    renderPlayerState();
  }

  function renderPlayerState() {
    const host = document.getElementById("player-status");
    if (!playerState.available) {
      host.textContent = "СОСТОЯНИЕ ИГРОКА НЕДОСТУПНО";
      host.classList.remove("signal");
      return;
    }
    const health = Math.round(Number(playerState.health) || 0);
    const maximum = Math.round(Number(playerState.maximumHealth) || 0);
    const armor = Math.round(Number(playerState.armor) || 0);
    host.textContent = `HEALTH ${health}/${maximum} · ARMOR ${armor} · ` +
      (playerState.godMode ? "БЕССМЕРТИЕ ВКЛ" : "БЕССМЕРТИЕ ВЫКЛ");
    host.classList.toggle("signal", playerState.godMode === true);
  }

  // Static controls ------------------------------------------------------

  document.getElementById("close").addEventListener("click", close);
  document.getElementById("vehicle-search").addEventListener("input", renderVehicles);
  document.getElementById("weapon-search").addEventListener("input", renderWeapons);
  document.getElementById("travel-search").addEventListener("input", renderTravel);
  document.getElementById("cyberware-open").addEventListener("click", () => send("cyberlab", {}));
  document.getElementById("vehicle-delete").addEventListener("click", () => send("dv", {}));
  document.getElementById("vehicle-delete-all").addEventListener("click", () => send("dv", { all: true }));
  document.getElementById("vehicle-spawn").addEventListener("click", () => {
    const record = document.getElementById("vehicle-record").value.trim();
    if (record) send("car", { model: record });
  });
  document.getElementById("vehicle-repair").addEventListener("click", () => send("vehicleRepair", {}));
  document.getElementById("vehicle-engine-on").addEventListener("click", () => send("vehicleEngine", { enabled: true }));
  document.getElementById("vehicle-engine-off").addEventListener("click", () => send("vehicleEngine", { enabled: false }));
  document.getElementById("vehicle-lock").addEventListener("click", () => send("vehicleLock", { enabled: true }));
  document.getElementById("vehicle-unlock").addEventListener("click", () => send("vehicleLock", { enabled: false }));
  document.getElementById("vehicle-lights").addEventListener("click", () => send("vehicleLights", { enabled: true }));
  document.getElementById("vehicle-lights-off").addEventListener("click", () => send("vehicleLights", { enabled: false }));

  for (const button of body.querySelectorAll("#weapon-slots button"))
    button.addEventListener("click", () => selectSlot(Number(button.dataset.slot)));
  document.getElementById("weapon-ammo").addEventListener("click", () => {
    const reserveText = document.getElementById("ammo-reserve").value.trim();
    const magazineText = document.getElementById("ammo-magazine").value.trim();
    const reserve = Number(reserveText);
    const maximum = Number(state.weapons && state.weapons.maximumReserve) || 5000;
    if (!Number.isInteger(reserve) || reserve < 0 || reserve > maximum)
      return showToast(false, `reserve must be an integer from 0 to ${maximum}`);
    const payload = { slot: selectedSlot, reserve };
    if (magazineText) {
      const magazine = Number(magazineText);
      if (!Number.isInteger(magazine) || magazine < 0)
        return showToast(false, "магазин — целое положительное число");
      payload.magazine = magazine;
    }
    send("weaponAmmo", payload);
  });
  document.getElementById("weapon-activate").addEventListener("click", () =>
    send("weaponActivate", { slot: selectedSlot }));
  document.getElementById("weapon-refresh").addEventListener("click", () => send("weaponSnapshot", {}));
  document.getElementById("weapon-holster").addEventListener("click", () => send("weaponHolster", {}));
  document.getElementById("weapon-remove").addEventListener("click", () =>
    send("weaponRemove", { slot: selectedSlot }));

  document.getElementById("coord-go").addEventListener("click", () => {
    const value = id => document.getElementById(id).value.trim();
    if (["coord-x", "coord-y", "coord-z"].some(id => !value(id)))
      return showToast(false, "Введи X, Y и Z перед перемещением.");
    const x = Number(value("coord-x"));
    const y = Number(value("coord-y"));
    const z = Number(value("coord-z"));
    const heading = Number(value("coord-h") || "0");
    if (![x, y, z, heading].every(Number.isFinite))
      return showToast(false, "неверные координаты");
    send("tpc", { x, y, z, heading });
  });
  document.getElementById("player-wardrobe").addEventListener("click", () => send("wardrobe", {}));
  document.getElementById("player-spawn").addEventListener("click", () => send("spawn", {}));
  document.getElementById("player-restore").addEventListener("click", () => send("restore", {}));
  document.getElementById("player-max-levels").addEventListener("click", () => send("maxLevels", {}));
  document.getElementById("player-revive").addEventListener("click", () => send("revive", {}));
  document.getElementById("player-god-on").addEventListener("click", () => send("godMode", { enabled: true }));
  document.getElementById("player-god-off").addEventListener("click", () => send("godMode", { enabled: false }));
  document.getElementById("player-suicide").addEventListener("click", () => send("suicide", {}));

  document.addEventListener("keydown", event => {
    if (!body.classList.contains("open")) return;
    if (event.key === "Escape") { event.preventDefault(); close(); }
    if (event.key === "/" && !body.classList.contains("animation-mode") &&
        !["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName)) {
      const input = body.querySelector(".page.active input.search, .page.active #travel-search");
      if (input) { event.preventDefault(); input.focus(); }
    }
    if (event.key === "Tab") {
      const focusable = [...body.querySelectorAll('button, input, select, summary, [tabindex="0"]')]
        .filter(element => !element.disabled && element.getClientRects().length && getComputedStyle(element).visibility !== "hidden");
      const first = focusable[0], last = focusable[focusable.length - 1];
      if (first && (!body.contains(document.activeElement) ||
          (event.shiftKey && document.activeElement === first) || (!event.shiftKey && document.activeElement === last))) {
        event.preventDefault(); (event.shiftKey ? last : first).focus();
      }
    }
  });

  // Bridge ---------------------------------------------------------------

  Open77.on("freeroam:state", payload => {
    if (payload && typeof payload === "object") state = payload;
    render();
  });
  Open77.on("freeroam:weapons", payload => {
    weaponSlots = asArray(payload && payload.slots);
    renderWeapons();
    renderLoadout();
  });
  Open77.on("freeroam:garage", payload => {
    garageState = payload && typeof payload === "object" ? payload : { count: 0, maximum: 0 };
    renderVehicles();
  });
  Open77.on("freeroam:player", payload => {
    playerState = payload && typeof payload === "object" ? payload : { available: false };
    renderPlayerState();
  });
  Open77.on("freeroam:open", () => {
    body.classList.add("open");
    const name = body.querySelector(".page.active")?.id.replace("page-", "") || "vehicles";
    activatePage(name);
    const focus = body.classList.contains("animation-mode") ? document.getElementById("anim-search") : body.querySelector(".tab.active");
    focus?.focus({ preventScroll: true });
  });
  Open77.on("freeroam:closed", () => body.classList.remove("open"));
  Open77.on("freeroam:result", payload => {
    if (payload && payload.text) showToast(payload.ok === true, payload.text);
  });
  Open77.ready();
  Open77.emit("freeroam:ready", {});
})();
