// Boots Meme Mimic: stage, game state, screens and the splash.
import { game } from './game.js';
import { audio } from './audio.js';
import { mountUI } from './ui.js';
import { CHARACTERS, portrait } from './library.js';

const app = document.getElementById('app');
const canvas = document.getElementById('stage');
const splash = document.getElementById('splash');
const fallback = document.querySelector('.fallback-stage');
const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
const started = performance.now();

let stage = null;

// MARK: Layout — phone column, tablet scale, or the iPad-style side panel on wide screens.

function layout() {
  const w = app.clientWidth, h = app.clientHeight;
  let s, side = 0;
  if (w >= 820 && w > h * 1.15) {
    s = clamp(Math.min(h / 820, w / 1280), 0.6, 1.22);
    side = Math.round(Math.min(w * 0.45, 560 * s + 64));
  } else if (w >= 700 && h >= 900) {
    s = clamp(Math.min(w / 430, h / 900), 1, 1.32);
  } else {
    s = clamp(Math.min(h / 860, w / 390), 0.74, 1);
  }
  app.style.setProperty('--u', `${s.toFixed(3)}px`);
  app.style.setProperty('--side-w', `${side}px`);
  app.classList.toggle('side', side > 0);
  stage?.setSidePanel(side);
}

// MARK: Stage

function stageState() {
  let focusID;
  switch (game.screen) {
    case 'crew': focusID = game.editingPlayerID; break;
    case 'handoff': case 'turn': case 'reveal': focusID = game.currentPlayer?.id; break;
    case 'home': focusID = game.players[0]?.id; break;
    default: focusID = game.standings[0]?.player.id;
  }
  return {
    screen: game.screen,
    members: game.players.map((p) => ({ id: p.id, color: p.color, character: p.character })),
    focusID,
    mood: game.mascotMood,
    audienceMood: game.screen === 'reveal' && game.lastResult ? (game.lastResult.total >= 62 ? 'happy' : 'idle') : 'idle',
    ranking: game.standings.map((s) => s.player.id),
    beat: game.stageBeat,
    pokes: game.pokes,
    pokeID: game.pokeID,
    homeCharacter: game.hostCharacter,
  };
}

/** The host's pick first, then the crew, then the lineup outward from the host. */
function loadOrder() {
  const ids = CHARACTERS.map((c) => c.id);
  const i = ids.indexOf(game.hostCharacter);
  const order = [game.hostCharacter, ...game.players.map((p) => p.character)];
  for (let d = 1; d < ids.length; d++) {
    order.push(ids[(i + d) % ids.length], ids[(i - d + ids.length * 2) % ids.length]);
  }
  return order;
}

let hostReady = false;
function finishSplash() {
  if (!splash || splash.classList.contains('out')) return;
  const wait = Math.max(0, 1500 - (performance.now() - started));
  setTimeout(() => {
    splash.classList.add('out');
    setTimeout(() => splash.remove(), 700);
  }, wait);
}

async function boot() {
  layout();
  new ResizeObserver(layout).observe(app);
  mountUI(document.getElementById('ui'));

  try {
    const { Stage } = await import('./stage.js');
    stage = new Stage(canvas, {
      onTapMember: (id) => game.poke(id),
      onTapShowcase: (id) => (id === game.hostCharacter ? game.poke() : game.setHostCharacter(id)),
      onSwipe: (dir) => { if (game.screen === 'home') game.cycleHostCharacter(dir); },
      onCharacterLoaded: (id) => { if (id === game.hostCharacter && !hostReady) { hostReady = true; finishSplash(); } },
    });
    stage.level = () => game.micLevelForStage;
    if (/[?&]debug\b/.test(location.search)) window.__mm = { game, stage, audio };
    layout();
    stage.sync(stageState());
    game.subscribe(() => stage.sync(stageState()));
    stage.preload(loadOrder());
    new IntersectionObserver(([entry]) => stage.setPaused(!entry.isIntersecting), { threshold: 0.05 }).observe(app);
  } catch (e) {
    console.warn('3D stage unavailable, using portraits.', e);
    app.classList.add('no-webgl');
    const show = () => {
      const id = ['handoff', 'turn', 'reveal'].includes(game.screen) ? game.currentPlayer.character
        : game.screen === 'home' ? game.hostCharacter : (game.standings[0]?.player.character ?? game.hostCharacter);
      if (fallback && fallback.dataset.id !== id) { fallback.dataset.id = id; fallback.src = portrait(id); }
    };
    show();
    game.subscribe(show);
    finishSplash();
  }
  // Never hold the splash for long, even on a slow connection.
  setTimeout(finishSplash, 7000);
}

// Browsers start audio only after a user gesture.
const unlock = () => audio.unlock();
addEventListener('pointerdown', unlock, { passive: true });
addEventListener('keydown', unlock);

// Keyboard play on computers: arrows pick a character, Space drives a turn.
addEventListener('keydown', (e) => {
  if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === 'Escape' && game.isConfirmingQuit) { game.keepPlaying(); return; }
  const t = e.target;
  if (t instanceof HTMLInputElement || t instanceof HTMLTextAreaElement) return;
  if (game.showSettings || game.showHowToPlay || game.isConfirmingQuit) return;
  if (app.getBoundingClientRect().bottom < innerHeight * 0.5) return; // reading the page below
  if (game.screen === 'home' && (e.key === 'ArrowLeft' || e.key === 'ArrowRight')) {
    e.preventDefault();
    game.cycleHostCharacter(e.key === 'ArrowRight' ? 1 : -1);
  } else if (game.screen === 'turn' && e.key === ' ' && !(t instanceof HTMLButtonElement)) {
    e.preventDefault();
    if (game.phase === 'intro') game.listen();
    else if (game.phase === 'ready') game.startTake();
    else if (game.phase === 'recording') game.stopTake();
  }
});

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
}

boot();
