import AVFoundation
import Foundation

/// One voice inside a prompt. Times are in seconds, pitch in Hz.
struct ToneSegment {
    enum Timbre {
        /// Pure sine.
        case whistle
        /// Sine with a couple of soft harmonics.
        case hum
        /// Bright, reedy harmonics.
        case buzz
        /// Trombone-like: a full harmonic series through an opening "wah" filter.
        case brass
        /// Stadium air horn: three slightly detuned reeds, driven hard.
        case horn
        /// A sung or spoken vowel: a voice-like source shaped by vowel formants.
        case voice
        /// Filtered noise; `from`/`to` sweep the filter's centre (breaths, risers, clicks).
        case noise
        /// Deep sub-bass hit whose pitch falls from `from` to `to`.
        case boom
    }

    enum Vowel {
        case u, o, uh, a, e, i

        /// First three formant frequencies (Hz), from typical adult speech.
        var formants: (Double, Double, Double) {
            switch self {
            case .u: (320, 800, 2300)
            case .o: (450, 850, 2600)
            case .uh: (640, 1190, 2390)
            case .a: (750, 1200, 2500)
            case .e: (500, 1800, 2500)
            case .i: (300, 2250, 3000)
            }
        }
    }

    var start: Double
    var duration: Double
    var from: Double
    var to: Double
    var timbre: Timbre = .hum
    var vowel: Vowel = .uh
    var toVowel: Vowel? = nil
    var vibratoHz: Double = 0
    var vibratoSemitones: Double = 0
    var tremoloHz: Double = 0
    var attack: Double = 0.015
    var release: Double = 0.04
    var gain: Double = 1
}

struct Prompt: Identifiable {
    let id: String
    let name: String
    let hint: String
    /// Synthesized voices. Unused when the prompt is a recorded `clip`.
    var segments: [ToneSegment] = []
    /// Name of a recorded clip in the app bundle (Sounds/<clip>.m4a).
    var clip: String? = nil
    /// Feedback echo amount, 0...1, for dramatic synthesized sounds.
    var echo: Double = 0

    var duration: Double {
        if let clip { return Double(SoundLibrary.clipSamples(clip).count) / SoundLibrary.sampleRate }
        return segments.map { $0.start + $0.duration }.max() ?? 0
    }
}

struct SoundPack: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let symbol: String
    let tint: BloomColor
    let prompts: [Prompt]
}

/// The game's prompts and interface sounds.
///
/// Prompts are short meme clips supplied by the project owner (mp3/), trimmed and
/// level-matched by art/prepare_clips.swift into Sounds/. Many are third-party audio:
/// fine for private play and testing, but they need licensing or replacing before
/// any public release. Interface cues are synthesized.
enum SoundLibrary {
    static let sampleRate = 44_100.0

    private static func meme(_ clip: String, _ name: String, _ hint: String) -> Prompt {
        Prompt(id: clip, name: name, hint: hint, clip: clip)
    }

    private static func original(_ id: String, _ name: String, _ hint: String,
                                 echo: Double = 0, _ segments: [ToneSegment]) -> Prompt {
        Prompt(id: "original-\(id)", name: name, hint: hint, segments: segments, echo: echo)
    }

    static let packs: [SoundPack] = [
        SoundPack(id: "reactions", name: "Meme Reactions", blurb: "Short, loud, iconic.", symbol: "face.smiling.inverse", tint: .sunny, prompts: [
            meme("faaah", "Faaah!", "One long, dramatic \"faaah\"."),
            meme("you-what-spongebob", "You What?", "Squeaky disbelief."),
            meme("what_JOcN7Y8", "What?!", "A sharp, shocked \"what\"."),
            meme("omg-bruh-oh-hell-nah", "OMG Bruh, Oh Hell Nah", "Escalating disbelief. Match every word."),
            meme("emotional-damage-meme", "Emotional Damage", "Deliver it like a final blow."),
            meme("meme-okay-lets-go", "Okay, Let's Go!", "Pure hype. Get louder at the end."),
            meme("cringe-sus-anime-girl", "Sus Anime Girl", "A tiny, very suspicious squeal."),
        ]),
        SoundPack(id: "voices", name: "Silly Voices", blurb: "Cats, frogs, aliens and worse.", symbol: "theatermasks.fill", tint: .grape, prompts: [
            meme("oiia-oiia-sound", "OIIA OIIA", "The spinning cat. The pitch goes everywhere."),
            meme("mu-hehehe-cat-meme", "Mu-hehehe Cat", "A sneaky, evil little laugh."),
            meme("frog-laughing-meme", "Laughing Frog", "Croaky laughter. Keep the rhythm."),
            meme("zab-zab-zab-bla-bla-blu-blu-alien-tiktok-meme", "Zab Zab Alien", "Zab zab zab, bla bla, blu blu."),
            meme("snore-mimimimimimi", "Mimimi Snore", "Snore in, \"mimimi\" out."),
            meme("oi-oi-oe-oi-a-eye-eye", "Oi Oi Oe Oi", "Oi oi oe oi, a-eye-eye!"),
            meme("anime-wow-sound-effect-mp3cut", "Anime Wow", "A dreamy, wide-eyed \"wow\"."),
        ]),
        SoundPack(id: "worldwide", name: "Worldwide & Wild", blurb: "Memes from everywhere.", symbol: "globe.americas.fill", tint: .sky, prompts: [
            meme("bom-dia-a-todos-e-todes-meme", "Bom Dia a Todos", "Portuguese for \"good morning, everyone\". Say it with gusto."),
            meme("lula-bom-dia-motivacional-meme-kkkkkk", "Bom Dia Motivacional", "A motivational Brazilian good morning."),
            meme("du-bist-gut-genug", "Du Bist Gut Genug", "German for \"you are good enough\"."),
            meme("man-screaming", "Man Screaming", "Just scream. Match the length."),
            meme("michael-dont-leave-me-here", "Michael, Don't Leave Me Here", "Desperate and dramatic."),
            meme("ny-video-online-audio-converter", "Mystery Meme #1", "No spoilers. Just copy what you hear."),
            meme("yt1s_wU4BGgD", "Mystery Meme #2", "No spoilers. Just copy what you hear."),
        ]),
        SoundPack(id: "brainrot", name: "Brainrot", blurb: "Peak internet nonsense.", symbol: "brain.head.profile", tint: .mint, prompts: [
            meme("italian-brainrot", "Italian Brainrot", "Fast, dramatic and very Italian."),
            meme("Dragon-Cannelloni", "Dragon Cannelloni", "Announce it like a legend."),
            meme("Chinese-rapping", "Chinese Rapping", "Keep up with the flow."),
            meme("cat-iphone-ringtone", "Cat Ringtone", "Meow the ringtone, note for note."),
            meme("This-thing-is-called-Ratafak", "This Thing Is Called Ratafak", "Present it with total confidence."),
            meme("Plankton-Aughhhhh", "Plankton AUGHHH", "One long, tiny, furious scream."),
            meme("Its-Time-For-Scoo", "It's Time For...", "Big announcement energy."),
        ]),
        SoundPack(id: "lines", name: "Movie & TV Lines", blurb: "Quotes everyone knows.", symbol: "film.fill", tint: .tangerine, prompts: [
            meme("No-its-Thursday-bro", "No, It's Thursday Bro", "A dead-serious correction."),
            meme("Nobodys-gonna-know", "Nobody's Gonna Know", "Like you're getting away with it."),
            meme("Somebody-Get-These-Beggars-Outta-Here", "Get These Beggars Outta Here", "Maximum disgust."),
            meme("Ted-Hey-can-i-have-this", "Hey, Can I Have This?", "Innocent. Polite. Suspicious."),
            meme("naoya_zenin", "Naoya Zenin", "Anime villain energy."),
            meme("Dictator-Mbappe", "Dictator Mbappé", "Copy every word, and the attitude."),
            meme("Surprise-mother-fer", "Surprise!", "The famous jump-scare line. Strong language."),
            meme("Aller-ftg-", "Aller, FTG!", "French, rude and very fast."),
        ]),
    ]

    /// Fully original, runtime-synthesized alternatives used when remote `realSound`
    /// is false. They contain no samples, melodies, performances, or third-party audio.
    static let originalPacks: [SoundPack] = [
        SoundPack(id: "reactions", name: "Synth Reactions", blurb: "Original expressive sound bites.", symbol: "waveform", tint: .sunny, prompts: [
            original("rising-wow", "Rising Wow", "Start low, then sweep way up.", echo: 0.18, [
                .init(start: 0, duration: 0.75, from: 190, to: 510, timbre: .voice, vowel: .o, toVowel: .a, vibratoHz: 5, vibratoSemitones: 0.3),
            ]),
            original("triple-pop", "Triple Pop", "Three quick notes, last one highest.", [
                .init(start: 0, duration: 0.13, from: 330, to: 390, timbre: .buzz),
                .init(start: 0.20, duration: 0.13, from: 390, to: 450, timbre: .buzz),
                .init(start: 0.40, duration: 0.24, from: 520, to: 620, timbre: .buzz),
            ]),
            original("tiny-gasp", "Tiny Gasp", "A quick breath, then a bright squeak.", [
                .init(start: 0, duration: 0.16, from: 900, to: 1800, timbre: .noise, gain: 0.45),
                .init(start: 0.13, duration: 0.34, from: 720, to: 980, timbre: .whistle, vibratoHz: 7, vibratoSemitones: 0.4),
            ]),
        ]),
        SoundPack(id: "voices", name: "Synth Creatures", blurb: "Original oddball voices.", symbol: "theatermasks.fill", tint: .grape, prompts: [
            original("robot-giggle", "Robot Giggle", "Four bouncy electronic laughs.", echo: 0.12, [
                .init(start: 0, duration: 0.16, from: 260, to: 410, timbre: .voice, vowel: .e),
                .init(start: 0.20, duration: 0.16, from: 300, to: 470, timbre: .voice, vowel: .e),
                .init(start: 0.40, duration: 0.16, from: 350, to: 530, timbre: .voice, vowel: .e),
                .init(start: 0.60, duration: 0.28, from: 420, to: 250, timbre: .voice, vowel: .a),
            ]),
            original("alien-question", "Alien Question", "Warble upward like a curious alien.", echo: 0.28, [
                .init(start: 0, duration: 0.95, from: 210, to: 570, timbre: .voice, vowel: .u, toVowel: .i, vibratoHz: 11, vibratoSemitones: 1.1),
            ]),
            original("frog-bounce", "Frog Bounce", "Low, low, then one springy high note.", [
                .init(start: 0, duration: 0.25, from: 115, to: 95, timbre: .buzz),
                .init(start: 0.32, duration: 0.25, from: 120, to: 100, timbre: .buzz),
                .init(start: 0.65, duration: 0.42, from: 145, to: 330, timbre: .buzz),
            ]),
        ]),
        SoundPack(id: "worldwide", name: "Vocal Gym", blurb: "Original vowels and rhythms.", symbol: "mouth.fill", tint: .sky, prompts: [
            original("vowel-wave", "Vowel Wave", "Oo–oh–ah in one smooth breath.", [
                .init(start: 0, duration: 1.25, from: 205, to: 245, timbre: .voice, vowel: .u, toVowel: .a, vibratoHz: 4.5, vibratoSemitones: 0.2),
            ]),
            original("hey-ho", "Hey Ho", "A short high call and a long low answer.", echo: 0.15, [
                .init(start: 0, duration: 0.25, from: 390, to: 430, timbre: .voice, vowel: .e),
                .init(start: 0.38, duration: 0.62, from: 240, to: 170, timbre: .voice, vowel: .o),
            ]),
            original("breath-riser", "Breath Riser", "Build from a hush into a bright finish.", [
                .init(start: 0, duration: 0.65, from: 500, to: 2600, timbre: .noise, gain: 0.38),
                .init(start: 0.58, duration: 0.38, from: 440, to: 660, timbre: .whistle),
            ]),
        ]),
        SoundPack(id: "brainrot", name: "Synth Chaos", blurb: "Original maximum nonsense.", symbol: "brain.head.profile", tint: .mint, prompts: [
            original("laser-duck", "Laser Duck", "Quack low, zap high, drop low again.", echo: 0.22, [
                .init(start: 0, duration: 0.22, from: 180, to: 125, timbre: .brass),
                .init(start: 0.24, duration: 0.28, from: 420, to: 1250, timbre: .whistle),
                .init(start: 0.55, duration: 0.35, from: 210, to: 90, timbre: .brass),
            ]),
            original("wobble-siren", "Wobble Siren", "Follow the fast up-down wobble.", echo: 0.2, [
                .init(start: 0, duration: 1.15, from: 260, to: 360, timbre: .horn, vibratoHz: 6.5, vibratoSemitones: 3),
            ]),
            original("bass-splat", "Bass Splat", "A huge falling boom with a tiny chirp.", [
                .init(start: 0, duration: 0.52, from: 115, to: 42, timbre: .boom, gain: 0.9),
                .init(start: 0.50, duration: 0.16, from: 880, to: 1180, timbre: .whistle, gain: 0.55),
            ]),
        ]),
        SoundPack(id: "lines", name: "Rhythm Calls", blurb: "Original call-and-response patterns.", symbol: "music.note.list", tint: .tangerine, prompts: [
            original("stadium-call", "Stadium Call", "Two short blasts and one long finale.", echo: 0.3, [
                .init(start: 0, duration: 0.20, from: 310, to: 330, timbre: .horn),
                .init(start: 0.34, duration: 0.20, from: 370, to: 390, timbre: .horn),
                .init(start: 0.68, duration: 0.62, from: 460, to: 520, timbre: .horn),
            ]),
            original("syncopated-buzz", "Syncopated Buzz", "Short-short, pause, long-short.", [
                .init(start: 0, duration: 0.14, from: 230, to: 260, timbre: .buzz),
                .init(start: 0.18, duration: 0.14, from: 280, to: 310, timbre: .buzz),
                .init(start: 0.52, duration: 0.38, from: 350, to: 290, timbre: .buzz),
                .init(start: 0.96, duration: 0.16, from: 430, to: 520, timbre: .buzz),
            ]),
            original("victory-yell", "Victory Yell", "Climb three notes and hold the last.", echo: 0.24, [
                .init(start: 0, duration: 0.22, from: 220, to: 240, timbre: .voice, vowel: .a),
                .init(start: 0.28, duration: 0.22, from: 280, to: 310, timbre: .voice, vowel: .a),
                .init(start: 0.56, duration: 0.72, from: 370, to: 440, timbre: .voice, vowel: .a, vibratoHz: 5, vibratoSemitones: 0.5),
            ]),
        ]),
    ]

    static func packs(realSounds: Bool) -> [SoundPack] {
        realSounds ? packs : originalPacks
    }

    static func pack(_ id: String) -> SoundPack? { packs.first { $0.id == id } }

    /// A prompt as mono samples at `sampleRate`: the recorded clip, or the synthesized
    /// voices with echo and normalised level.
    static func render(_ prompt: Prompt) -> [Float] {
        if let clip = prompt.clip { return clipSamples(clip) }
        var out = render(prompt.segments, tail: prompt.echo > 0 ? 0.7 : 0.15)
        if prompt.echo > 0 {
            let d1 = Int(0.19 * sampleRate), d2 = Int(0.31 * sampleRate)
            for n in d1..<out.count {
                var y = out[n] + Float(0.35 * prompt.echo) * out[n - d1]
                if n >= d2 { y += Float(0.22 * prompt.echo) * out[n - d2] }
                out[n] = y
            }
        }
        // Every prompt plays at the same loudness, whatever its timbre.
        let peak = out.map { abs($0) }.max() ?? 0
        if peak > 0 {
            let k = 0.85 / peak
            for i in out.indices { out[i] *= k }
        }
        return out
    }

    static func render(_ segments: [ToneSegment], tail: Double = 0.05) -> [Float] {
        let length = (segments.map { $0.start + $0.duration }.max() ?? 0) + tail
        var out = [Float](repeating: 0, count: Int(length * sampleRate))
        for (index, seg) in segments.enumerated() {
            let first = Int(seg.start * sampleRate)
            let count = Int(seg.duration * sampleRate)
            var phase = 0.0
            var rng = UInt64(0x9E37_79B9_7F4A_7C15) &+ UInt64(index) &* 0x1234_5679
            var res = (Resonator(), Resonator(), Resonator())
            for n in 0..<count where first + n < out.count {
                let t = Double(n) / sampleRate
                let q = t / seg.duration
                // Glide on a log scale so sweeps sound even to the ear.
                var hz = seg.from * pow(seg.to / seg.from, q)
                if seg.vibratoSemitones > 0 {
                    hz *= pow(2, seg.vibratoSemitones * sin(2 * .pi * seg.vibratoHz * t) / 12)
                }
                phase += 2 * .pi * hz / sampleRate
                var env = min(1, t / max(seg.attack, 0.0005)) * min(1, (seg.duration - t) / max(seg.release, 0.0005))
                if seg.tremoloHz > 0 { env *= 1 - 0.3 * (1 + sin(2 * .pi * seg.tremoloHz * t)) }
                let retune = n % 32 == 0

                let wave: Double
                switch seg.timbre {
                case .whistle:
                    wave = sin(phase)
                case .hum:
                    wave = sin(phase) + 0.45 * sin(2 * phase) + 0.2 * sin(3 * phase)
                case .buzz:
                    wave = (1...7).reduce(0) { $0 + sin(Double($1) * phase) / Double($1) }
                case .brass:
                    // The "wah" opens with each note's attack, like a trombone mute.
                    if retune { res.0.tune(450 + 1200 * min(1, t / 0.12), q: 2.2) }
                    let src = saw(phase, hz: hz, limit: 3500)
                    wave = 0.9 * res.0.process(src) + 0.25 * src
                case .horn:
                    if retune { res.0.tune(1300, q: 1.6) }
                    let src = saw(phase, hz: hz, limit: 4500) + saw(phase * 1.006, hz: hz, limit: 4500) + saw(phase * 0.994, hz: hz, limit: 4500)
                    wave = tanh(1.6 * (0.6 * res.0.process(src) + 0.25 * src))
                case .voice:
                    if retune {
                        let a = seg.vowel.formants, b = (seg.toVowel ?? seg.vowel).formants
                        res.0.tune(a.0 + (b.0 - a.0) * q, q: (a.0 + (b.0 - a.0) * q) / 80)
                        res.1.tune(a.1 + (b.1 - a.1) * q, q: (a.1 + (b.1 - a.1) * q) / 100)
                        res.2.tune(a.2 + (b.2 - a.2) * q, q: (a.2 + (b.2 - a.2) * q) / 140)
                    }
                    let src = saw(phase, hz: hz, limit: 4000)
                    wave = 1.4 * (res.0.process(src) + 0.6 * res.1.process(src) + 0.35 * res.2.process(src))
                case .noise:
                    if retune { res.0.tune(hz, q: 1.8); res.1.tune(hz, q: 1.8) }
                    rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let white = Double(Int64(bitPattern: rng >> 1) % 1_000_000) / 500_000 - 1
                    wave = 2.5 * res.1.process(res.0.process(white))
                case .boom:
                    wave = tanh(1.8 * (sin(phase) + 0.3 * sin(2 * phase)))
                }
                out[first + n] += Float(wave * env * seg.gain * 0.22)
            }
        }
        return out
    }

    // MARK: Recorded clips

    private static let clipLock = NSLock()
    nonisolated(unsafe) private static var clipCache: [String: [Float]] = [:]

    /// Decoded clip samples (mono, `sampleRate`), loaded once and cached. Thread-safe:
    /// scoring reads clips off the main thread.
    static func clipSamples(_ name: String) -> [Float] {
        clipLock.lock(); defer { clipLock.unlock() }
        if let cached = clipCache[name] { return cached }
        let samples = clipURL(name).flatMap(decode) ?? []
        clipCache[name] = samples
        return samples
    }

    private static func clipURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "m4a") { return url }
        if let url = Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds") { return url }
        // Command-line tools (tests) point here at the Sounds folder.
        if let dir = ProcessInfo.processInfo.environment["ECHOBLOOM_SOUNDS"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".m4a")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func decode(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: input)) != nil else { return nil }
        let capacity = AVAudioFrameCount(Double(file.length) * sampleRate / file.processingFormat.sampleRate) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil else { return nil }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    // MARK: Synthesis

    /// Band-limited sawtooth: harmonics up to `limit` Hz, so high notes don't alias.
    private static func saw(_ phase: Double, hz: Double, limit: Double) -> Double {
        let count = max(1, min(48, Int(limit / max(hz, 1))))
        var s = 0.0
        for k in 1...count { s += sin(Double(k) * phase) / Double(k) }
        return s * 0.6
    }

    /// Two-pole band-pass filter (RBJ cookbook, constant peak gain).
    private struct Resonator {
        var b0 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        mutating func tune(_ freq: Double, q: Double) {
            let w = 2 * .pi * min(freq, SoundLibrary.sampleRate * 0.45) / SoundLibrary.sampleRate
            let alpha = sin(w) / (2 * max(q, 0.3))
            let a0 = 1 + alpha
            b0 = alpha / a0
            b2 = -alpha / a0
            a1 = -2 * cos(w) / a0
            a2 = (1 - alpha) / a0
        }

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }

    @MainActor private static var envelopes: [String: [Double]] = [:]

    /// Loudness shape of a prompt as `bars` values in 0...1, for drawing.
    @MainActor static func envelope(_ prompt: Prompt, bars: Int) -> [Double] {
        let key = "\(prompt.id)#\(bars)"
        if let cached = envelopes[key] { return cached }
        let samples = render(prompt)
        let chunk = max(1, samples.count / bars)
        let peaks = (0..<bars).map { i -> Double in
            let slice = samples[min(i * chunk, samples.count - 1)..<min((i + 1) * chunk, samples.count)]
            return Double(slice.map { abs($0) }.max() ?? 0)
        }
        let top = max(peaks.max() ?? 1, 0.0001)
        let shape = peaks.map { 0.08 + 0.92 * $0 / top }
        envelopes[key] = shape
        return shape
    }

    /// Short interface sounds, synthesized like the prompts.
    enum Cue {
        case tick, go, reveal, pop

        var segments: [ToneSegment] {
            switch self {
            case .tick: [.init(start: 0, duration: 0.07, from: 880, to: 880, timbre: .whistle, gain: 0.6)]
            case .go: [.init(start: 0, duration: 0.18, from: 1320, to: 1320, timbre: .whistle, gain: 0.7)]
            case .reveal: [
                .init(start: 0, duration: 0.10, from: 523, to: 523, timbre: .whistle, gain: 0.6),
                .init(start: 0.09, duration: 0.10, from: 659, to: 659, timbre: .whistle, gain: 0.6),
                .init(start: 0.18, duration: 0.22, from: 784, to: 790, timbre: .whistle, gain: 0.6),
            ]
            case .pop: [.init(start: 0, duration: 0.09, from: 300, to: 900, gain: 0.7)]
            }
        }
    }
}
