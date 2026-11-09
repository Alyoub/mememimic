import AVFoundation

/// Collects microphone samples from the real-time tap. The tap runs off the main thread,
/// so access goes through a lock.
final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var level: Float = 0

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = n > 0 ? sqrt(sum / Float(n)) : 0
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: n))
        level = rms
        lock.unlock()
    }

    var currentLevel: Float { lock.lock(); defer { lock.unlock() }; return level }
    var allSamples: [Float] { lock.lock(); defer { lock.unlock() }; return samples }
}

struct RecordedTake {
    let samples: [Float]
    let sampleRate: Double
}

/// Owns the microphone engine. Every call that touches audio hardware runs on a private
/// serial queue: session activation and input start-up can block for a long time
/// (indefinitely on some simulators), and must never stall the UI.
private final class MicRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "echobloom.mic")
    private var engine: AVAudioEngine?
    private(set) var sink: SampleSink?
    private var rate = 48_000.0

    func start() async -> Bool {
        await withCheckedContinuation { done in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                    try session.setActive(true)
                } catch {
                    done.resume(returning: false); return
                }
                let engine = AVAudioEngine()
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.channelCount > 0, format.sampleRate > 0 else { done.resume(returning: false); return }
                let sink = SampleSink()
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
                do {
                    try engine.start()
                } catch {
                    input.removeTap(onBus: 0)
                    done.resume(returning: false); return
                }
                self.engine = engine
                self.sink = sink
                self.rate = format.sampleRate
                done.resume(returning: true)
            }
        }
    }

    func stop() async -> RecordedTake? {
        await withCheckedContinuation { done in
            queue.async {
                guard let engine = self.engine, let sink = self.sink else { done.resume(returning: nil); return }
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                self.engine = nil
                self.sink = nil
                // Back to playback-only so the mic indicator turns off.
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                done.resume(returning: RecordedTake(samples: sink.allSamples, sampleRate: self.rate))
            }
        }
    }
}

@MainActor
final class AudioEngine {
    enum MicAccess { case unknown, granted, denied }

    private let playback = AVAudioEngine()
    private let promptPlayer = AVAudioPlayerNode()
    private let takePlayer = AVAudioPlayerNode()
    private let promptFormat = AVAudioFormat(standardFormatWithSampleRate: SoundLibrary.sampleRate, channels: 1)!
    private let mic = MicRecorder()
    private var activeSink: SampleSink?

    var muted = false

    init() {
        // The playback graph is built on first use, not here: touching the engine's
        // output asks the system audio server for its format, and if that server is slow
        // to answer (it happens, e.g. after a call or an audio-server restart) CoreAudio
        // aborts the app. At launch that would be a crash before the first frame.
        // Playback-only until a take actually starts; activated off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
        }
    }

    var micAccess: MicAccess {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    func requestMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    private var graphReady = false

    private func startPlaybackEngine() {
        if !graphReady {
            playback.attach(promptPlayer)
            playback.attach(takePlayer)
            playback.connect(promptPlayer, to: playback.mainMixerNode, format: promptFormat)
            graphReady = true
        }
        guard !playback.isRunning else { return }
        try? playback.start()
    }

    // MARK: Playback

    /// Plays mono samples rendered at `SoundLibrary.sampleRate`. Returns the clip length.
    @discardableResult
    func play(_ samples: [Float], force: Bool = false) -> Double {
        let seconds = Double(samples.count) / SoundLibrary.sampleRate
        guard !muted || force, let buffer = makeBuffer(samples, format: promptFormat) else { return seconds }
        startPlaybackEngine()
        promptPlayer.stop()
        promptPlayer.scheduleBuffer(buffer)
        promptPlayer.play()
        return seconds
    }

    func cue(_ cue: SoundLibrary.Cue) {
        play(SoundLibrary.render(cue.segments))
    }

    func playTake(_ take: RecordedTake) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: take.sampleRate, channels: 1),
              let buffer = makeBuffer(take.samples, format: format) else { return }
        startPlaybackEngine()
        promptPlayer.stop()
        takePlayer.stop()
        playback.disconnectNodeOutput(takePlayer)
        playback.connect(takePlayer, to: playback.mainMixerNode, format: format)
        takePlayer.scheduleBuffer(buffer)
        takePlayer.play()
    }

    func stopPlayback() {
        guard graphReady else { return }   // nothing has played yet
        promptPlayer.stop()
        takePlayer.stop()
    }

    private func makeBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }

    // MARK: Recording

    func startRecording() async -> Bool {
        stopPlayback()
        guard await mic.start() else { return false }
        activeSink = mic.sink
        return true
    }

    var inputLevel: Float { activeSink?.currentLevel ?? 0 }

    func stopRecording() async -> RecordedTake? {
        activeSink = nil
        return await mic.stop()
    }

    func cancelRecording() {
        guard activeSink != nil else { return }
        activeSink = nil
        Task { _ = await mic.stop() }
    }
}
