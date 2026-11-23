import AVFoundation
import Foundation

/// Shared audio pipeline for Gemini Live voice mode (M2).
///
/// Uplink: AVAudioEngine input tap → AVAudioConverter → Int16 / 16 kHz /
/// mono → raw PCM Data chunks (caller base64-encodes into
/// `realtimeInput.audio` frames).
///
/// Downlink: Gemini returns base64 Int16 PCM (rate from the mimeType) →
/// Float32 buffer scheduled on the engine's playerNode. One engine serves
/// both directions; barge-in (`.interrupted`) stops playback immediately.
final class GeminiAudioPipe {

    static let upSampleRate: Double = 16000

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?

    private let sendQueue = DispatchQueue(label: "lantern.gemini.audio")

    /// Serial-chunk uplink callback (Int16 little-endian, 16 kHz mono).
    var onChunk: ((Data) -> Void)?

    private(set) var isCapturing = false
    private(set) var isPlaying = false

    // MARK: - Pure helpers (unit-tested)

    /// "audio/pcm;rate=24000" → 24000. Nil when the mimeType carries no rate.
    static func pcmRate(fromMimeType mimeType: String) -> Double? {
        guard let range = mimeType.range(of: #"rate=(\d+)"#, options: .regularExpression) else {
            return nil
        }
        let digits = mimeType[range].dropFirst("rate=".count)
        return Double(digits)
    }

    /// Int16 little-endian mono PCM → interleaved-free Float32 buffer.
    static func floatBuffer(fromPCM16 data: Data, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = data.count / 2
        guard frameCount > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let samples = raw.bindMemory(to: Int16.self)
            let dst = buffer.floatChannelData![0]
            for i in 0..<frameCount {
                dst[i] = Float(Int16(littleEndian: samples[i])) / 32768.0
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    // MARK: - Capture (uplink)

    func startCapture() throws {
        guard !isCapturing else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.upSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "lantern.gemini", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "cannot build 16k Int16 format"])
        }
        let converter = AVAudioConverter(from: inputFormat, to: target)
        self.converter = converter
        captureFormat = target

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.convertAndEmit(buffer)
        }
        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        converter = nil
    }

    private func convertAndEmit(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let captureFormat else { return }
        let ratio = Self.upSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard capacity > 0,
              let out = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity)
        else { return }

        var consumed = false
        let status = converter.convert(to: out, error: nil) { _, statusOut in
            if consumed {
                statusOut.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        guard status == .haveData, let int16 = out.int16ChannelData, out.frameLength > 0 else {
            return
        }
        let chunk = Data(bytes: int16, count: Int(out.frameLength) * 2)
        sendQueue.async { [weak self] in
            self?.onChunk?(chunk)
        }
    }

    // MARK: - Playback (downlink)

    func ensurePlaybackGraph() {
        if !engine.isRunning {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            try? engine.start()
        }
    }

    func play(pcm16 data: Data, sampleRate: Double) {
        guard let buffer = Self.floatBuffer(fromPCM16: data, sampleRate: sampleRate) else { return }
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.ensurePlaybackGraph()
            self.player.scheduleBuffer(buffer)
            if !self.player.isPlaying {
                self.player.play()
                self.isPlaying = true
            }
        }
    }

    /// Barge-in: Gemini said we were interrupted — drop pending audio now.
    func stopPlayback() {
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.isPlaying = false
        }
    }
}
