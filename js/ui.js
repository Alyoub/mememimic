// Every screen, ported from the SwiftUI views in EchoBloom/UI.
import { h, render } from 'preact';
import { useState, useEffect, useLayoutEffect, useRef, useReducer } from 'preact/hooks';
import htm from 'htm';
import { game, isBusy, total, MAX_PLAYERS, MIN_PLAYERS, ROUND_OPTIONS, LISTENS_PER_TURN } from './game.js';
import { audio } from './audio.js';
import { haptics } from './haptics.js';
import { Icon } from './icons.js';
import { CHARACTERS, PACKS, APP_STORE_URL, character, colorCSS, portrait, verdict } from './library.js';

const html = htm.bind(h);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const reduceMotion = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

// MARK: Shared pieces

function Scaffold({ top, bottom, cls = '' }) {
  return html`<div class="scaffold ${cls}">
    <div class="scaffold-top">${top}</div>
    <div class="scaffold-bottom"><div class="scaffold-inner">${bottom}</div></div>
  </div>`;
}

function IconButton({ icon, label, onClick, cls = '' }) {
  return html`<button class="icon-btn ${cls}" type="button" aria-label=${label} title=${label} onClick=${onClick}>
    <${Icon} name=${icon} size=${18} />
  </button>`;
}

function Chunky({ children, onClick, height = 62, disabled, cls = '', id }) {
  return html`<button id=${id} class="chunky ${height > 56 ? 'big' : ''} ${cls}" style=${{ '--h': height }} type="button" disabled=${disabled} onClick=${onClick}>
    <span class="chunky-face">${children}</span>
  </button>`;
}

function Glass({ children, onClick, height = 50, cls = '', disabled }) {
  return html`<button class="glass-btn ${cls}" style=${{ '--h': height }} type="button" disabled=${disabled} onClick=${onClick}>${children}</button>`;
}

/** One line of text that shrinks (down to 60%) to fit, like SwiftUI's minimumScaleFactor. */
function FitText({ cls, text, id }) {
  const ref = useRef(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const fit = () => {
      el.style.fontSize = '';
      const over = el.scrollWidth / Math.max(1, el.clientWidth);
      if (over > 1.01) el.style.fontSize = `${parseFloat(getComputedStyle(el).fontSize) * Math.max(0.6, 1 / over)}px`;
    };
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(el.parentElement ?? el);
    const app = document.getElementById('app');
    if (app) ro.observe(app);
    return () => ro.disconnect();
  }, [text]);
  return html`<div class=${cls} ref=${ref} id=${id}>${text}</div>`;
}

const Eyebrow = ({ text, accent }) => html`<div class="eyebrow ${accent ? 'accent' : ''}">${text}</div>`;
const Pill = ({ text, accent }) => html`<span class="pill ${accent ? 'accent' : ''}">${text}</span>`;
const PlayerDot = ({ color, size = 22 }) => html`<span class="dot" style=${{ '--c': colorCSS(color), '--d': size }}></span>`;

function PlayerChip({ player }) {
  return html`<span class="chip" style=${{ '--c': colorCSS(player.color, 0.6) }}>
    <${PlayerDot} color=${player.color} size=${20} /><span class="chip-name">${player.name}</span>
  </span>`;
}

function CharacterBadge({ id, color, size = 44, rounded }) {
  return html`<span class="badge" style=${{ '--d': size, '--r': rounded ?? size / 2, '--c': colorCSS(color), '--c35': colorCSS(color, 0.35) }}>
    <img src=${portrait(id)} alt="" width=${size} height=${size} loading="lazy" decoding="async" />
  </span>`;
}

function Wordmark() {
  return html`<div class="wordmark" aria-label="Meme Mimic">
    <span class="wm-dots" aria-hidden="true"><i></i><i></i><i></i></span><span>MEME MIMIC</span>
  </div>`;
}

const MuteButton = () => html`<${IconButton}
  icon=${game.muted ? 'speakerOff' : 'speaker'}
  label=${game.muted ? 'Turn sound effects on' : 'Turn sound effects off'}
  onClick=${() => { game.setMuted(!game.muted); haptics.select(); }} />`;

const SettingsButton = () => html`<${IconButton} icon="gear" label="Settings" onClick=${() => { game.setShowSettings(true); haptics.select(); }} />`;

/** Vertical bars for live input or a clip's loudness shape. */
function WaveBars({ values, progress = null, idle = false }) {
  const n = values.length;
  return html`<div class="wavebars ${idle ? 'idle' : ''}" aria-hidden="true">
    ${values.map((v, i) => html`<i class=${progress == null || i / n <= progress ? 'on' : ''} style=${{ height: `${Math.max(7, v * 100)}%` }}></i>`)}
  </div>`;
}

// MARK: Home

function HomeScreen() {
  return html`<${Scaffold}
    top=${html`<div class="topbar"><${Wordmark} /><div class="topbar-actions"><${MuteButton} /><${SettingsButton} /></div></div>`}
    bottom=${html`<div class="stack gap15">
      <${CharacterSelector} />
      <div class="stack gap10 center">
        <h2 class="headline">
          <span class="hl-1">Copy the sound.</span>
          <span class="hl-2"><${Burst} /><span>Win the room.</span><${Burst} mirrored /></span>
        </h2>
        <p class="subhead">A party game for 1–8 players.</p>
      </div>
      <div class="stack gap10">
        <${Chunky} height=${68} onClick=${() => game.openCrew()} id="play-btn"><${Icon} name="play" size=${20} /> Play<//>
        <${Glass} height=${56} cls="danger-stroke" onClick=${() => game.setShowHowToPlay(true)}><${Icon} name="book" size=${19} /> How to play<//>
      </div>
    </div>`} />`;
}

const Burst = ({ mirrored }) => html`<svg class="burst ${mirrored ? 'mirrored' : ''}" viewBox="0 0 24 38" aria-hidden="true">
  <rect x="2.5" y="6" width="19" height="4" rx="2" transform="rotate(-38 12 8)" /><rect x="4" y="17" width="16" height="4" rx="2" /><rect x="2.5" y="28" width="19" height="4" rx="2" transform="rotate(38 12 30)" />
</svg>`;

function CharacterSelector() {
  const current = game.hostCharacter;
  return html`<div class="selector">
    <div class="selector-row">
      <button class="arrow-btn" type="button" aria-label="Previous character" onClick=${() => game.cycleHostCharacter(-1)}><${Icon} name="chevronLeft" size=${22} /></button>
      <div class="selector-name">
        <${Eyebrow} text=${matchMedia('(pointer: coarse)').matches ? 'Swipe to choose' : 'Choose your character'} />
        <${FitText} cls="char-name" key=${current} text=${character(current).name} />
      </div>
      <button class="arrow-btn" type="button" aria-label="Next character" onClick=${() => game.cycleHostCharacter(1)}><${Icon} name="chevronRight" size=${22} /></button>
    </div>
    <div class="selector-dots" aria-hidden="true">
      ${CHARACTERS.map((c) => html`<i class=${c.id === current ? 'on' : ''}></i>`)}
    </div>
  </div>`;
}

// MARK: Crew

function CrewScreen() {
  const listRef = useRef(null);
  useEffect(() => {
    const id = game.editingPlayerID;
    if (!id || !listRef.current) return;
    const row = listRef.current.querySelector(`[data-player="${id}"]`);
    row?.scrollIntoView({ block: 'nearest', behavior: reduceMotion() ? 'auto' : 'smooth' });
  }, [game.editingPlayerID, game.players.length]);

  return html`<${Scaffold}
    top=${html`<div class="topbar">
      <${IconButton} icon="chevronLeft" label="Back" onClick=${() => game.goHome()} />
      <div class="title-block"><div class="title">Your crew</div><div class="subtitle">${game.players.length} of ${MAX_PLAYERS} players</div></div>
      <span class="icon-spacer"></span>
    </div>`}
    bottom=${html`<div class="stack gap14">
      <div class="panel crew-panel scroll" ref=${listRef}>
        <div class="stack gap8 pad12">
          ${game.players.map((p) => html`<${PlayerRow} key=${p.id} player=${p} />`)}
          ${game.players.length < MAX_PLAYERS && html`<button class="add-player" type="button" onClick=${() => game.addPlayer()}><${Icon} name="plus" size=${18} /> Add player</button>`}
        </div>
      </div>
      <${RoundsPicker} />
      <${Chunky} onClick=${() => { document.activeElement?.blur?.(); game.openPacks(); }}>Pick sound packs<//>
    </div>`} />`;
}

function PlayerRow({ player }) {
  const editing = game.editingPlayerID === player.id;
  const canRemove = game.players.length > MIN_PLAYERS;
  const inputRef = useRef(null);
  return html`<div class="player-row ${editing ? 'editing' : ''}" data-player=${player.id}>
    <div class="player-main">
      <button class="badge-btn" type="button" aria-label=${`Change character for ${player.name}, currently ${character(player.character).name}`}
        onClick=${() => { game.setEditing(editing ? null : player.id); game.poke(player.id); }}>
        <${CharacterBadge} id=${player.character} color=${player.color} size=${44} />
      </button>
      <input ref=${inputRef} class="name-input" type="text" value=${player.name} maxlength="14" placeholder="Name"
        autocomplete="off" autocapitalize="words" spellcheck="false" enterkeyhint="done" aria-label="Player name"
        onFocus=${() => { if (!editing) game.setEditing(player.id); }}
        onInput=${(e) => game.setName(player.id, e.currentTarget.value)}
        onKeyDown=${(e) => { if (e.key === 'Enter') { e.currentTarget.blur(); game.savePlayer(player.id); } }} />
      ${editing && html`<button class="save-btn" type="button" aria-label=${`Save ${player.name}`} onClick=${() => { inputRef.current?.blur(); game.savePlayer(player.id); }}><${Icon} name="check" size=${16} /></button>`}
      ${canRemove && html`<button class="remove-btn" type="button" aria-label=${`Remove ${player.name}`} onClick=${() => game.removePlayer(player.id)}><${Icon} name="x" size=${15} /></button>`}
    </div>
    ${editing && html`<div class="char-strip" role="listbox" aria-label="Characters">
      ${CHARACTERS.map((c) => {
        const selected = player.character === c.id;
        const taken = !game.isCharacterAvailable(c.id, player.id);
        return html`<button type="button" role="option" aria-selected=${selected} disabled=${taken}
          class="char-option ${selected ? 'selected' : ''} ${taken ? 'taken' : ''}"
          aria-label=${taken ? `${c.name}, already chosen` : c.name}
          onClick=${() => game.setCharacter(c.id, player.id)}>
          <${CharacterBadge} id=${c.id} color=${player.color} size=${64} rounded=${16} />
          <span>${c.name}</span>
          ${taken && html`<b class="lock"><${Icon} name="lock" size=${11} /></b>`}
        </button>`;
      })}
    </div>`}
  </div>`;
}

function RoundsPicker() {
  return html`<div class="panel rounds">
    <span class="rounds-label">Rounds</span>
    <div class="rounds-options">
      ${ROUND_OPTIONS.map((n) => html`<button type="button" class=${game.roundsTotal === n ? 'on' : ''} aria-pressed=${game.roundsTotal === n} aria-label=${`${n} rounds`} onClick=${() => game.setRounds(n)}>${n}</button>`)}
    </div>
  </div>`;
}

// MARK: Packs

function PacksScreen() {
  useEffect(() => { for (const p of PACKS) audio.load(p.prompts[0].clip).catch(() => {}); }, []);
  const count = game.selectedPacks.reduce((n, p) => n + p.prompts.length, 0);
  return html`<${Scaffold}
    top=${html`<div class="topbar">
      <${IconButton} icon="chevronLeft" label="Back" onClick=${() => game.go('crew')} />
      <div class="title-block"><div class="title">Sound packs</div><div class="subtitle">${count} sounds in the mix</div></div>
      <${MuteButton} />
    </div>`}
    bottom=${html`<div class="stack gap14">
      <div class="packs-list scroll"><div class="stack gap10 padv4">
        ${PACKS.map((p) => html`<${PackCard} key=${p.id} pack=${p} selected=${game.packIDs.has(p.id)} />`)}
      </div></div>
      <${Chunky} height=${66} onClick=${() => game.startMatch()} id="start-btn">Start the match<//>
    </div>`} />`;
}

function PackCard({ pack, selected }) {
  const [state, setState] = useState('idle'); // idle | loading | playing
  const token = useRef(0);
  const preview = async (e) => {
    e.stopPropagation();
    const t = ++token.current;
    if (!audio.isLoaded(pack.prompts[0].clip)) setState('loading');
    const secs = await game.preview(pack);
    if (t !== token.current) return;
    if (!secs) { setState('idle'); return; }
    setState('playing');
    await sleep(Math.min(Math.max(secs, 0.8), 6) * 1000);
    if (t === token.current) setState('idle');
  };
  useEffect(() => () => { token.current++; }, []);
  const tint = colorCSS(pack.tint);
  return html`<div class="pack-card ${selected ? 'selected' : ''}" style=${{ '--t': tint, '--t16': colorCSS(pack.tint, 0.16), '--t38': colorCSS(pack.tint, 0.38), '--t45': colorCSS(pack.tint, 0.45) }}
    role="checkbox" aria-checked=${selected} tabindex="0" aria-label=${`${pack.name}, ${pack.prompts.length} sounds. ${pack.blurb}`}
    onClick=${() => game.togglePack(pack.id)}
    onKeyDown=${(e) => { if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); game.togglePack(pack.id); } }}>
    <span class="pack-tile">
      <${Icon} name=${pack.icon} size=${24} />
      <span class="pack-count"><${Icon} name="waveform" size=${9} />${pack.prompts.length}</span>
    </span>
    <span class="pack-text"><span class="pack-name">${pack.name}</span><span class="pack-blurb">${pack.blurb}</span></span>
    <button class="pack-preview ${state}" type="button" aria-label=${`Preview ${pack.name}`} onClick=${preview}>
      ${state === 'loading' ? html`<span class="spinner small"></span>` : state === 'playing' ? html`<span class="eq"><i></i><i></i><i></i><i></i></span>` : html`<${Icon} name="play" size=${14} />`}
    </button>
    <span class="pack-check" aria-hidden="true"><${Icon} name=${selected ? 'check' : 'plus'} size=${14} /></span>
  </div>`;
}

// MARK: Match

function MatchTopBar() {
  return html`<div class="topbar">
    <${IconButton} icon="x" label="Quit match" onClick=${() => game.askToQuit()} />
    <${Pill} text=${`ROUND ${game.round + 1} OF ${game.roundsTotal}`} />
    <${MuteButton} />
  </div>`;
}

function TurnDots() {
  const n = game.players.length;
  return html`<div class="turn-dots" role="img" aria-label=${`Turn ${game.turn + 1} of ${n}`}>
    ${game.players.map((_, i) => {
      const p = game.players[(i + game.round) % n];
      const done = game.roundResults.has(p.id);
      const current = i === game.turn && !done;
      return html`<i class="${done ? 'done' : ''} ${current ? 'current' : ''}"></i>`;
    })}
  </div>`;
}

function HandoffScreen() {
  const player = game.currentPlayer;
  const solo = game.players.length === 1;
  const prompt = solo ? 'Copy the sound and chase your best score.'
    : game.turn === 0 && game.round === 0 ? "You're up first. Everyone else, get ready to judge." : 'Your turn to make some noise.';
  return html`<${Scaffold}
    top=${html`<${MatchTopBar} />`}
    bottom=${html`<div class="stack gap20 center">
      <div class="stack gap6 center">
        <${Eyebrow} text=${solo ? 'Your turn' : 'Pass the phone to'} />
        <${FitText} cls="handoff-name" text=${player.name} />
        <p class="body muted">${prompt}</p>
      </div>
      <${TurnDots} />
      <${Chunky} height=${66} onClick=${() => game.takeThePhone()} id="handoff-go">${solo ? "Let's go!" : `I'm ${player.name}. Let's go!`}<//>
    </div>`} />`;
}

function TurnScreen() {
  return html`<${Scaffold}
    top=${html`<div class="stack gap12 center"><${MatchTopBar} /><${PlayerChip} player=${game.currentPlayer} /></div>`}
    bottom=${html`<div class="stack gap18"><${PromptCard} /><${Controls} /></div>`} />
    ${game.phase === 'countIn' && html`<div class="countin" key=${game.countIn} aria-live="assertive">${game.countIn}</div>`}`;
}

const STATUS = {
  intro: 'Your sound', listening: 'Listen closely…', ready: 'Your turn to copy it',
  countIn: 'Get ready', recording: 'Recording, go!', analyzing: 'Judging your echo…',
};

function PromptCard() {
  const prompt = game.currentPrompt;
  const live = game.phase === 'recording' || game.phase === 'analyzing';
  const env = audio.envelope(prompt.clip, 40);
  const status = game.loadingPrompt ? 'Loading the sound…' : STATUS[game.phase];
  let bars;
  if (live) bars = html`<${WaveBars} values=${game.levelHistory} />`;
  else if (env) bars = html`<${WaveBars} values=${env} progress=${game.phase === 'listening' ? game.listenProgress : game.listensLeft < LISTENS_PER_TURN ? 1 : 0} />`;
  else bars = html`<${WaveBars} values=${new Array(40).fill(0.12)} progress=${0} idle />`;
  return html`<div class="panel prompt-card">
    <div class="stack gap6 center">
      <${Eyebrow} text=${status} accent />
      <${FitText} cls="prompt-name" text=${prompt.name} />
      <p class="body muted">${prompt.hint}</p>
    </div>
    <div class="prompt-bars">${bars}</div>
  </div>`;
}

function Controls() {
  const phase = game.phase;
  const pre = phase === 'intro' || phase === 'listening';
  return html`<div class="stack gap12 center controls">
    ${pre ? html`
      <${Chunky} height=${66} disabled=${phase === 'listening'} onClick=${() => game.listen()} id="listen-btn">
        <${Icon} name="speaker" size=${20} /> ${phase === 'listening' ? (game.loadingPrompt ? 'Loading…' : 'Playing…') : 'Play the sound'}
      <//>
      <button class="link-btn" type="button" disabled=${isBusy(phase)} onClick=${() => game.useDemoTake()}><${Icon} name="wand" size=${15} /> No mic? Use a demo take</button>
    ` : html`<div class="record-row">
      <${SideAction} icon="again" title="Hear again" detail=${`${game.listensLeft} left`} disabled=${game.listensLeft === 0 || phase !== 'ready'} onClick=${() => game.listen()} />
      <${RecordButton} />
      <${SideAction} icon="wand" title="Demo take" detail="no mic" disabled=${isBusy(phase)} onClick=${() => game.useDemoTake()} />
    </div>`}
    ${game.micDenied && html`<p class="footnote muted">Microphone is blocked for this site. Allow it from your browser's address bar, or play with demo takes.</p>`}
    ${game.micAccess === 'unavailable' && html`<p class="footnote muted">No microphone available here. You can still play with demo takes.</p>`}
  </div>`;
}

function SideAction({ icon, title, detail, disabled, onClick }) {
  return html`<button class="side-action" type="button" disabled=${disabled} onClick=${onClick} aria-label=${`${title}, ${detail}`}>
    <span class="side-circle"><${Icon} name=${icon} size=${19} /></span>
    <span class="side-title">${title}</span><span class="side-detail">${detail}</span>
  </button>`;
}

function RecordButton() {
  const recording = game.phase === 'recording';
  const busy = isBusy(game.phase) && !recording;
  const R = 47, C = 2 * Math.PI * R;
  const progress = recording ? game.recordProgress : 0;
  return html`<button class="record ${recording ? 'recording' : ''}" type="button" id="record-btn" disabled=${busy || game.takeStarting}
    aria-label=${recording ? 'Stop recording' : 'Record your take'}
    onClick=${() => (recording ? game.stopTake() : game.startTake())}>
    <span class="record-halo" style=${{ transform: `scale(${1 + game.liveLevel * 0.35})` }}></span>
    <svg class="record-ring" viewBox="0 0 112 112" aria-hidden="true">
      <circle cx="56" cy="56" r=${R} class="track" />
      <circle cx="56" cy="56" r=${R} class="progress" style=${{ strokeDasharray: C, strokeDashoffset: C * (1 - progress) }} />
    </svg>
    <span class="record-core">
      ${game.phase === 'analyzing' ? html`<span class="spinner"></span>` : html`<${Icon} name=${recording ? 'stop' : 'mic'} size=${30} />`}
    </span>
  </button>`;
}

function RevealScreen() {
  const result = game.lastResult ?? { total: 0, pitch: 0, rhythm: 0, length: 0, isDemo: true };
  const player = game.currentPlayer;
  const [shown, setShown] = useState(0);
  const [barsIn, setBarsIn] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (reduceMotion()) { setShown(result.total); setBarsIn(true); return; }
      await sleep(250);
      for (let i = 1; i <= 28; i++) {
        if (cancelled) return;
        setShown(Math.round(result.total * (1 - Math.pow(1 - i / 28, 3))));
        if (i % 3 === 0) haptics.tick();
        await sleep(28 + i * 2);
      }
      if (cancelled) return;
      setShown(result.total);
      result.total >= 62 ? haptics.success() : haptics.thump();
      setBarsIn(true);
    })();
    return () => { cancelled = true; };
  }, []);
  const rank = game.roundRankOfLastResult;
  const done = shown === result.total && barsIn;
  const next = game.nextPlayer;
  return html`<${Scaffold}
    top=${html`<${MatchTopBar} />`}
    bottom=${html`<div class="stack gap14">
      <div class="panel reveal-card">
        <div class="reveal-head">
          <${PlayerChip} player=${player} />
          ${result.isDemo ? html`<${Pill} text="DEMO SCORE" accent />`
            : rank && game.roundResults.size > 1 ? html`<${Pill} text=${rank === 1 ? 'BEST THIS ROUND' : `#${rank} THIS ROUND`} accent=${rank === 1} />` : null}
        </div>
        <div class="score ${done ? 'landed' : ''}" role="img" aria-label=${`Score ${result.total} out of 100`} id="score">
          <span class="score-num">${shown}</span><span class="score-of">/100</span>
        </div>
        <div class="verdict ${done ? 'in' : ''}">${verdict(result.total)}</div>
        <div class="stack gap10">
          <${Breakdown} title="Pitch" value=${result.pitch} show=${barsIn} />
          <${Breakdown} title="Rhythm" value=${result.rhythm} show=${barsIn} />
          <${Breakdown} title="Length" value=${result.length} show=${barsIn} />
        </div>
        ${!result.isDemo && html`<div class="row gap10">
          <${Glass} height=${44} onClick=${() => game.replayTake()}><${Icon} name="play" size=${15} /> Your take<//>
          <${Glass} height=${44} onClick=${() => game.replayPrompt()}><${Icon} name="speaker" size=${16} /> Original<//>
        </div>`}
      </div>
      <${Chunky} height=${64} onClick=${() => game.continueAfterReveal()} id="reveal-next">${next ? `Pass to ${next.name}` : 'See round results'}<//>
    </div>`} />`;
}

function Breakdown({ title, value, show }) {
  return html`<div class="breakdown" role="img" aria-label=${`${title} ${value}`}>
    <span class="bd-title">${title}</span>
    <span class="bd-track"><span class="bd-fill" style=${{ width: show ? `max(10px, ${value}%)` : '10px' }}></span></span>
    <span class="bd-value">${value}</span>
  </div>`;
}

function StandingRow({ rank, player, roundScore, change = 0, index = 0, animate }) {
  return html`<div class="standing ${rank === 1 ? 'first' : ''} ${animate ? 'animate' : ''}" style=${{ animationDelay: `${index * 60}ms` }}>
    <span class="rank">${rank}</span>
    <${PlayerDot} color=${player.color} size=${24} />
    <span class="st-name">${player.name}</span>
    ${change !== 0 && html`<span class="change ${change > 0 ? 'up' : 'down'}" aria-label=${change > 0 ? `up ${change}` : `down ${-change}`}><${Icon} name=${change > 0 ? 'up' : 'down'} size=${10} /></span>`}
    <span class="grow"></span>
    ${roundScore != null && html`<span class="round-score">+${roundScore}</span>`}
    <span class="st-total">${total(player)}</span>
  </div>`;
}

function RecapScreen() {
  let best = null;
  for (const [id, r] of game.roundResults) if (!best || r.total > best[1].total) best = [id, r];
  const bestPlayer = best && game.players.find((p) => p.id === best[0]);
  const headline = bestPlayer ? `${bestPlayer.name} nailed it with ${best[1].total}` : 'Scores are in';
  return html`<${Scaffold}
    top=${html`<${MatchTopBar} />`}
    bottom=${html`<div class="stack gap14">
      <div class="stack gap4 center">
        <${Eyebrow} text=${`Round ${game.round + 1} complete`} accent />
        <div class="recap-title">${headline}</div>
      </div>
      <div class="panel standings scroll">
        ${game.standings.map((s, i) => html`<${StandingRow} key=${s.player.id} rank=${s.rank} player=${s.player} index=${i} animate
          roundScore=${game.roundResults.get(s.player.id)?.total} change=${game.rankChange(s.player, s.rank)} />`)}
      </div>
      <${Chunky} height=${64} onClick=${() => game.continueAfterRecap()} id="recap-next">${game.isLastRound ? 'Reveal the winner' : `Start round ${game.round + 2}`}<//>
    </div>`} />`;
}

function PodiumScreen() {
  const standings = game.standings;
  const winners = standings.filter((s) => s.rank === 1).map((s) => s.player);
  return html`<${Scaffold}
    top=${html`<div class="stack gap8 center podium-top">
      <${Eyebrow} text="Final results" accent />
      <${FitText} cls="podium-title" text=${winners.length > 1 ? "It's a tie!" : `${winners[0]?.name ?? 'Someone'} wins!`} />
    </div>`}
    bottom=${html`<div class="stack gap12">
      <div class="panel standings podium-list scroll">
        ${standings.map((s, i) => html`<${StandingRow} key=${s.player.id} rank=${s.rank} player=${s.player} index=${i} />`)}
      </div>
      <${Chunky} height=${64} onClick=${() => game.startMatch()} id="rematch">Rematch<//>
      <div class="row gap10">
        <${Glass} onClick=${() => game.go('crew')}>Change crew<//>
        <${Glass} onClick=${() => game.goHome()}>Home<//>
      </div>
    </div>`} />`;
}

// MARK: Overlays

function QuitPanel() {
  return html`<div class="overlay" onClick=${(e) => { if (e.target === e.currentTarget) game.keepPlaying(); }}>
    <div class="panel dialog" role="alertdialog" aria-modal="true" aria-labelledby="quit-title">
      <span class="dialog-icon"><${Icon} name="door" size=${30} /></span>
      <div class="stack gap6 center">
        <div class="dialog-title" id="quit-title">Quit this match?</div>
        <p class="body muted">Scores from this match will be lost.</p>
      </div>
      <div class="stack gap10">
        <${Chunky} height=${56} cls="danger" onClick=${() => game.confirmQuit()}>Quit match<//>
        <${Glass} onClick=${() => game.keepPlaying()}>Keep playing<//>
      </div>
    </div>
  </div>`;
}

function Sheet({ title, onClose, children, label }) {
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    addEventListener('keydown', onKey);
    return () => removeEventListener('keydown', onKey);
  }, []);
  return html`<div class="overlay sheet-overlay" onClick=${(e) => { if (e.target === e.currentTarget) onClose(); }}>
    <div class="sheet" role="dialog" aria-modal="true" aria-label=${label ?? title}>
      <div class="sheet-head"><div class="sheet-title">${title}</div><${IconButton} icon="x" label="Close" onClick=${onClose} /></div>
      <div class="sheet-body">${children}</div>
    </div>
  </div>`;
}

function HowToPlay() {
  const steps = [
    ['ear', 'Listen', 'Everyone gets the same weird meme sound each round. You can hear it twice.'],
    ['mic', 'Imitate', 'Get close to the mic and copy it. The pitch, the rhythm, the length all count.'],
    ['trophy', 'Score & pass', 'Your character judges the echo out of 100, then the phone moves on.'],
  ];
  const close = () => game.setShowHowToPlay(false);
  return html`<${Sheet} title="How to play" onClose=${close}>
    <div class="stack gap20">
      ${steps.map(([icon, title, text], i) => html`<div class="step">
        <span class="step-icon s${i}"><${Icon} name=${icon} size=${24} /></span>
        <div><div class="step-title">${title}</div><p class="body muted">${text}</p></div>
      </div>`)}
      <p class="footnote faint">Everything stays on this device. Recordings are scored in your browser and never uploaded.</p>
      <${Chunky} onClick=${close}>Got it<//>
    </div>
  <//>`;
}

function Toggle({ icon, title, on, onChange }) {
  return html`<label class="setting-row toggle-row">
    <span class="row-label"><${Icon} name=${icon} size=${18} />${title}</span>
    <input type="checkbox" class="switch" checked=${on} onChange=${(e) => onChange(e.currentTarget.checked)} />
  </label>`;
}

function Settings() {
  const [confirmReset, setConfirmReset] = useState(false);
  const close = () => game.setShowSettings(false);
  const mic = game.micAccess;
  const micTitle = { granted: 'Microphone allowed', denied: 'Microphone blocked', unavailable: 'No microphone available', unknown: 'Microphone not asked yet' }[mic] ?? 'Microphone';
  const share = async () => {
    const url = location.href.split('#')[0];
    try {
      if (navigator.share) await navigator.share({ title: 'Meme Mimic', text: 'Play Meme Mimic with me!', url });
      else { await navigator.clipboard.writeText(url); game.flash('Link copied. Send it to your crew!'); }
    } catch { /* Sharing was cancelled. */ }
  };
  return html`<${Sheet} title="Settings" onClose=${close}>
    <div class="stack gap18">
      <section class="settings-section">
        <h3>Sound & feel</h3>
        <div class="panel settings-card">
          <${Toggle} icon="speaker" title="Sound effects" on=${!game.muted} onChange=${(v) => game.setMuted(!v)} />
          ${haptics.supported && html`<hr /><${Toggle} icon="vibrate" title="Vibration" on=${game.hapticsOn} onChange=${(v) => game.setHaptics(v)} />`}
        </div>
      </section>
      <section class="settings-section">
        <h3>Microphone</h3>
        <div class="panel settings-card">
          <div class="setting-row"><span class="row-label"><${Icon} name="mic" size=${18} />${micTitle}</span>${mic === 'granted' ? html`<span class="ok"><${Icon} name="check" size=${18} /></span>` : null}</div>
          <p class="footnote faint">${mic === 'denied' ? "To turn it on, open your browser's site settings for this page (the icon in the address bar) and allow the microphone. " : ''}Meme Mimic listens only while you record a take. Audio is scored in your browser and never uploaded.</p>
        </div>
      </section>
      <section class="settings-section">
        <h3>More</h3>
        <div class="panel settings-card">
          <a class="setting-row" href="privacy/" target="_blank" rel="noopener"><span class="row-label"><${Icon} name="shield" size=${18} />Privacy policy</span><${Icon} name="external" size=${15} /></a>
          <hr />
          <button class="setting-row" type="button" onClick=${share}><span class="row-label"><${Icon} name="share" size=${18} />Share the game</span></button>
          ${APP_STORE_URL && html`<hr /><a class="setting-row" href=${APP_STORE_URL} target="_blank" rel="noopener"><span class="row-label"><${Icon} name="apple" size=${18} />Get the iPhone app</span><${Icon} name="external" size=${15} /></a>`}
        </div>
      </section>
      <section class="settings-section">
        <h3>Crew</h3>
        <div class="panel settings-card">
          <button class="setting-row ${confirmReset ? 'danger' : ''}" type="button" onClick=${() => {
            if (confirmReset) { game.resetCrew(); setConfirmReset(false); game.flash('Crew reset.'); } else setConfirmReset(true);
          }}><span class="row-label"><${Icon} name="again" size=${18} />${confirmReset ? 'Tap again to reset' : 'Reset crew'}</span></button>
          <p class="footnote faint">Back to one player with a new color, 3 rounds and every sound pack.</p>
        </div>
      </section>
      <div class="about">
        <div>Meme Mimic for the web</div>
        <div>Characters by Quaternius (CC0)</div>
      </div>
    </div>
  <//>`;
}

function Notice() {
  return html`<div class="notice" role="status"><${Icon} name="bubble" size=${18} /><span>${game.notice}</span></div>`;
}

// MARK: Root

const SCREENS = {
  home: HomeScreen, crew: CrewScreen, packs: PacksScreen, handoff: HandoffScreen,
  turn: TurnScreen, reveal: RevealScreen, recap: RecapScreen, podium: PodiumScreen,
};

function App() {
  const [, force] = useReducer((n) => n + 1, 0);
  useEffect(() => game.subscribe(force), []);
  const Screen = SCREENS[game.screen] ?? HomeScreen;
  return html`
    <div class="screen" key=${game.screen} data-screen=${game.screen}><${Screen} /></div>
    ${game.notice && html`<${Notice} key=${game.notice} />`}
    ${game.isConfirmingQuit && html`<${QuitPanel} />`}
    ${game.showHowToPlay && html`<${HowToPlay} />`}
    ${game.showSettings && html`<${Settings} />`}
  `;
}

export function mountUI(el) {
  render(html`<${App} />`, el);
}
