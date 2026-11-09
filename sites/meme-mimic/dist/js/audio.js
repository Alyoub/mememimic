// Playback of the real meme clips, synthesized interface cues and microphone capture.
// The web twin of Audio/AudioEngine.swift.
import { clipURL } from './library.js';

const Ctx = window.AudioContext || window.webkitAudioContext;

/** Interface cues, synthesized like the iOS app's (SoundLibrary.Cue). */
const CUES = {
  tick: [{ start: 0, duration: 0.07, from: 880, to: 880, timbre: 'whistle', gain: 0.6 }],
  go: [{ start: 0, duration: 0.18, from: 1320, to: 1320, timbre: 'whistle', gain: 0.7 }],
  reveal: [
    { start: 0, duration: 0.10, from: 523, to: 523, timbre: 'whistle', gain: 0.6 },
    { start: 0.09, duration: 0.10, from: 659, to: 659, timbre: 'whistle', gain: 0.6 },
    { start: 0.18, duration: 0.22, from: 784, to: 790, timbre: 'whistle', gain: 0.6 },
  ],
  pop: [{ start: 0, duration: 0.09, from: 300, to: 900, timbre: 'hum', gain: 0.7 }],
};

class AudioEngine {
  constructor() {
    this.ctx = null;
    this.muted = false;
    this.buffers = new Map();   // clip id → Promise<AudioBuffer>
    this.decoded = new Map();   // clip id → AudioBuffer
    this.monoCache = new Map(); // clip id → Float32Array
    this.envelopes = new Map();
    this.promptSource = null;
    this.takeSource = null;
    this.stream = null;
    this.micNode = null;
    this.micSource = null;
    this.sink = null;
    this.level = 0;
    this.micAccess = 'unknown'; // unknown | granted | denied | unavailable
    this.workletReady = null;
    this.onMicAccess = null;
    this.watchPermission();
    this.setSession('playback');
  }

  /** Created up front (suspended) so clips can decode before the first tap. */
  context() {
    if (!this.ctx && Ctx) {
      try { this.ctx = new Ctx({ latencyHint: 'interactive' }); } catch { this.ctx = new Ctx(); }
      this.out = this.ctx.createGain();
      this.out.connect(this.ctx.destination);
      this.hum = this.ctx.createPeriodicWave(new Float32Array([0, 0, 0, 0]), new Float32Array([0, 1, 0.45, 0.2]));
    }
    return this.ctx;
  }

  /** Called from the first user gesture: browsers only start audio after one. */
  unlock() {
    const ctx = this.context();
    if (!ctx) return;
    if (ctx.state !== 'running') ctx.resume().catch(() => {});
    if (!this.unlocked) {
      this.unlocked = true;
      // iOS Safari: one silent buffer inside the gesture fully wakes the output.
      const b = ctx.createBuffer(1, 1, 22050);
      const s = ctx.createBufferSource();
      s.buffer = b; s.connect(ctx.destination); s.start(0);
    }
  }

  /** Safari's Audio Session API: plays through the speaker even with the ringer off. */
  setSession(type) {
    try { if (navigator.audioSession) navigator.audioSession.type = type; } catch {}
  }

  // MARK: Clips

  load(clip) {
    if (!this.buffers.has(clip)) {
      const ctx = this.context();
      const p = fetch(clipURL(clip))
        .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.arrayBuffer(); })
        .then((data) => new Promise((resolve, reject) => {
          // Old Safari only supports the callback form.
          const done = ctx.decodeAudioData(data, resolve, reject);
          if (done && done.then) done.then(resolve, reject);
        }))
        .then((buffer) => { this.decoded.set(clip, buffer); return buffer; });
      p.catch(() => this.buffers.delete(clip));
      this.buffers.set(clip, p);
    }
    return this.buffers.get(clip);
  }

  isLoaded(clip) { return this.decoded.has(clip); }

  duration(clip) { return this.decoded.get(clip)?.duration ?? 0; }

  /** The clip as mono samples at the context's rate, for scoring. */
  samples(clip) {
    if (this.monoCache.has(clip)) return this.monoCache.get(clip);
    const b = this.decoded.get(clip);
    if (!b) return null;
    let mono;
    if (b.numberOfChannels === 1) mono = b.getChannelData(0).slice();
    else {
      mono = new Float32Array(b.length);
      for (let c = 0; c < b.numberOfChannels; c++) {
        const d = b.getChannelData(c);
        for (let i = 0; i < d.length; i++) mono[i] += d[i] / b.numberOfChannels;
      }
    }
    this.monoCache.set(clip, mono);
    return mono;
  }

  sampleRate(clip) { return this.decoded.get(clip)?.sampleRate ?? this.ctx?.sampleRate ?? 44100; }

  /** Loudness shape of a clip as `bars` values in 0...1, for drawing. */
  envelope(clip, bars) {
    const key = `${clip}#${bars}`;
    if (this.envelopes.has(key)) return this.envelopes.get(key);
    const s = this.samples(clip);
    if (!s) return null;
    const chunk = Math.max(1, Math.floor(s.length / bars));
    const peaks = [];
    for (let i = 0; i < bars; i++) {
      let m = 0;
      const end = Math.min((i + 1) * chunk, s.length);
      for (let j = Math.min(i * chunk, s.length - 1); j < end; j++) { const v = Math.abs(s[j]); if (v > m) m = v; }
      peaks.push(m);
    }
    const top = Math.max(...peaks, 0.0001);
    const shape = peaks.map((p) => 0.08 + (0.92 * p) / top);
    this.envelopes.set(key, shape);
    return shape;
  }

  // MARK: Playback

  /** Plays a decoded clip. Prompts always play (force); the mute switch is for effects. */
  play(clip, { force = false } = {}) {
    const buffer = this.decoded.get(clip);
    if (!buffer) return 0;
    if (this.muted && !force) return buffer.duration;
    this.unlock();
    this.stopPrompt();
    const s = this.ctx.createBufferSource();
    s.buffer = buffer;
    s.connect(this.out);
    s.start();
    this.promptSource = s;
    return buffer.duration;
  }

  cue(name) {
    if (this.muted) return;
    const ctx = this.context();
    if (!ctx || ctx.state !== 'running') return;
    const t0 = ctx.currentTime + 0.005;
    for (const seg of CUES[name] ?? []) {
      const osc = ctx.createOscillator();
      if (seg.timbre === 'hum') osc.setPeriodicWave(this.hum); else osc.type = 'sine';
      const start = t0 + seg.start, end = start + seg.duration;
      osc.frequency.setValueAtTime(seg.from, start);
      if (seg.to !== seg.from) osc.frequency.exponentialRampToValueAtTime(seg.to, end);
      const g = ctx.createGain();
      const peak = seg.gain * 0.22;
      g.gain.setValueAtTime(0, start);
      g.gain.linearRampToValueAtTime(peak, start + 0.015);
      g.gain.setValueAtTime(peak, Math.max(start + 0.015, end - 0.04));
      g.gain.linearRampToValueAtTime(0, end);
      osc.connect(g).connect(this.out);
      osc.start(start);
      osc.stop(end + 0.02);
    }
  }

  playTake(take) {
    if (!take?.samples?.length) return;
    this.unlock();
    this.stopPlayback();
    const b = this.ctx.createBuffer(1, take.samples.length, take.sampleRate);
    b.copyToChannel(take.samples, 0);
    const s = this.ctx.createBufferSource();
    s.buffer = b;
    s.connect(this.out);
    s.start();
    this.takeSource = s;
  }

  stopPrompt() {
    try { this.promptSource?.stop(); } catch {}
    this.promptSource = null;
  }

  stopPlayback() {
    this.stopPrompt();
    try { this.takeSource?.stop(); } catch {}
    this.takeSource = null;
  }

  // MARK: Microphone

  async watchPermission() {
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) { this.micAccess = 'unavailable'; return; }
    try {
      const status = await navigator.permissions.query({ name: 'microphone' });
      const apply = () => {
        this.micAccess = status.state === 'granted' ? 'granted' : status.state === 'denied' ? 'denied' : 'unknown';
        this.onMicAccess?.(this.micAccess);
      };
      apply();
      status.onchange = apply;
    } catch { /* Not every browser can query the microphone permission. */ }
  }

  /** Asks for the microphone and holds the stream until the take ends. */
  async requestMic() {
    if (this.stream) return true;
    if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
      this.micAccess = 'unavailable';
      return false;
    }
    this.unlock();
    this.setSession('play-and-record');
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: true, channelCount: 1 },
      });
      this.micAccess = 'granted';
      this.onMicAccess?.(this.micAccess);
      return true;
    } catch (e) {
      this.setSession('playback');
      if (e && (e.name === 'NotAllowedError' || e.name === 'SecurityError')) this.micAccess = 'denied';
      else if (e && (e.name === 'NotFoundError' || e.name === 'OverconstrainedError')) this.micAccess = 'unavailable';
      this.onMicAccess?.(this.micAccess);
      return false;
    }
  }

  async startRecording() {
    this.stopPlayback();
    if (!(await this.requestMic())) return false;
    const ctx = this.context();
    try {
      if (ctx.state !== 'running') await ctx.resume();
      this.sink = { chunks: [], rate: ctx.sampleRate };
      this.level = 0;
      const source = ctx.createMediaStreamSource(this.stream);
      const onChunk = (data) => {
        if (!this.sink) return;
        this.sink.chunks.push(data);
        let sum = 0;
        for (let i = 0; i < data.length; i++) sum += data[i] * data[i];
        this.level = Math.sqrt(sum / data.length);
      };
      let node;
      if (ctx.audioWorklet && window.AudioWorkletNode) {
        this.workletReady ??= ctx.audioWorklet.addModule(new URL('./recorder-worklet.js', import.meta.url));
        await this.workletReady;
        node = new AudioWorkletNode(ctx, 'meme-mimic-recorder', { numberOfInputs: 1, numberOfOutputs: 1, channelCount: 1 });
        node.port.onmessage = (e) => onChunk(e.data);
      } else {
        node = ctx.createScriptProcessor(1024, 1, 1);
        node.onaudioprocess = (e) => onChunk(e.inputBuffer.getChannelData(0).slice());
      }
      // Silent path to the output keeps the node pulled by the graph.
      const mute = ctx.createGain();
      mute.gain.value = 0;
      source.connect(node);
      node.connect(mute).connect(ctx.destination);
      this.micSource = source;
      this.micNode = node;
      this.micMute = mute;
      return true;
    } catch {
      this.releaseMic();
      return false;
    }
  }

  get inputLevel() { return this.sink ? this.level : 0; }

  stopRecording() {
    const sink = this.sink;
    this.releaseMic();
    if (!sink) return null;
    const total = sink.chunks.reduce((n, c) => n + c.length, 0);
    const samples = new Float32Array(total);
    let o = 0;
    for (const c of sink.chunks) { samples.set(c, o); o += c.length; }
    return { samples, sampleRate: sink.rate };
  }

  cancelRecording() { this.releaseMic(); }

  releaseMic() {
    this.sink = null;
    this.level = 0;
    try { this.micSource?.disconnect(); } catch {}
    try { this.micNode?.disconnect(); } catch {}
    try { this.micMute?.disconnect(); } catch {}
    if (this.micNode?.port) this.micNode.port.onmessage = null;
    this.micSource = this.micNode = this.micMute = null;
    if (this.stream) {
      for (const t of this.stream.getTracks()) t.stop();
      this.stream = null;
      // Back to playback-only so the mic indicator turns off and output returns to full volume.
      this.setSession('playback');
    }
  }
}

export const audio = new AudioEngine();
