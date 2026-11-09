import Foundation

/// On-device comparison of an imitation against a prompt.
///
/// Both sounds are reduced to an energy envelope and a relative pitch contour (semitones
/// around their own median, so a deep voice copying a high whistle is judged on shape,
/// not register). The contours are aligned with dynamic time warping, which forgives a
/// player who starts late or drags a note.
enum VoiceAnalyzer {
    struct Features {
        /// Loudness per frame, normalised to 0...1, trimmed to the active region.
        let energy: [Double]
        /// Semitones relative to the median voiced pitch; nil where unvoiced.
        let pitch: [Double?]
        let activeDuration: Double

        var voicedRatio: Double {
            pitch.isEmpty ? 0 : Double(pitch.compactMap { $0 }.count) / Double(pitch.count)
        }
    }

    static let hop = 0.01

    static func features(_ samples: [Float], sampleRate: Double) -> Features? {
        guard sampleRate > 0, samples.count > Int(sampleRate * 0.1) else { return nil }

        // Work at ~11 kHz: plenty for voice pitch, and fast enough for a debug build.
        let factor = max(1, Int(sampleRate / 11_025))
        let rate = sampleRate / Double(factor)
        let x: [Double] = stride(from: 0, to: samples.count - factor + 1, by: factor).map { i in
            var s = 0.0
            for k in 0..<factor { s += Double(samples[i + k]) }
            return s / Double(factor)
        }

        let hopN = Int(rate * hop)
        let frameN = Int(rate * 0.04)
        guard x.count > frameN else { return nil }
        let starts = Array(stride(from: 0, to: x.count - frameN, by: hopN))

        let rms = starts.map { s -> Double in
            var e = 0.0
            for i in s..<(s + frameN) { e += x[i] * x[i] }
            return sqrt(e / Double(frameN))
        }
        guard let peak = rms.max(), peak > 0.006 else { return nil }

        let gate = max(peak * 0.12, 0.004)
        guard let first = rms.firstIndex(where: { $0 > gate }),
              let last = rms.lastIndex(where: { $0 > gate }),
              last - first >= 8 else { return nil }

        let energy = rms[first...last].map { $0 / peak }
        let rawPitch: [Double?] = starts[first...last].enumerated().map { offset, s in
            rms[first + offset] > gate ? pitch(x, start: s, length: frameN, rate: rate) : nil
        }
        let semis = rawPitch.map { $0.map { 12 * log2($0) } }
        let voiced = semis.compactMap { $0 }.sorted()
        let median = voiced.isEmpty ? 0 : voiced[voiced.count / 2]
        let relative = semis.map { $0.map { max(-14, min(14, $0 - median)) } }

        return Features(energy: energy, pitch: relative, activeDuration: Double(last - first) * hop)
    }

    /// Normalised autocorrelation pitch estimate between 75 and 1100 Hz.
    private static func pitch(_ x: [Double], start: Int, length: Int, rate: Double) -> Double? {
        let minLag = Int(rate / 1100), maxLag = min(Int(rate / 75), length - 1)
        guard maxLag > minLag else { return nil }
        var bestLag = 0, best = 0.0
        var corr = [Double](repeating: 0, count: maxLag + 1)
        for lag in minLag...maxLag {
            var num = 0.0, a = 0.0, b = 0.0
            for i in start..<(start + length - lag) {
                num += x[i] * x[i + lag]; a += x[i] * x[i]; b += x[i + lag] * x[i + lag]
            }
            let c = num / max(sqrt(a * b), 1e-9)
            corr[lag] = c
        }
        // Take the first strong peak rather than the global max to avoid octave errors.
        let threshold = (corr.max() ?? 0) * 0.88
        for lag in (minLag + 1)..<maxLag where corr[lag] >= threshold && corr[lag] >= corr[lag - 1] && corr[lag] >= corr[lag + 1] {
            bestLag = lag; best = corr[lag]; break
        }
        guard best > 0.55, bestLag > 0 else { return nil }
        return rate / Double(bestLag)
    }

    static func score(take: Features, reference: Features) -> TurnResult {
        let n = 48
        let a = resample(take.energy, n), b = resample(reference.energy, n)
        let rhythmCost = dtw(a, b, bandFraction: 0.1) { abs($0 - $1) }
        let rhythm = clamp(1 - rhythmCost * 3.2)

        let pitch: Double
        if reference.voicedRatio < 0.12 {
            // An unpitched prompt (a gasp, a breath) is best copied unpitched; a sung
            // attempt still gets partial credit, and rhythm decides the rest.
            pitch = take.voicedRatio < 0.12 ? 1.0 : 0.6
        } else if take.voicedRatio < 0.12 {
            // Unpitched noise can't copy a melody.
            pitch = 0.05
        } else {
            let pa = resample(fillGaps(take.pitch), n), pb = resample(fillGaps(reference.pitch), n)
            let cost = dtw(pa, pb, bandFraction: 0.2) { min(abs($0 - $1), 12) }
            pitch = clamp(1 - cost / 5)
        }

        let ratio = min(take.activeDuration, reference.activeDuration) / max(take.activeDuration, reference.activeDuration, 0.01)
        let length = clamp((ratio - 0.25) / 0.6)

        // Weighted blend, then stretched so a wrong sound lands low and a close copy high.
        let raw = 0.55 * pitch + 0.30 * rhythm + 0.15 * length
        let total = Int((100 * pow(clamp((raw - 0.38) / 0.58), 0.85)).rounded())
        return TurnResult(total: max(3, min(99, total)),
                          pitch: Int((pitch * 100).rounded()),
                          rhythm: Int((rhythm * 100).rounded()),
                          length: Int((length * 100).rounded()),
                          isDemo: false)
    }

    // MARK: Helpers

    private static func clamp(_ v: Double) -> Double { max(0, min(1, v)) }

    private static func resample(_ v: [Double], _ n: Int) -> [Double] {
        guard v.count > 1 else { return Array(repeating: v.first ?? 0, count: n) }
        return (0..<n).map { i in
            let p = Double(i) / Double(n - 1) * Double(v.count - 1)
            let lo = Int(p), hi = min(lo + 1, v.count - 1), f = p - Double(lo)
            return v[lo] * (1 - f) + v[hi] * f
        }
    }

    /// Linear interpolation across unvoiced frames; edges hold the nearest voiced value.
    private static func fillGaps(_ v: [Double?]) -> [Double] {
        let known = v.enumerated().compactMap { i, x in x.map { (i, $0) } }
        guard let firstKnown = known.first, let lastKnown = known.last else { return Array(repeating: 0, count: v.count) }
        var out = [Double](repeating: 0, count: v.count)
        var k = 0
        for i in v.indices {
            if i <= firstKnown.0 { out[i] = firstKnown.1; continue }
            if i >= lastKnown.0 { out[i] = lastKnown.1; continue }
            while known[k + 1].0 < i { k += 1 }
            let (i0, y0) = known[k], (i1, y1) = known[k + 1]
            out[i] = i1 == i0 ? y0 : y0 + (y1 - y0) * Double(i - i0) / Double(i1 - i0)
        }
        return out
    }

    /// Mean per-step cost along the best warping path, within a band around the diagonal.
    private static func dtw(_ a: [Double], _ b: [Double], bandFraction: Double, cost: (Double, Double) -> Double) -> Double {
        let n = a.count, m = b.count, band = max(1, Int(Double(max(n, m)) * bandFraction))
        var d = [[Double]](repeating: [Double](repeating: .infinity, count: m + 1), count: n + 1)
        var len = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        d[0][0] = 0
        for i in 1...n {
            for j in max(1, i - band)...min(m, i + band) {
                let c = cost(a[i - 1], b[j - 1])
                let options = [(d[i - 1][j - 1], len[i - 1][j - 1]), (d[i - 1][j], len[i - 1][j]), (d[i][j - 1], len[i][j - 1])]
                let best = options.min { $0.0 < $1.0 }!
                d[i][j] = best.0 + c
                len[i][j] = best.1 + 1
            }
        }
        return d[n][m] / Double(max(len[n][m], 1))
    }
}
