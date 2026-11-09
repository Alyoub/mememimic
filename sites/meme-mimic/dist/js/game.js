// The whole match as a state machine, ported from Game/GameModel.swift:
// home → crew → packs → [handoff → turn → reveal] × players → recap … → podium.
import { audio } from './audio.js';
import * as analyzer from './analyzer.js';
import { haptics } from './haptics.js';
import { COLORS, CHARACTERS, PACKS, DEFAULT_CHARACTER, character, competitionRanks } from './library.js';

export const MIN_PLAYERS = 1;
export const MAX_PLAYERS = 8;
export const ROUND_OPTIONS = [1, 3, 5];
export const LISTENS_PER_TURN = 2;
const STORAGE_KEY = 'memeMimic.web.setup.v1';
const BUSY = new Set(['listening', 'countIn', 'recording', 'analyzing']);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const uid = () => (crypto.randomUUID ? crypto.randomUUID() : `p${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`);
const shuffle = (a) => { const b = a.slice(); for (let i = b.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [b[i], b[j]] = [b[j], b[i]]; } return b; };
const randomColor = (used) => { const free = COLORS.filter((c) => !used.has(c.id)); const pool = free.length ? free : COLORS; return pool[Math.floor(Math.random() * pool.length)].id; };

export const isBusy = (phase) => BUSY.has(phase);
export const total = (p) => p.roundScores.reduce((a, b) => a + b, 0);

class Game {
  constructor() {
    this.listeners = new Set();
    this.version = 0;
    this.pending = false;

    this.screen = 'home';
    this.players = [];
    this.roundsTotal = 3;
    this.packIDs = new Set(PACKS.map((p) => p.id));
    this.editingPlayerID = null;

    this.round = 0;
    this.turn = 0;
    this.roundPrompts = [];
    this.phase = 'intro';
    this.countIn = 0;
    this.listensLeft = LISTENS_PER_TURN;
    this.lastResult = null;
    this.lastTake = null;
    this.roundResults = new Map();
    this.ranksBeforeRound = new Map();
    this.loadingPrompt = false;

    this.liveLevel = 0;
    this.levelHistory = new Array(40).fill(0);
    this.recordProgress = 0;
    this.listenProgress = 0;

    this.notice = null;
    this.stageBeat = 0;
    this.pokes = 0;
    this.pokeID = null;
    this.showHowToPlay = false;
    this.showSettings = false;
    this.isConfirmingQuit = false;
    this.muted = false;
    this.hapticsOn = true;
    this.micAccess = audio.micAccess;

    this.referenceCache = new Map();
    this.token = 0;
    this.stopRequested = false;
    this.takeStarting = false;

    this.load();
    if (!this.players.length) this.players = this.defaultCrew();
    audio.muted = this.muted;
    haptics.enabled = this.hapticsOn;
    audio.onMicAccess = (a) => { this.micAccess = a; this.emit(); };
  }

  // MARK: Change notification (batched to one render per microtask)

  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }

  emit() {
    if (this.pending) return;
    this.pending = true;
    queueMicrotask(() => {
      this.pending = false;
      this.version++;
      for (const fn of this.listeners) fn();
    });
  }

  // MARK: Derived state

  get currentPlayerIndex() { return this.players.length ? (this.turn + this.round) % this.players.length : 0; }
  get currentPlayer() { return this.players[this.currentPlayerIndex]; }
  get selectedPacks() { return PACKS.filter((p) => this.packIDs.has(p.id)); }
  get currentPrompt() { return this.roundPrompts.length ? this.roundPrompts[this.round % this.roundPrompts.length] : PACKS[0].prompts[0]; }
  get isLastTurnOfRound() { return this.turn >= this.players.length - 1; }
  get isLastRound() { return this.round >= this.roundsTotal - 1; }
  get nextPlayer() { return this.isLastTurnOfRound ? null : this.players[(this.turn + 1 + this.round) % this.players.length]; }
  get hostCharacter() { return this.players[0]?.character ?? DEFAULT_CHARACTER; }
  get hostColor() { return this.players[0]?.color ?? 0; }
  get micDenied() { return this.micAccess === 'denied'; }

  /** Players sorted by total score, with tie-aware ranks. */
  get standings() {
    const sorted = this.players.slice().sort((a, b) => total(b) - total(a));
    const ranks = competitionRanks(sorted.map(total));
    return sorted.map((player, i) => ({ rank: ranks[i], player }));
  }

  get canStartSetup() {
    return this.players.length >= MIN_PLAYERS &&
      this.players.every((p) => p.name.trim().length > 0) &&
      new Set(this.players.map((p) => p.character)).size === this.players.length;
  }

  /** Where this turn's score sits among the takes so far this round (1-based). */
  get roundRankOfLastResult() {
    if (!this.lastResult) return null;
    let n = 1;
    for (const r of this.roundResults.values()) if (r.total > this.lastResult.total) n++;
    return n;
  }

  get mascotMood() {
    switch (this.screen) {
      case 'turn':
        return { intro: 'idle', listening: 'listening', ready: 'ready', countIn: 'countIn', recording: 'recording', analyzing: 'thinking' }[this.phase];
      case 'reveal': return this.lastResult ? (this.lastResult.total >= 62 ? 'happy' : 'sad') : 'idle';
      case 'podium': return 'celebrate';
      case 'recap': return 'happy';
      default: return 'idle';
    }
  }

  get micLevelForStage() { return this.phase === 'recording' ? this.liveLevel : 0; }

  // MARK: Navigation

  go(screen) {
    this.screen = screen;
    this.emit();
  }

  goHome() {
    this.cancelTurn();
    this.isConfirmingQuit = false;
    this.go('home');
  }

  askToQuit() { haptics.tap(); this.isConfirmingQuit = true; this.emit(); }
  keepPlaying() { this.isConfirmingQuit = false; this.emit(); }
  confirmQuit() { haptics.thump(); this.goHome(); }

  openCrew() { haptics.tap(); this.go('crew'); }

  openPacks() {
    if (!this.canStartSetup) { this.flash('Every player needs a name.'); haptics.warning(); return; }
    this.players.forEach((p) => { p.name = p.name.trim(); });
    this.editingPlayerID = null;
    this.save();
    haptics.tap();
    this.go('packs');
  }

  setShowHowToPlay(v) { this.showHowToPlay = v; this.emit(); }
  setShowSettings(v) { this.showSettings = v; this.emit(); }

  setMuted(v) { this.muted = v; audio.muted = v; this.save(); this.emit(); }
  setHaptics(v) { this.hapticsOn = v; haptics.enabled = v; this.save(); this.emit(); }

  // MARK: Crew editing

  defaultCrew() {
    return [{ id: uid(), name: 'Player 1', color: randomColor(new Set()), character: DEFAULT_CHARACTER, roundScores: [] }];
  }

  addPlayer() {
    if (this.players.length >= MAX_PLAYERS) return;
    const used = new Set(this.players.map((p) => p.character));
    const free = CHARACTERS.find((c) => !used.has(c.id));
    if (!free) return;
    const player = {
      id: uid(),
      name: `Player ${this.players.length + 1}`,
      color: randomColor(new Set(this.players.map((p) => p.color))),
      character: free.id,
      roundScores: [],
    };
    this.players.push(player);
    this.editingPlayerID = player.id;
    haptics.tap();
    this.save();
    this.emit();
  }

  removePlayer(id) {
    if (this.players.length <= MIN_PLAYERS) return;
    this.players = this.players.filter((p) => p.id !== id);
    if (this.editingPlayerID === id) this.editingPlayerID = null;
    haptics.tap();
    this.save();
    this.emit();
  }

  setEditing(id) { this.editingPlayerID = id; this.emit(); }

  setName(id, name) {
    const p = this.players.find((x) => x.id === id);
    if (!p) return;
    p.name = name.slice(0, 14);
    this.save();
    this.emit();
  }

  /** The ✓ on an open player row: tidies the name, saves, and closes the editor. */
  savePlayer(id) {
    const i = this.players.findIndex((p) => p.id === id);
    if (i < 0) return;
    const name = this.players[i].name.trim();
    this.players[i].name = name || `Player ${i + 1}`;
    this.editingPlayerID = null;
    this.save();
    this.poke(id);
    haptics.success();
  }

  resetCrew() {
    this.players = this.defaultCrew();
    this.editingPlayerID = null;
    this.roundsTotal = 3;
    this.packIDs = new Set(PACKS.map((p) => p.id));
    this.save();
    haptics.success();
    this.emit();
  }

  setRounds(n) { this.roundsTotal = n; haptics.select(); this.save(); this.emit(); }

  isCharacterAvailable(characterID, playerID) {
    return !this.players.some((p) => p.id !== playerID && p.character === characterID);
  }

  setCharacter(characterID, playerID) {
    const p = this.players.find((x) => x.id === playerID);
    if (!p || p.character === characterID) return;
    if (!this.isCharacterAvailable(characterID, playerID)) {
      this.flash(`${character(characterID).name} is already taken.`);
      haptics.warning();
      return;
    }
    p.character = characterID;
    this.save();
    audio.cue('pop');
    haptics.select();
    this.emit();
  }

  cycleHostCharacter(step) {
    const host = this.players[0];
    if (!host) return;
    const i = CHARACTERS.findIndex((c) => c.id === this.hostCharacter);
    const dir = step >= 0 ? 1 : -1;
    for (let d = 1; d <= CHARACTERS.length; d++) {
      const candidate = CHARACTERS[(i + dir * d + CHARACTERS.length * 2) % CHARACTERS.length];
      if (this.isCharacterAvailable(candidate.id, host.id)) { this.setCharacter(candidate.id, host.id); return; }
    }
  }

  setHostCharacter(characterID) {
    const host = this.players[0];
    if (host) this.setCharacter(characterID, host.id);
  }

  togglePack(id) {
    if (this.packIDs.has(id)) {
      if (this.packIDs.size <= 1) { this.flash('Keep at least one pack.'); haptics.warning(); return; }
      this.packIDs.delete(id);
    } else {
      this.packIDs.add(id);
    }
    haptics.select();
    this.save();
    this.emit();
  }

  /** Plays a pack's first sound. Resolves with its length in seconds. */
  async preview(pack) {
    const prompt = pack.prompts[0];
    if (!prompt) return 0;
    audio.unlock();
    try { await audio.load(prompt.clip); } catch { this.flash("Couldn't load that sound. Check your connection."); return 0; }
    return audio.play(prompt.clip, { force: true });
  }

  /** Makes a mascot hop and spin; null pokes whoever has the spotlight. */
  poke(id = null) {
    this.pokeID = id;
    this.pokes++;
    audio.cue('pop');
    haptics.tap();
    this.emit();
  }

  // MARK: Match flow

  startMatch() {
    this.cancelTurn();
    this.players.forEach((p) => { p.roundScores = []; });
    const pool = shuffle(this.selectedPacks.flatMap((p) => p.prompts));
    this.roundPrompts = Array.from({ length: this.roundsTotal }, (_, i) => pool[i % pool.length]);
    for (const p of this.roundPrompts) audio.load(p.clip).then(() => this.emit(), () => {});
    this.round = 0;
    this.turn = 0;
    this.beginRound();
    this.save();
    haptics.success();
  }

  beginRound() {
    this.roundResults = new Map();
    this.ranksBeforeRound = new Map(this.standings.map((s) => [s.player.id, s.rank]));
    this.resetTurn();
    audio.load(this.currentPrompt.clip).then(() => this.emit(), () => {});
    this.go('handoff');
  }

  takeThePhone() {
    haptics.tap();
    audio.unlock();
    this.resetTurn();
    this.go('turn');
  }

  async listen() {
    if (this.listensLeft <= 0 || isBusy(this.phase)) return;
    const token = this.token;
    const prompt = this.currentPrompt;
    const before = this.phase;
    audio.unlock();
    this.listensLeft -= 1;
    this.phase = 'listening';
    this.listenProgress = 0;
    haptics.tap();
    this.emit();
    if (!audio.isLoaded(prompt.clip)) {
      this.loadingPrompt = true;
      this.emit();
      try {
        await audio.load(prompt.clip);
      } catch {
        if (token !== this.token) return;
        this.loadingPrompt = false;
        this.listensLeft += 1;
        this.phase = before;
        this.flash("Couldn't load this sound. Check your connection and try again.");
        haptics.warning();
        return;
      }
      this.loadingPrompt = false;
      if (token !== this.token) return;
    }
    const seconds = Math.max(0.2, audio.play(prompt.clip, { force: true }));
    const start = performance.now();
    while (token === this.token) {
      const t = (performance.now() - start) / 1000 / seconds;
      this.listenProgress = Math.min(1, t);
      if (t >= 1) break;
      this.emit();
      await sleep(30);
    }
    if (token !== this.token) return;
    this.phase = 'ready';
    this.emit();
  }

  startTake() {
    if (this.phase !== 'ready' || this.takeStarting) return;
    this.runTake(this.token);
  }

  stopTake() {
    if (this.phase !== 'recording') return;
    this.stopRequested = true;
    haptics.tap();
  }

  async runTake(token) {
    this.takeStarting = true;
    audio.unlock();
    const ok = await audio.requestMic();
    this.takeStarting = false;
    if (token !== this.token) { audio.cancelRecording(); return; }
    if (!ok) {
      this.micAccess = audio.micAccess;
      this.flash(audio.micAccess === 'unavailable'
        ? 'No microphone available here. Use the demo take.'
        : 'Microphone is off. Use the demo take, or allow it in your browser.');
      haptics.warning();
      this.emit();
      return;
    }
    for (const n of [3, 2, 1]) {
      this.phase = 'countIn';
      this.countIn = n;
      this.stageBeat++;
      audio.cue('tick');
      haptics.tick();
      this.emit();
      await sleep(700);
      if (token !== this.token) { audio.cancelRecording(); return; }
    }
    const started = await audio.startRecording();
    if (!started || token !== this.token) {
      audio.cancelRecording();
      if (token !== this.token) return;
      this.phase = 'ready';
      this.flash("Couldn't open the microphone. Try the demo take.");
      this.emit();
      return;
    }
    haptics.thump();
    this.phase = 'recording';
    this.stopRequested = false;
    this.recordProgress = 0;
    this.emit();

    const promptDuration = audio.duration(this.currentPrompt.clip) || 2;
    const maxDuration = Math.max(2.5, promptDuration + 1.6);
    const start = performance.now();
    let heardVoice = false;
    let quietSince = null;
    while (token === this.token && !this.stopRequested) {
      const now = performance.now();
      const elapsed = (now - start) / 1000;
      const level = audio.inputLevel;
      const shown = Math.min(1, Math.pow(level * 9, 0.6));
      this.liveLevel += (shown - this.liveLevel) * 0.5;
      this.levelHistory = [...this.levelHistory.slice(1), this.liveLevel];
      this.recordProgress = Math.min(1, elapsed / maxDuration);

      // Stop on our own once the player clearly finished.
      if (level > 0.03) { heardVoice = true; quietSince = null; }
      else if (heardVoice && level < 0.012) quietSince ??= now;
      if (quietSince != null && (now - quietSince) / 1000 > 0.9 && elapsed > promptDuration * 0.6) break;
      if (elapsed >= maxDuration) break;
      this.emit();
      await sleep(33);
    }
    const take = audio.stopRecording();
    this.liveLevel = 0;
    if (token !== this.token) return;
    this.phase = 'analyzing';
    this.emit();
    await sleep(40); // let the "judging" state paint before the number crunching
    await this.analyze(take, token);
  }

  async analyze(take, token) {
    const prompt = this.currentPrompt;
    const t0 = performance.now();
    let reference = this.referenceCache.get(prompt.id) ?? null;
    if (!reference) {
      const s = audio.samples(prompt.clip);
      reference = s ? analyzer.features(s, audio.sampleRate(prompt.clip)) : null;
    }
    const feats = take ? analyzer.features(take.samples, take.sampleRate) : null;
    // Give the "thinking" beat a moment to read, even when analysis is instant.
    await sleep(Math.max(0, 900 - (performance.now() - t0)));
    if (token !== this.token || this.phase !== 'analyzing') return;
    if (reference) this.referenceCache.set(prompt.id, reference);

    if (!reference || !feats) {
      this.phase = 'ready';
      this.levelHistory = new Array(40).fill(0);
      this.flash("Didn't catch that. Get closer and go again!");
      haptics.warning();
      this.emit();
      return;
    }
    this.lastTake = take;
    this.finishTurn(analyzer.score(feats, reference));
  }

  /** A clearly labeled, deterministic score so the game works without a microphone. */
  useDemoTake() {
    this.cancelTurn();
    let seed = 7;
    for (const ch of `${this.currentPrompt.id}${this.currentPlayer.name}${this.round}`) {
      seed = (seed * 31 + ch.codePointAt(0)) & 0xffff;
    }
    this.lastTake = null;
    this.finishTurn({
      total: 40 + (seed % 55),
      pitch: 35 + (seed % 60),
      rhythm: 40 + (Math.floor(seed / 7) % 55),
      length: 50 + (Math.floor(seed / 13) % 50),
      isDemo: true,
    });
  }

  finishTurn(result) {
    this.lastResult = result;
    this.roundResults.set(this.currentPlayer.id, result);
    this.currentPlayer.roundScores.push(result.total);
    audio.cue('reveal');
    this.go('reveal');
  }

  replayTake() { if (this.lastTake) audio.playTake(this.lastTake); }

  replayPrompt() { audio.play(this.currentPrompt.clip, { force: true }); }

  continueAfterReveal() {
    haptics.tap();
    audio.stopPlayback();
    if (this.isLastTurnOfRound) {
      this.go('recap');
    } else {
      this.turn++;
      this.resetTurn();
      this.go('handoff');
    }
  }

  continueAfterRecap() {
    haptics.tap();
    if (this.isLastRound) {
      haptics.success();
      this.go('podium');
    } else {
      this.round++;
      this.turn = 0;
      this.beginRound();
    }
  }

  rankChange(player, now) {
    const before = this.ranksBeforeRound.get(player.id);
    if (before == null || this.round === 0) return 0;
    return before - now;
  }

  // MARK: Helpers

  resetTurn() {
    this.cancelTurn();
    this.phase = 'intro';
    this.listensLeft = LISTENS_PER_TURN;
    this.lastResult = null;
    this.lastTake = null;
    this.listenProgress = 0;
    this.recordProgress = 0;
    this.levelHistory = new Array(40).fill(0);
  }

  cancelTurn() {
    this.token++;
    this.takeStarting = false;
    this.loadingPrompt = false;
    audio.cancelRecording();
    audio.stopPlayback();
    this.liveLevel = 0;
    if (isBusy(this.phase)) this.phase = 'ready';
  }

  flash(text) {
    this.notice = text;
    this.emit();
    clearTimeout(this.noticeTimer);
    this.noticeTimer = setTimeout(() => {
      if (this.notice === text) { this.notice = null; this.emit(); }
    }, 2800);
  }

  // MARK: Persistence

  save() {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify({
        players: this.players.map(({ id, name, color, character: c }) => ({ id, name, color, character: c })),
        rounds: this.roundsTotal,
        packs: [...this.packIDs],
        muted: this.muted,
        haptics: this.hapticsOn,
      }));
    } catch { /* Private mode or storage blocked: the game still plays. */ }
  }

  load() {
    let saved;
    try { saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null'); } catch { saved = null; }
    if (!saved || typeof saved !== 'object') return;
    const used = new Set();
    this.players = (Array.isArray(saved.players) ? saved.players : []).slice(0, MAX_PLAYERS)
      .filter((p) => p && typeof p.name === 'string')
      .map((p) => {
        let c = CHARACTERS.some((k) => k.id === p.character) ? p.character : DEFAULT_CHARACTER;
        if (used.has(c)) c = CHARACTERS.find((k) => !used.has(k.id))?.id ?? c;
        used.add(c);
        return {
          id: typeof p.id === 'string' ? p.id : uid(),
          name: p.name.slice(0, 14),
          color: Number.isInteger(p.color) && COLORS[p.color] ? p.color : 0,
          character: c,
          roundScores: [],
        };
      });
    this.roundsTotal = ROUND_OPTIONS.includes(saved.rounds) ? saved.rounds : 3;
    const valid = (Array.isArray(saved.packs) ? saved.packs : []).filter((id) => PACKS.some((p) => p.id === id));
    if (valid.length) this.packIDs = new Set(valid);
    this.muted = !!saved.muted;
    this.hapticsOn = saved.haptics !== false;
  }
}

export const game = new Game();
