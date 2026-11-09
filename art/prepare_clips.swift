// Turns raw meme clips into short, level-matched game prompts.
//
//   swiftc -O art/prepare_clips.swift -o /tmp/prepare_clips
//   /tmp/prepare_clips mp3 EchoBloom/Sounds
//
// Each input becomes <out>/<name>.m4a: mono 44.1 kHz AAC, silence trimmed, at most
// `maxLength` seconds long, faded at both ends and normalised. Clips longer than that
// keep the earliest window that is nearly as loud as the loudest one, which is usually
// where the meme lands. Prints the window chosen for each file.
import AVFoundation
import Foundation

let maxLength = 4.5
let rate = 44_100.0

func readMono(_ url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url)
    let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let converter = AVAudioConverter(from: file.processingFormat, to: target)!
    let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: input)
    let capacity = AVAudioFrameCount(Double(file.length) * rate / file.processingFormat.sampleRate) + 4096
    let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)!
    var fed = false
    var error: NSError?
    converter.convert(to: output, error: &error) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true
        status.pointee = .haveData
        return input
    }
    if let error { throw error }
    return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
}

func writeAAC(_ samples: [Float], to url: URL) throws {
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000]
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
    try file.write(from: buffer)
}

/// RMS per 20 ms window.
func loudness(_ x: [Float]) -> [Float] {
    let hop = Int(rate * 0.02)
    return stride(from: 0, to: x.count, by: hop).map { s in
        let e = min(s + hop, x.count)
        var sum: Float = 0
        for i in s..<e { sum += x[i] * x[i] }
        return sqrt(sum / Float(max(1, e - s)))
    }
}

let args = CommandLine.arguments
let inDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "mp3" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

for url in files {
    var x = try readMono(url)
    let hop = Int(rate * 0.02)
    let rms = loudness(x)
    let peak = rms.max() ?? 0
    // Trim leading and trailing silence (below 3% of the loudest window; higher cut
    // into quiet words after a loud one).
    let gate = peak * 0.03
    let first = rms.firstIndex { $0 > gate } ?? 0
    let last = rms.lastIndex { $0 > gate } ?? (rms.count - 1)
    var startWin = first, endWin = last + 1
    let maxWins = Int(maxLength / 0.02)
    if endWin - startWin > maxWins {
        // Earliest window whose mean loudness is within 85% of the best window.
        var sums: [Float] = []
        var running: Float = rms[startWin..<(startWin + maxWins)].reduce(0, +)
        sums.append(running)
        for s in (startWin + 1)...(endWin - maxWins) {
            running += rms[s + maxWins - 1] - rms[s - 1]
            sums.append(running)
        }
        let best = sums.max() ?? 0
        let pick = sums.firstIndex { $0 >= best * 0.85 } ?? 0
        startWin += pick
        endWin = startWin + maxWins
    }
    let a = max(0, startWin * hop - Int(rate * 0.03)), b = min(x.count, endWin * hop + Int(rate * 0.05))
    x = Array(x[a..<b])
    // Fades so trims never click, then normalise to -1 dBFS.
    let fadeIn = Int(rate * 0.015), fadeOut = Int(rate * 0.08)
    for i in 0..<min(fadeIn, x.count) { x[i] *= Float(i) / Float(fadeIn) }
    for i in 0..<min(fadeOut, x.count) { x[x.count - 1 - i] *= Float(i) / Float(fadeOut) }
    let top = x.map { abs($0) }.max() ?? 1
    if top > 0 { for i in x.indices { x[i] *= 0.89 / top } }

    let name = url.deletingPathExtension().lastPathComponent
    try writeAAC(x, to: outDir.appendingPathComponent(name + ".m4a"))
    print(String(format: "%-52@ %6.2fs -> %5.2f..%5.2f (%4.2fs)", name as NSString,
                 Double(rms.count) * 0.02, Double(a) / rate, Double(b) / rate, Double(x.count) / rate))
}
