(function () {
  "use strict";

  var bridge = window.Open77;
  var $ = function (id) { return document.getElementById(id); };
  var backdrop = $("backdrop"), form = $("form"), confirmCard = $("confirm");
  var first = $("first"), last = $("last"), submit = $("submit");
  var limits = { minLength: 2, maxLength: 20 };
  var stage = null; // "form" | "confirm" | null

  function emit(event, payload) {
    if (bridge && bridge.emit) bridge.emit("rpp:" + event, payload || {});
  }

  function on(event, handler) {
    if (bridge && bridge.on) bridge.on("rpp:" + event, handler);
  }

  function setError(field, message) {
    var node = document.querySelector('.error[data-for="' + field + '"]');
    if (node) node.textContent = message || "";
    var input = field === "first" ? first : field === "last" ? last : null;
    if (input) input.classList.toggle("invalid", !!message);
  }

  function clearErrors() {
    ["first", "last", "form"].forEach(function (f) { setError(f, ""); });
  }

  // Та же проверка, что на сервере (shared/names.lua); сервер всё равно
  // проверяет ещё раз, это только подсказка до отправки.
  var NAME_RE = /^[A-Za-zА-Яа-яЁё]+(?:['-][A-Za-zА-Яа-яЁё]+)*$/;
  function check(value) {
    value = value.trim();
    if (!value) return "Поле не заполнено.";
    var length = Array.from(value).length;
    if (length < limits.minLength) return "Слишком коротко: минимум " + limits.minLength + " символа.";
    if (length > limits.maxLength) return "Слишком длинно: максимум " + limits.maxLength + " символов.";
    if (!NAME_RE.test(value)) return "Только буквы (русские или латинские), дефис и апостроф.";
    return "";
  }

  function show(which) {
    stage = which;
    backdrop.classList.remove("hidden");
    form.classList.toggle("hidden", which !== "form");
    confirmCard.classList.toggle("hidden", which !== "confirm");
  }

  function hide() {
    stage = null;
    backdrop.classList.add("hidden");
    form.classList.add("hidden");
    confirmCard.classList.add("hidden");
  }

  function close() {
    var was = stage;
    hide();
    emit("close", { stage: was });
  }

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    clearErrors();
    var e1 = check(first.value), e2 = check(last.value);
    if (e1) setError("first", e1);
    if (e2) setError("last", e2);
    if (e1 || e2) return;
    submit.disabled = true;
    emit("submit", { first: first.value.trim(), last: last.value.trim() });
    // Если сервер не ответил, кнопку можно нажать снова через 3 секунды.
    setTimeout(function () { submit.disabled = false; }, 3000);
  });

  [first, last].forEach(function (input) {
    input.addEventListener("input", function () { setError(input.id, ""); setError("form", ""); });
  });

  $("cancel").addEventListener("click", close);
  $("done").addEventListener("click", close);

  document.addEventListener("keydown", function (event) {
    if (event.key === "Escape" && stage) { event.preventDefault(); close(); }
    if (event.key === "Enter" && stage === "confirm") { event.preventDefault(); close(); }
  });

  on("askName", function (payload) {
    if (payload && payload.minLength) limits.minLength = payload.minLength;
    if (payload && payload.maxLength) limits.maxLength = payload.maxLength;
    first.maxLength = limits.maxLength;
    last.maxLength = limits.maxLength;
    clearErrors();
    submit.disabled = false;
    show("form");
    setTimeout(function () { first.focus(); }, 50);
  });

  on("error", function (payload) {
    submit.disabled = false;
    setError((payload && payload.field) || "form", (payload && payload.message) || "Ошибка.");
  });

  on("confirm", function (payload) {
    $("tag").textContent = payload.tag;
    $("name").textContent = payload.first + " " + payload.last;
    show("confirm");
    setTimeout(function () { $("done").focus(); }, 50);
  });

  on("hide", hide);

  emit("ready");
})();
