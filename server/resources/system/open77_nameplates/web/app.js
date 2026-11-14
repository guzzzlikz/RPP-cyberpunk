(() => {
  "use strict";
  const root = document.getElementById("nameplates");
  const nodes = new Map();
  // RPP: сообщения чата над головой. id игрока -> { el, until }
  const bubbles = new Map();
  const BUBBLE_MS_MIN = 4000, BUBBLE_MS_PER_CHAR = 70, BUBBLE_MS_MAX = 12000, BUBBLE_MAX_CHARS = 140;

  function renderBubble(node, data) {
    let el = node.querySelector(".chat-bubble");
    if (!el) {
      el = document.createElement("div");
      el.className = "chat-bubble";
      node.prepend(el);
    }
    el.className = "chat-bubble" + (data.kind === "me" ? " chat-bubble--me" : "");
    el.replaceChildren();
    const head = document.createElement("span");
    head.className = "chat-bubble-head";
    head.textContent = data.kind === "me" ? "// ДЕЙСТВИЕ" : "// СООБЩЕНИЕ";
    const body = document.createElement("span");
    body.className = "chat-bubble-body";
    let left = BUBBLE_MAX_CHARS;
    const parts = data.kind === "me" || !data.segments.length ? [{ text: data.text, action: data.kind === "me" }] : data.segments;
    for (const part of parts) {
      if (left <= 0) break;
      let text = String(part.text || "");
      if (text.length > left) text = text.slice(0, left - 1) + "…";
      left -= text.length;
      const span = document.createElement("span");
      if (part.action) span.className = "chat-bubble-action";
      span.textContent = text;
      body.append(span);
    }
    el.append(head, body);
    // Перезапустить анимацию появления.
    el.classList.remove("chat-bubble--in");
    void el.offsetWidth;
    el.classList.add("chat-bubble--in");
  }

  function bubble(payload = {}) {
    const id = String(payload.id || "");
    if (!id) return;
    const segments = Array.isArray(payload.segments) ? payload.segments : [];
    const text = String(payload.text || "");
    if (!text.trim()) return;
    const ms = Math.max(BUBBLE_MS_MIN, Math.min(BUBBLE_MS_MAX, text.length * BUBBLE_MS_PER_CHAR));
    const range = Math.max(1, Number(payload.range) || 20);
    const data = { kind: payload.kind === "me" ? "me" : "say", text, segments, range, until: Date.now() + ms };
    bubbles.set(id, data);
    const node = nodes.get(id);
    if (node) renderBubble(node, data);
  }

  setInterval(() => {
    const now = Date.now();
    for (const [id, data] of bubbles) {
      if (data.until > now) continue;
      bubbles.delete(id);
      const node = nodes.get(id);
      const el = node && node.querySelector(".chat-bubble");
      if (el) el.remove();
    }
  }, 250);
  const safeColor = value => /^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(String(value || ""))
    ? String(value) : "#f2f6f8";  // --op77-text

  function update(payload = {}) {
    const seen = new Set();
    for (const player of Array.isArray(payload.players) ? payload.players : []) {
      const id = String(player && player.id || "");
      if (!id) continue;
      seen.add(id);
      let node = nodes.get(id);
      if (!node) {
        node = document.createElement("div");
        node.className = "nameplate";
        const voice = document.createElement("span");
        voice.className = "nameplate-voice";
        voice.setAttribute("aria-hidden", "true");
        const name = document.createElement("span");
        name.className = "nameplate-name";
        node.append(voice, name);
        root.append(node);
        nodes.set(id, node);
        if (bubbles.has(id)) renderBubble(node, bubbles.get(id));
      }
      const x = Math.max(0, Math.min(1, Number(player.x) || 0));
      const y = Math.max(0, Math.min(1, Number(player.y) || 0));
      const distance = Math.max(0, Number(player.distance) || 0);
      node.style.left = `${x * 100}%`;
      node.style.top = `${y * 100}%`;
      node.style.setProperty("--plate-color", safeColor(player.color));
      // `alpha` is the native appear / occlusion fade (absent on older clients).
      const alpha = typeof player.alpha === "number" ? Math.max(0, Math.min(1, player.alpha)) : 1;
      node.style.setProperty("--plate-opacity", String(Math.max(.42, 1 - distance / 80) * alpha));
      node.classList.toggle("nameplate--talking", player.talking === true);
      // Пузырь чата виден только в радиусе голоса автора (шёпот / обычно / крик).
      const said = bubbles.get(id);
      const bubbleEl = node.querySelector(".chat-bubble");
      if (bubbleEl && said) bubbleEl.classList.toggle("chat-bubble--far", distance > said.range);
      node.querySelector(".nameplate-name").textContent =
        String(player.label || "Player").slice(0, 96);
    }
    for (const [id, node] of nodes) {
      if (seen.has(id)) continue;
      node.remove();
      nodes.delete(id);
    }
  }

  Open77.on("nameplates:update", update);
  Open77.on("nameplates:bubble", bubble);
  Open77.ready();
  Open77.emit("nameplates:ready", {});
})();
