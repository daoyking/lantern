import AVFoundation
import Foundation
import Combine

// MARK: - Wire protocol (M1: TEXT modality)

/// Gemini Live bidi session over URLSessionWebSocketTask.
///
/// Protocol (verified against Sapphire's GeminiAPI.swift, itself following
/// Google's Live API): one `setup` frame after resume, then bidirectional
/// JSON frames. M1 speaks text (`responseModalities: ["TEXT"]` on
/// `gemini-2.0-flash-live-001`); M2 flips to native-audio models.
final class GeminiLiveSession: NSObject {

    enum State: Equatable {
        case idle, connecting, open
        case closed(String?)   // reason, nil = clean
    }

    enum ServerEvent: Equatable {
        case setupComplete
        case modelText(String)
        case modelAudio(base64: String, mimeType: String)
        case turnComplete
        case interrupted
        case inputTranscription(String)
        case outputTranscription(String, finished: Bool)
        case error(String)
    }

    enum Modality { case text, audio }

    struct Config {
        let apiKey: String
        let model: String
        let modality: Modality
        let voiceName: String?
        let systemPrompt: String?
    }

    static let endpoint = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

    var onState: ((State) -> Void)?
    var onEvent: ((ServerEvent) -> Void)?

    private var task: URLSessionWebSocketTask?
    private lazy var urlSession = URLSession(configuration: .default)

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onState?(state) } }
    }

    // MARK: - Frame builders (exposed for tests)

    static func setupMessage(config: Config) -> Data {
        let modalities: [String]
        switch config.modality {
        case .text: modalities = ["TEXT"]
        case .audio: modalities = ["AUDIO"]
        }
        var generation: [String: Any] = ["responseModalities": modalities]
        if config.modality == .audio, let voice = config.voiceName {
            generation["speechConfig"] = [
                "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice]]
            ]
        }
        var setup: [String: Any] = [
            "model": "models/\(config.model)",
            "generationConfig": generation,
        ]
        if config.modality == .audio {
            setup["inputAudioTranscription"] = [:]
            setup["outputAudioTranscription"] = [:]
        }
        if let prompt = config.systemPrompt, !prompt.isEmpty {
            setup["systemInstruction"] = ["parts": [["text": prompt]]]
        }
        return try! JSONSerialization.data(withJSONObject: ["setup": setup])
    }

    /// Uplink audio chunk: `{"realtimeInput":{"audio":{"mimeType":"audio/pcm;rate=16000","data":...}}}`
    static func realtimeAudioMessage(pcm16: Data) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm16.base64EncodedString(),
                ]
            ]
        ])
    }

    static func clientContentMessage(text: String) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": text]]]],
                "turnComplete": true,
            ]
        ])
    }

    /// Defensive parse of one server frame; unknown shapes → nil.
    static func parseServer(_ data: Data) -> ServerEvent? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if obj["setupComplete"] as? [String: Any] != nil || obj.keys.contains("setupComplete") {
            return .setupComplete
        }
        if let error = obj["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "unknown Gemini error"
            return .error(message)
        }
        guard let content = obj["serverContent"] as? [String: Any] else { return nil }
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            return .interrupted
        }
        if let turn = content["modelTurn"] as? [String: Any],
           let parts = turn["parts"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return .modelText(text) }
            for part in parts {
                guard let inline = part["inlineData"] as? [String: Any] else { continue }
                let mime = (inline["mimeType"] as? String) ?? ""
                if mime.lowercased().contains("audio"),
                   let payload = inline["data"] as? String, !payload.isEmpty {
                    return .modelAudio(base64: payload, mimeType: mime)
                }
            }
        }
        if let input = content["inputTranscription"] as? [String: Any],
           let text = input["text"] as? String, !text.isEmpty {
            return .inputTranscription(text)
        }
        if let transcription = content["outputTranscription"] as? [String: Any],
           let text = transcription["text"] as? String {
            return .outputTranscription(text, finished: transcription["finished"] as? Bool ?? false)
        }
        if content["turnComplete"] != nil {
            return .turnComplete
        }
        return nil
    }

    // MARK: - Session lifecycle

    func connect(config: Config) {
        guard task == nil else { return }
        state = .connecting
        guard var components = URLComponents(string: Self.endpoint) else {
            state = .closed("bad endpoint"); return
        }
        components.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
        guard let url = components.url else {
            state = .closed("bad endpoint URL"); return
        }
        let task = urlSession.webSocketTask(with: url)
        self.task = task
        task.resume()
        listen()
        task.send(.data(Self.setupMessage(config: config))) { [weak self] error in
            if let error { self?.close(reason: error.localizedDescription) }
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data): self.emit(data)
                case .string(let string): self.emit(Data(string.utf8))
                @unknown default: break
                }
                self.listen()
            case .failure(let error):
                self.state = .closed(error.localizedDescription)
            }
        }
    }

    private func emit(_ data: Data) {
        guard let event = Self.parseServer(data) else { return }
        if case .setupComplete = event { state = .open }
        onEvent?(event)
    }

    func sendText(_ text: String) {
        send(.data(Self.clientContentMessage(text: text)))
    }

    func send(_ message: URLSessionWebSocketTask.Message) {
        task?.send(message) { [weak self] error in
            if let error { self?.close(reason: error.localizedDescription) }
        }
    }

    func close(reason: String? = nil) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed(reason)
    }
}

// MARK: - Service (feature gate + panel/island state)

/// Quick-checklist Sapphire #17 — Gemini Live. M1 scope: text turns from
/// the panel + live reply snippet on the island. The `geminiLiveEnabled`
/// toggle IS the connection (start = connect, stop = disconnect).
final class GeminiLiveService: BaseFeatureService {

    static let shared = GeminiLiveService(feature: .geminiLiveEnabled)

    /// M1 uses the bidi text-capable model; native-audio models reject TEXT
    /// modality. Overridable via `DefaultsKey.geminiModel`.
    static let defaultModel = "gemini-2.0-flash-live-001"

    static let systemPrompt =
        "You are Lantern, a concise macOS menu-bar assistant. Answer briefly."

    @Published public private(set) var sessionState: GeminiLiveSession.State = .idle
    @Published public private(set) var streamingReply: String = ""
    @Published public private(set) var lastReply: String?
    @Published public private(set) var voiceMode = false

    /// Native-audio voice model; TEXT models reject AUDIO modality.
    static let defaultVoiceModel = "gemini-2.5-flash-native-audio-preview-12-2025"
    static let defaultVoiceName = "Aoede"

    private var session: GeminiLiveSession?
    private let audioPipe = GeminiAudioPipe()

    public var voiceModel: String {
        UserDefaults.standard.string(forKey: DefaultsKey.geminiVoiceModel.rawValue)
            ?? Self.defaultVoiceModel
    }

    override init(feature: AppFeature) { super.init(feature: feature) }
    deinit { session?.close(); audioPipe.stopCapture() }

    // MARK: Key/model access

    public var apiKey: String? {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.geminiAPIKey.rawValue) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var model: String {
        UserDefaults.standard.string(forKey: DefaultsKey.geminiModel.rawValue) ?? Self.defaultModel
    }

    public var isOpen: Bool { sessionState == .open }

    // MARK: FeatureService

    override public func start() throws {
        guard let key = apiKey else {
            sessionState = .closed("missing-key")
            return
        }
        streamingReply = ""
        lastReply = nil
        let session = GeminiLiveSession()
        session.onState = { [weak self] state in self?.sessionState = state }
        session.onEvent = { [weak self] event in self?.handle(event) }
        if voiceMode {
            audioPipe.onChunk = { [weak session] chunk in
                session?.send(.data(GeminiLiveSession.realtimeAudioMessage(pcm16: chunk)))
            }
        }
        session.connect(config: .init(
            apiKey: key,
            model: voiceMode ? voiceModel : model,
            modality: voiceMode ? .audio : .text,
            voiceName: voiceMode ? Self.defaultVoiceName : nil,
            systemPrompt: Self.systemPrompt
        ))
        self.session = session
        if voiceMode {
            try? audioPipe.startCapture()
        }
    }

    override public func stop() throws {
        session?.close()
        session = nil
        audioPipe.stopCapture()
        audioPipe.stopPlayback()
        sessionState = .idle
    }

    // MARK: Turns

    public func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isOpen else { return }
        streamingReply = ""
        session?.sendText(trimmed)
    }

    /// Voice gate (geminiLiveTalk): flips the session between the text
    /// model and the native-audio model. Reconnects when already open.
    public func setVoiceMode(_ on: Bool) {
        guard voiceMode != on else { return }
        voiceMode = on
        if session != nil {
            session?.close()
            session = nil
            audioPipe.stopCapture()
            try? start()
        }
    }

    private func handle(_ event: GeminiLiveSession.ServerEvent) {
        switch event {
        case .modelText(let text):
            streamingReply += text
        case .modelAudio(let base64, let mimeType):
            guard let payload = Data(base64Encoded: base64),
                  let rate = GeminiAudioPipe.pcmRate(fromMimeType: mimeType)
            else { return }
            if !streamingReply.isEmpty { lastReply = streamingReply }
            streamingReply = ""
            audioPipe.play(pcm16: payload, sampleRate: rate)
        case .turnComplete:
            if !streamingReply.isEmpty { lastReply = streamingReply }
            streamingReply = ""
        case .interrupted:
            streamingReply = ""
            audioPipe.stopPlayback()
        case .inputTranscription(let text):
            streamingReply += text
        case .error(let message):
            sessionState = .closed(message)
        case .setupComplete, .outputTranscription:
            break
        }
    }
}


// MARK: - Voice gate (separate feature, same pipeline)

/// `geminiLiveTalk` toggle: switches the shared Gemini session between
/// text mode and native-audio voice mode. Registered in AppDelegate.
final class GeminiVoiceService: BaseFeatureService {
    static let shared = GeminiVoiceService(feature: .geminiLiveTalk)

    override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws { GeminiLiveService.shared.setVoiceMode(true) }
    override public func stop() throws { GeminiLiveService.shared.setVoiceMode(false) }
}
