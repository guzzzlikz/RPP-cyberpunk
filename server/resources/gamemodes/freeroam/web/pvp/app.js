(() => {
  'use strict';
  const $ = id => document.getElementById(`pvp-${id}`);
  const list = value => Array.isArray(value) ? value : [];
  const number = value => Number.isFinite(Number(value)) ? Number(value) : 0;
  const write = (id, value) => { $(id).textContent = String(value ?? ''); };
  const emit = (action, data = {}) => Open77.emit('pvp:action', { action, ...data });
  let state = {}, weapons = [], chosen = '', anchor = performance.now(), board = false, noticeTimer, weaponSignature = '';
  let bladeWeapons = [], bladeChosen = '', loadoutMode = 'ffa';
  const formatNames = { ffa:'FREE-FOR-ALL', blade:'КЛИНКИ FFA', '1v1':'DUEL', '2v2':'DOUBLES', '3v3':'SQUADS' };
  function open() {
    document.getElementById('freeroam-menu').dispatchEvent(new CustomEvent('freeroam:navigate', { detail: 'pvp' }));
  }
  function formatTime(ms) {
    const seconds = Math.ceil(Math.max(0,ms) / 1000);
    return `${Math.floor(seconds/60).toString().padStart(2,'0')}:${(seconds%60).toString().padStart(2,'0')}`;
  }
  function notify(payload) {
    write('notice-title', payload.title || 'PVP'); write('notice-body', payload.message);
    $('notice').hidden = false; clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => { $('notice').hidden = true; }, 3600);
  }
  function renderWeapons() {
    const query = $('weapon-search').value.trim().toLowerCase();
    const kits = list(state.arena?.kits);
    const blade = state.participant ? state.mode === 'blade' : loadoutMode === 'blade';
    const inArena = !!state.arena, locked = inArena && state.roundState !== 'buy';
    const entries = inArena ? kits : blade ? bladeWeapons : weapons;
    const selection = blade ? bladeChosen : chosen;
    for (const tab of document.querySelectorAll('[data-pvp-loadout]')) {
      tab.disabled = !!state.participant;
      tab.setAttribute('aria-pressed', String((blade ? 'blade' : 'ffa') === tab.dataset.pvpLoadout));
    }
    const signature = JSON.stringify([query,entries,inArena,state.arena?.kit,selection,locked,blade]);
    if (signature === weaponSignature) return;
    weaponSignature = signature;
    $('weapons').replaceChildren();
    for (const item of entries) {
      if (query && !`${item.label} ${item.category || ''} ${item.key}`.toLowerCase().includes(query)) continue;
      const button = document.createElement('button'); button.className = 'pvp-weapon';
      const selected = item.key === (inArena ? state.arena.kit : selection);
      button.setAttribute('aria-pressed', String(selected));
      const name = document.createElement('span'); name.textContent = item.label || item.key;
      const category = document.createElement('small'); category.textContent = selected ? 'SELECTED' : (item.category || 'СНАРЯЖЕНИЕ АРЕНЫ').toUpperCase();
      button.append(name,category);
      button.disabled = locked;
      button.addEventListener('click', () => { emit(inArena ? 'kit' : blade ? 'bladeWeapon' : 'weapon', {key:item.key}); });
      $('weapons').append(button);
    }
    if (!$('weapons').childElementCount) {
      const empty = document.createElement('p'); empty.textContent = locked ? 'Снаряжение закреплено на этот раунд.' : query ? 'Подходящего оружия нет.' : 'Загрузка арсенала сервера.';
      $('weapons').append(empty);
    }
    write('loadout-hint', blade ? 'Melee only. Choose before joining or during spawn protection; later changes apply on respawn.'
      : locked ? 'Открой /pvp в следующей фазе закупки, чтобы сменить снаряжение.'
      : inArena ? 'Фаза закупки. У обеих команд одинаковый список. Выбери, пока идёт таймер.'
      : 'Выбери основное оружие. Изменения во время боя применятся после возрождения.');
  }
  function renderRows() {
    $('rows').replaceChildren();
    for (const [index,row] of list(state.rows).entries()) {
      const tr = document.createElement('tr'); tr.classList.toggle('self', String(row.id) === String(state.playerId));
      const team = state.arena && number(row.team) > 0 ? (number(row.team) === number(state.arena.side) ? 'ALLY' : 'OPPONENT') : '';
      if (team) tr.classList.add(team.toLowerCase());
      const name = `${row.name || 'Player'}${row.bot ? ' [BOT]' : ''}${team ? ` · ${team}` : ''}`;
      for (const value of [row.rank || index+1, name, number(row.kills), number(row.deaths), number(row.assists), number(row.score)]) {
        const td = document.createElement('td'); td.textContent = String(value); tr.append(td);
      }
      $('rows').append(tr);
    }
  }
  function render() {
    const participant = state.participant === true, queued = state.playerState === 'queued';
    const arena = state.arena, me = state.self || {};
    $('hud').hidden = !participant;
    $('queue-dock').hidden = !queued || participant;
    const queueFormat = state.queueFormat || state.queuedFormat || state.queue?.format || 'ARENA';
    const current = participant ? `${formatNames[state.mode] || 'PVP'} · IN MATCH` : `${queueFormat.toUpperCase()} · QUEUED`;
    write('current-label', current); write('queue-label', current);
    write('current-detail', participant ? 'После выхода вернёшься на сохранённое место во Freeroam.' : 'Можно закрыть меню и гулять дальше.');
    $('current').hidden = !participant && !queued;
    for (const button of document.querySelectorAll('[data-pvp-format]')) button.disabled = participant || queued;
    write('population', `${number(state.instancePlayers)} players · ${number(state.instanceCount)} live instances`);
    for (const label of document.querySelectorAll('[data-pvp-queue]')) {
      const format = label.dataset.pvpQueue;
      const counts = state.arenaQueue || {};
      const item = Array.isArray(counts) ? counts.find(x => x.format === format || x.key === format) : counts[format];
      label.textContent = `${number(typeof item === 'object' ? item?.count ?? item?.players ?? item?.queued : item)} QUEUED`;
    }
    write('mode', formatNames[state.mode] || 'ARENA');
    write('objective', arena ? `ROUND ${number(arena.round)} · FIRST TO ${number(arena.target)}` : `FIRST TO ${number(state.killLimit) || 25} ELIMINATIONS`);
    const alive = list(arena?.aliveByTeam), side = number(arena?.side) || 1;
    write('match-hint', arena ? (state.roundState === 'buy' ? '/PVP · CHOOSE YOUR KIT'
      : `${number(alive[side-1])} ALLIES · ${number(alive[side===1 ? 1 : 0])} OPPONENTS ALIVE`) : state.mode === 'blade' ? 'ТОЛЬКО БЛИЖНИЙ БОЙ · CTRL РЫВОК · X ОВЕРДРАЙВ' : '');
    $('scoreline').replaceChildren();
    if (arena) {
      const side = number(arena.side) || 1, wins = list(arena.wins);
      const mine = document.createTextNode(String(number(wins[side-1])));
      const separator = document.createElement('span'); separator.textContent = 'VS';
      const theirs = document.createElement('b'); theirs.textContent = String(number(wins[side===1 ? 1 : 0]));
      $('scoreline').append(mine,separator,theirs);
    }
    write('rank', `P${number(me.rank) || '—'}`); write('kills',number(me.kills)); write('deaths',number(me.deaths)); write('assists',number(me.assists));
    write('streak', number(me.streak) >= 2 ? `${number(me.streak)} ELIMINATION STREAK` : '/PVP · СНАРЯЖЕНИЕ / ВЫХОД');
    const result = state.phase === 'results' || state.roundState === 'resolved' || state.roundState === 'standings';
    const dead = !result && ['respawning','eliminated','dead'].includes(state.playerState);
    $('death').hidden = !participant || !dead || board;
    write('death-title', state.playerState === 'eliminated' ? 'ДЛЯ ТЕБЯ РАУНД ОКОНЧЕН' : 'ELIMINATED');
    write('death-detail', state.death?.killerName ? `Eliminated by ${state.death.killerName}` : 'Скоро следующий шанс.');
    $('board').hidden = !participant || (!board && !result);
    const outcome = state.result || {};
    const victory = arena ? number(outcome.winnerSide) === number(arena.side)
      : outcome.winnerId != null && String(outcome.winnerId) === String(state.playerId);
    write('board-title', result ? (victory ? 'VICTORY' : 'МАТЧ ОКОНЧЕН') : 'ТЕКУЩИЙ СЧЁТ');
    write('board-subtitle', result
      ? (arena ? 'Итоги подтверждены сервером · после таймера возврат во Freeroam.' : 'Итоги подтверждены сервером · следующий раунд начнётся сам.')
      : state.mode === 'blade' ? 'Клинки FFA · тест ближнего боя без рейтинга.' : 'Боты помечены. На рейтинг влияют только матчи с людьми.');
    renderRows(); tick();
  }
  function tick() {
    const elapsed = Math.max(0,performance.now()-anchor);
    const remaining = Math.max(0,number(state.remainingMs)-elapsed);
    const boost = state.overdrive || {};
    const boostMs = Math.max(0,number(boost.remainingMs)-elapsed);
    const active = boost.phase === 'active' && boostMs > 0 && state.playerState === 'active';
    const cooldown = Math.max(0,number(boost.cooldownMs)-elapsed);
    const showBoost = state.participant === true && state.mode === 'blade';
    $('overdrive').hidden = !showBoost;
    $('overdrive-glow').hidden = !showBoost || !active;
    $('overdrive').dataset.phase = active ? 'active' : cooldown > 0 ? 'cooldown' : 'ready';
    write('overdrive-status', active ? `ACTIVE · ${(boostMs/1000).toFixed(1)}S`
      : cooldown > 0 ? `COOLDOWN · ${Math.ceil(cooldown/1000)}S`
      : boost.available && number(boost.charges) > 0 ? 'READY' : 'UNAVAILABLE');
    const fill = active ? boostMs / Math.max(1,number(boost.durationMs))
      : cooldown > 0 ? 1-cooldown / Math.max(1,number(boost.rechargeMs)) : boost.available ? 1 : 0;
    $('overdrive-fill').style.width = `${Math.max(0,Math.min(1,fill))*100}%`;
    write('timer',formatTime(remaining));
    write('phase', ({buy:'ЗАКУПКА',active:'LIVE',playing:'LIVE',between:'СЛЕДУЮЩИЙ РАУНД',results:'RESULTS',resolved:'RESULTS',standings:'RESULTS'})[state.roundState || state.phase] || 'PREPARING');
    $('timer').parentElement.classList.toggle('urgent',remaining < 30000 && remaining > 0);
    const protection = Math.max(0,number(state.self?.protection?.remainingMs)-elapsed);
    $('protection').hidden = !state.participant || protection <= 0;
    write('protection-time',`${Math.ceil(protection/1000)}S`);
    write('respawn', state.playerState === 'respawning' ? `RESPAWN IN ${Math.ceil(Math.max(0,number(state.death?.remainingMs)-elapsed)/1000)}` : 'ЖДЁМ СЛЕДУЮЩИЙ РАУНД');
  }
  for (const button of document.querySelectorAll('[data-pvp-format]')) button.addEventListener('click', () => {
    emit(['ffa','blade'].includes(button.dataset.pvpFormat) ? 'join' : 'queue', {format:button.dataset.pvpFormat,bots:$('bots').checked});
  });
  for (const button of document.querySelectorAll('[data-pvp-loadout]')) button.addEventListener('click', () => {
    loadoutMode = button.dataset.pvpLoadout; $('weapon-search').value = ''; renderWeapons();
  });
  $('leave').addEventListener('click', () => emit('leave'));
  $('weapon-search').addEventListener('input', renderWeapons);
  $('sound').addEventListener('change', () => emit('sound',{enabled:$('sound').checked}));
  Open77.on('pvp:open', () => { open(); emit('refresh'); });
  Open77.on('pvp:state', payload => { state = payload || {}; anchor = performance.now(); render(); renderWeapons(); });
  Open77.on('pvp:weapons', payload => { weapons = list(payload.weapons); chosen = payload.chosen || ''; bladeWeapons = list(payload.bladeWeapons); bladeChosen = payload.bladeChosen || ''; renderWeapons(); });
  Open77.on('pvp:notice', notify);
  Open77.on('pvp:board', payload => { board = payload.open === true; render(); });
  Open77.on('pvp:killfeed', payload => {
    if (!state.participant) return;
    const row = document.createElement('div'); row.className = 'pvp-feed-row';
    const killer = document.createTextNode(`${payload.killerName || payload.killer?.name || 'Environment'}${payload.killerBot ? ' [BOT]' : ''}`);
    const marker = document.createElement('span'); marker.textContent = payload.headshot ? 'HEADSHOT' : 'ELIM';
    const victim = document.createTextNode(`${payload.victimName || payload.victim?.name || 'Player'}${payload.victimBot ? ' [BOT]' : ''}`);
    row.append(killer,marker,victim); $('feed').prepend(row);
    while($('feed').childElementCount > 4) $('feed').lastElementChild.remove();
    setTimeout(() => row.remove(),5000);
  });
  setInterval(tick,100);
  Open77.emit('pvp:ready',{});
})();
