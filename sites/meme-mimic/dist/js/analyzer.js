// On-device comparison of an imitation against a prompt. A direct port of the iOS
// VoiceAnalyzer: both sounds become an energy envelope and a relative pitch contour
// (semitones around their own median, so a deep voice copying a high squeak is judged on
// shape, not register). Contours are aligned with banded dynamic time warping, which
// forgives a player who starts late or drags a note.

const HOP = 0.01;

/**
 * @param {Float32Array} samples mono audio
 * @param {number} sampleRate
 * @returns {{energy:number[], pitch:(number|null)[], activeDuration:number, voicedRatio:number}|null}
 */
export function features(samples, sampleRate) {
  if (!(sampleRate > 0) || samples.length <= sampleRate * 0.1) return null;

  // Work at ~11 kHz: plenty for voice pitch, and fast.
  const factor = Math.max(1, Math.floor(sampleRate / 11025));
  const rate = sampleRate / factor;
  const n = Math.floor((samples.length - factor) / factor) + 1;
  const x = new Float64Array(n);
  for (let j = 0, i = 0; j < n; j++, i += factor) {
    let s = 0;
    for (let k = 0; k < factor; k++) s += samples[i + k];
    x[j] = s / factor;
  }

  const hopN = Math.floor(rate * HOP);
  const frameN = Math.floor(rate * 0.04);
  if (x.length <= frameN) return null;
  const starts = [];
  for (let s = 0; s < x.length - frameN; s += hopN) starts.push(s);

  const rms = starts.map((s) => {
    let e = 0;
    for (let i = s; i < s + frameN; i++) e += x[i] * x[i];
    return Math.sqrt(e / frameN);
  });
  const peak = Math.max(0, ...rms);
  if (!(peak > 0.006)) return null;

  const gate = Math.max(peak * 0.12, 0.004);
  const first = rms.findIndex((v) => v > gate);
  let last = -1;
  for (let i = rms.length - 1; i >= 0; i--) if (rms[i] > gate) { last = i; break; }
  if (first < 0 || last < 0 || last - first < 8) return null;

  const energy = rms.slice(first, last + 1).map((v) => v / peak);
  const semis = [];
  for (let f = first; f <= last; f++) {
    const hz = rms[f] > gate ? pitch(x, starts[f], frameN, rate) : null;
    semis.push(hz == null ? null : 12 * Math.log2(hz));
  }
  const voiced = semis.filter((v) => v != null).sort((a, b) => a - b);
  const median = voiced.length ? voiced[Math.floor(voiced.length / 2)] : 0;
  const rel = semis.map((v) => (v == null ? null : Math.max(-14, Math.min(14, v - median))));
  const voicedRatio = rel.length ? voiced.length / rel.length : 0;

  return { energy, pitch: rel, activeDuration: (last - first) * HOP, voicedRatio };
}

/** Normalised autocorrelation pitch estimate between 75 and 1100 Hz. */
function pitch(x, start, length, rate) {
  const minLag = Math.floor(rate / 1100);
  const maxLag = Math.min(Math.floor(rate / 75), length - 1);
  if (maxLag <= minLag) return null;
  const corr = new Float64Array(maxLag + 1);
  let top = 0;
  for (let lag = minLag; lag <= maxLag; lag++) {
    let num = 0, a = 0, b = 0;
    const end = start + length - lag;
    for (let i = start; i < end; i++) {
      const p = x[i], q = x[i + lag];
      num += p * q; a += p * p; b += q * q;
    }
    const c = num / Math.max(Math.sqrt(a * b), 1e-9);
    corr[lag] = c;
    if (c > top) top = c;
  }
  // Take the first strong peak rather than the global max to avoid octave errors.
  const threshold = top * 0.88;
  let bestLag = 0, best = 0;
  for (let lag = minLag + 1; lag < maxLag; lag++) {
    if (corr[lag] >= threshold && corr[lag] >= corr[lag - 1] && corr[lag] >= corr[lag + 1]) {
      bestLag = lag; best = corr[lag]; break;
    }
  }
  if (!(best > 0.55) || bestLag <= 0) return null;
  return rate / bestLag;
}

export function score(take, reference) {
  const n = 48;
  const a = resample(take.energy, n), b = resample(reference.energy, n);
  const rhythmCost = dtw(a, b, 0.1, (p, q) => Math.abs(p - q));
  const rhythm = clamp(1 - rhythmCost * 3.2);

  let pitchScore;
  if (reference.voicedRatio < 0.12) {
    // An unpitched prompt (a gasp, a breath) is best copied unpitched.
    pitchScore = take.voicedRatio < 0.12 ? 1.0 : 0.6;
  } else if (take.voicedRatio < 0.12) {
    // Unpitched noise can't copy a melody.
    pitchScore = 0.05;
  } else {
    const pa = resample(fillGaps(take.pitch), n), pb = resample(fillGaps(reference.pitch), n);
    const cost = dtw(pa, pb, 0.2, (p, q) => Math.min(Math.abs(p - q), 12));
    pitchScore = clamp(1 - cost / 5);
  }

  const ratio = Math.min(take.activeDuration, reference.activeDuration) /
    Math.max(take.activeDuration, reference.activeDuration, 0.01);
  const length = clamp((ratio - 0.25) / 0.6);

  // Weighted blend, then stretched so a wrong sound lands low and a close copy high.
  const raw = 0.55 * pitchScore + 0.30 * rhythm + 0.15 * length;
  const total = Math.round(100 * Math.pow(clamp((raw - 0.38) / 0.58), 0.85));
  return {
    total: Math.max(3, Math.min(99, total)),
    pitch: Math.round(pitchScore * 100),
    rhythm: Math.round(rhythm * 100),
    length: Math.round(length * 100),
    isDemo: false,
  };
}

const clamp = (v) => Math.max(0, Math.min(1, v));

function resample(v, n) {
  if (v.length <= 1) return new Array(n).fill(v[0] ?? 0);
  const out = new Array(n);
  for (let i = 0; i < n; i++) {
    const p = (i / (n - 1)) * (v.length - 1);
    const lo = Math.floor(p), hi = Math.min(lo + 1, v.length - 1), f = p - lo;
    out[i] = v[lo] * (1 - f) + v[hi] * f;
  }
  return out;
}

/** Linear interpolation across unvoiced frames; edges hold the nearest voiced value. */
function fillGaps(v) {
  const known = [];
  v.forEach((x, i) => { if (x != null) known.push([i, x]); });
  if (!known.length) return new Array(v.length).fill(0);
  const [fi, fv] = known[0], [li, lv] = known[known.length - 1];
  const out = new Array(v.length).fill(0);
  let k = 0;
  for (let i = 0; i < v.length; i++) {
    if (i <= fi) { out[i] = fv; continue; }
    if (i >= li) { out[i] = lv; continue; }
    while (known[k + 1][0] < i) k++;
    const [i0, y0] = known[k], [i1, y1] = known[k + 1];
    out[i] = i1 === i0 ? y0 : y0 + ((y1 - y0) * (i - i0)) / (i1 - i0);
  }
  return out;
}

/** Mean per-step cost along the best warping path, within a band around the diagonal. */
function dtw(a, b, bandFraction, cost) {
  const n = a.length, m = b.length;
  const band = Math.max(1, Math.floor(Math.max(n, m) * bandFraction));
  const d = Array.from({ length: n + 1 }, () => new Float64Array(m + 1).fill(Infinity));
  const len = Array.from({ length: n + 1 }, () => new Int32Array(m + 1));
  d[0][0] = 0;
  for (let i = 1; i <= n; i++) {
    for (let j = Math.max(1, i - band); j <= Math.min(m, i + band); j++) {
      const c = cost(a[i - 1], b[j - 1]);
      // Same tie order as the Swift min(by:): diagonal, then up, then left.
      let bestD = d[i - 1][j - 1], bestL = len[i - 1][j - 1];
      if (d[i - 1][j] < bestD) { bestD = d[i - 1][j]; bestL = len[i - 1][j]; }
      if (d[i][j - 1] < bestD) { bestD = d[i][j - 1]; bestL = len[i][j - 1]; }
      d[i][j] = bestD + c;
      len[i][j] = bestL + 1;
    }
  }
  return d[n][m] / Math.max(len[n][m], 1);
}
