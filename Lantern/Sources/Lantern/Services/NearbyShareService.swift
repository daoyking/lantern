import AppKit
import CryptoKit
import Foundation
import Network

// MARK: - Wire protocol (Lantern↔Lantern, JSON frames)

/// Frame set for the Lantern-to-Lantern share channel. Deliberately NOT the
/// Quick Share wire format (that needs vendored protobuf + UKEY2); this is
/// the self-family transport: same skeleton — mDNS discovery, 4-byte
/// big-endian length prefix, ephemeral ECDH P-256 → HKDF → AES-GCM per
/// frame — but JSON payloads and a `_lantern-share._tcp.` service type.
enum NearbyFrame: Equatable {
    case hello(name: String, pubKey: String)
    case offer(id: String, sender: String, kind: String, text: String?, fileNames: [String])
    case accept(id: String)
    case reject(id: String)
    case chunk(id: String, index: Int, data: Data, last: Bool)
    case done(id: String)

    private var dict: [String: Any] {
        switch self {
        case .hello(let name, let pubKey):
            return ["t": "hello", "name": name, "pub": pubKey]
        case .offer(let id, let sender, let kind, let text, let fileNames):
            var d: [String: Any] = ["t": "offer", "id": id, "from": sender, "kind": kind, "files": fileNames]
            if let text { d["text"] = text }
            return d
        case .accept(let id): return ["t": "accept", "id": id]
        case .reject(let id): return ["t": "reject", "id": id]
        case .chunk(let id, let index, let data, let last):
            return ["t": "chunk", "id": id, "i": index, "d": data.base64EncodedString(), "last": last]
        case .done(let id): return ["t": "done", "id": id]
        }
    }

    var data: Data { try! JSONSerialization.data(withJSONObject: dict) }

    static func parse(_ data: Data) -> NearbyFrame? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["t"] as? String else { return nil }
        switch type {
        case "hello":
            guard let name = obj["name"] as? String, let pub = obj["pub"] as? String else { return nil }
            return .hello(name: name, pubKey: pub)
        case "offer":
            guard let id = obj["id"] as? String, let sender = obj["from"] as? String,
                  let kind = obj["kind"] as? String, let files = obj["files"] as? [String] else { return nil }
            return .offer(id: id, sender: sender, kind: kind, text: obj["text"] as? String, fileNames: files)
        case "accept": return (obj["id"] as? String).map { .accept(id: $0) }
        case "reject": return (obj["id"] as? String).map { .reject(id: $0) }
        case "chunk":
            guard let id = obj["id"] as? String,
                  let index = (obj["i"] as? NSNumber)?.intValue,
                  let b64 = obj["d"] as? String,
                  let payload = Data(base64Encoded: b64),
                  let last = obj["last"] as? Bool else { return nil }
            return .chunk(id: id, index: index, data: payload, last: last)
        case "done": return (obj["id"] as? String).map { .done(id: $0) }
        default: return nil
        }
    }
}

// MARK: - Crypto (zero-dependency: CryptoKit replaces Sapphire's SwiftECC)

enum NearbyCrypto {
    static let salt = Data("lantern-share v1".utf8)

    static func makeKeyPair() -> P256.KeyAgreement.PrivateKey { P256.KeyAgreement.PrivateKey() }

    /// ECDH P-256 → HKDF-SHA256 → 32-byte AES-GCM key. Both sides derive
    /// the identical key from their private and the peer's public key.
    static func sessionKey(privateKey: P256.KeyAgreement.PrivateKey,
                           peerPublicKeyData: Data) -> SymmetricKey? {
        guard let peer = try? P256.KeyAgreement.PublicKey(x963Representation: peerPublicKeyData),
              let secret = try? privateKey.sharedSecretFromKeyAgreement(with: peer)
        else { return nil }
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: salt,
            sharedInfo: Data("session".utf8), outputByteCount: 32
        )
    }

    static func seal(_ frame: Data, key: SymmetricKey) -> Data? {
        try? AES.GCM.seal(frame, using: key).combined
    }

    static func open(_ combined: Data, key: SymmetricKey) -> Data? {
        try? AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
    }

    /// Wire encoding: 4-byte big-endian length prefix + payload.
    static func prefixed(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + payload
    }

    /// Split a payload stream back into (prefixRemoved) chunks.
    static func unprefix(_ buffer: [UInt8]) -> (payload: Data, remainder: [UInt8])? {
        guard buffer.count >= 4 else { return nil }
        let length = (UInt32(buffer[0]) << 24) | (UInt32(buffer[1]) << 16)
            | (UInt32(buffer[2]) << 8) | UInt32(buffer[3])
        guard buffer.count >= 4 + Int(length) else { return nil }
        let payload = Data(buffer[4..<4 + Int(length)])
        return (payload, Array(buffer[(4 + Int(length))...]))
    }
}

// MARK: - Per-connection session

/// One TCP connection to (or from) a peer: handshake, framed IO, transfers.
final class NearbyPeerSession {
    enum Phase { case handshaking, ready, closed }

    let connection: NWConnection
    private let ownKey: P256.KeyAgreement.PrivateKey
    private(set) var key: SymmetricKey?
    private(set) var phase: Phase = .handshaking
    private(set) var peerName = "…"

    /// Outgoing transfer state
    private var pendingTransferID: String?
    private var outgoingChunks: [Data] = []
    private var outgoingIndex = 0

    /// Incoming reassembly: transferID → (index → payload)
    private var incomingChunks: [String: [Int: Data]] = [:]

    var onEvent: ((NearbyPeerSession, NearbyFrame) -> Void)?
    var onReady: ((NearbyPeerSession, String) -> Void)?
    var onClosed: ((NearbyPeerSession) -> Void)?

    private var buffer: [UInt8] = []

    init(connection: NWConnection, ownKey: P256.KeyAgreement.PrivateKey) {
        self.connection = connection
        self.ownKey = ownKey
    }

    func start(ownName: String) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendHello(ownName: ownName)
                self?.receiveLoop()
            case .failed, .cancelled:
                guard let self else { return }
                self.phase = .closed
                self.onClosed?(self)
            default: break
            }
        }
        connection.start(queue: .main)
    }

    func cancel() {
        phase = .closed
        connection.cancel()
    }

    // MARK: Handshake

    private func sendHello(ownName: String) {
        send(plaintext: NearbyFrame.hello(
            name: ownName,
            pubKey: ownKey.publicKey.x963Representation.base64EncodedString()
        ).data)
    }

    private func establish(from frame: NearbyFrame) {
        guard case .hello(let name, let pub) = frame,
              let peerKeyData = Data(base64Encoded: pub),
              let key = NearbyCrypto.sessionKey(privateKey: ownKey, peerPublicKeyData: peerKeyData)
        else {
            cancel()
            return
        }
        self.key = key
        peerName = name
        phase = .ready
        onReady?(self, name)
    }

    var isReady: Bool { phase == .ready }

    // MARK: IO

    private func send(plaintext: Data) {
        connection.send(content: NearbyCrypto.prefixed(plaintext), completion: .contentProcessed { _ in })
    }

    func send(_ frame: NearbyFrame) {
        guard let key else { return }
        guard let sealed = NearbyCrypto.seal(frame.data, key: key) else { return }
        connection.send(content: NearbyCrypto.prefixed(sealed), completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] content, _, isComplete, _ in
            guard let self else { return }
            if let content, !content.isEmpty {
                self.buffer.append(contentsOf: content)
                self.drain()
            }
            if isComplete {
                self.phase = .closed
                self.onClosed?(self)
                return
            }
            self.receiveLoop()
        }
    }

    private func drain() {
        while true {
            guard let (payload, remainder) = NearbyCrypto.unprefix(buffer) else { return }
            buffer = remainder
            if phase == .handshaking {
                guard let frame = NearbyFrame.parse(payload), case .hello = frame else {
                    cancel(); return
                }
                establish(from: frame)
            } else if let key {
                guard let plain = NearbyCrypto.open(payload, key: key),
                      let frame = NearbyFrame.parse(plain) else {
                    cancel(); return
                }
                handle(frame)
            }
        }
    }

    private func handle(_ frame: NearbyFrame) {
        if case .hello = frame { return } // late hellos ignored
        onEvent?(self, frame)
    }

    // MARK: Outgoing transfer (offer → accept → chunks → done)

    func sendTransfer(text: String, transferID: String, senderName: String) {
        let payload = Data(text.utf8)
        pendingTransferID = transferID
        outgoingChunks = Self.chunks(of: payload)
        outgoingIndex = 0
        send(.offer(id: transferID, sender: senderName, kind: "text", text: text, fileNames: []))
    }

    func handleOutgoing(_ frame: NearbyFrame) {
        guard let id = pendingTransferID else { return }
        switch frame {
        case .accept(let acceptedID) where acceptedID == id:
            for (index, chunk) in outgoingChunks.enumerated() {
                send(.chunk(id: id, index: index, data: chunk, last: index == outgoingChunks.count - 1))
            }
            send(.done(id: id))
            pendingTransferID = nil
        case .reject(let rejectedID) where rejectedID == id:
            pendingTransferID = nil
        default: break
        }
    }

    /// ≤48 KB raw chunks — base64 inflates 4/3, frames stay well under the
    /// 256 KB receive window.
    static func chunks(of data: Data, size: Int = 48_000) -> [Data] {
        guard data.count > 0 else { return [Data()] }
        return stride(from: 0, to: data.count, by: size).map {
            data.subdata(in: $0..<min($0 + size, data.count))
        }
    }

    // MARK: Incoming assembly

    func ingest(_ frame: NearbyFrame) -> (id: String, assembled: Data?)? {
        switch frame {
        case .chunk(let id, let index, let data, let last):
            var slots = incomingChunks[id] ?? [:]
            slots[index] = data
            if last {
                incomingChunks[id] = nil
                let ordered = slots.sorted { $0.key < $1.key }.map { $0.value }
                return (id, Data(ordered.joined()))
            }
            incomingChunks[id] = slots
            return (id, nil)
        default:
            return nil
        }
    }
}

// MARK: - Feature service

/// Sapphire-exclusive #18, self-family edition: text snippets between
/// Lantern instances over the local network. Discovery via
/// `_lantern-share._tcp.` mDNS + NWBrowser; frames ECDH-sealed.
final class NearbyShareService: BaseFeatureService {

    static let shared = NearbyShareService(feature: .nearbyShare)
    static let serviceType = "_lantern-share._tcp."
    static let chunkSize = 48_000

    struct Peer: Identifiable, Equatable {
        let id: String
        let name: String
    }

    struct Prompt: Identifiable, Equatable {
        let id: String
        let peerName: String
        let preview: String
    }

    @Published public private(set) var peers: [Peer] = []
    @Published public private(set) var prompt: Prompt?
    @Published public private(set) var lastReceived: String?
    @Published public private(set) var lastError: String?

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var netService: NetService?
    private var sessions: [String: NearbyPeerSession] = [:]
    private var ownKey = NearbyCrypto.makeKeyPair()

    var ownName = Host.current().localizedName ?? "Lantern"

    override init(feature: AppFeature) { super.init(feature: feature) }
    deinit { stopListener() }

    override public func start() throws {
        ownKey = NearbyCrypto.makeKeyPair()
        startListener()
        startBrowser()
    }

    override public func stop() throws {
        stopListener()
        sessions.values.forEach { $0.cancel() }
        sessions.removeAll()
        peers = []
        prompt = nil
    }

    // MARK: Listener + advertisement

    private func startListener() {
        let listener = try? NWListener(using: .tcp, on: .any)
        guard let listener else {
            lastError = "listener unavailable"
            return
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, case .ready = state, let port = listener.port else { return }
            self.advertise(port: port)
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func advertise(port: NWEndpoint.Port) {
        let service = NetService(
            domain: "", type: Self.serviceType,
            name: ownName, port: Int32(port.rawValue)
        )
        service.schedule(in: .main, forMode: .common)
        service.publish()
        netService = service
    }

    private func startBrowser() {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.syncPeers(from: Array(results))
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.lastError = error.localizedDescription
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        netService?.stop()
        netService = nil
    }

    private func syncPeers(from results: [NWBrowser.Result]) {
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            if name == ownName { continue } // skip self
            let id = "\(name).\(type).\(domain)"
            guard sessions[id] == nil else { continue }
            let connection = NWConnection(
                to: .service(name: name, type: type, domain: domain, interface: nil),
                using: .tcp
            )
            attach(session: NearbyPeerSession(connection: connection, ownKey: ownKey), id: id)
        }
    }

    private func accept(connection: NWConnection) {
        let id = "in-\(UUID().uuidString)"
        attach(session: NearbyPeerSession(connection: connection, ownKey: ownKey), id: id)
    }

    private func attach(session: NearbyPeerSession, id: String) {
        sessions[id] = session
        session.onReady = { [weak self] session, name in
            self?.upsertPeer(id: id, name: name)
        }
        session.onEvent = { [weak self] peerSession, frame in
            self?.handle(frame, from: peerSession, peerID: id)
        }
        session.onClosed = { [weak self] _ in
            self?.sessions.removeValue(forKey: id)
            self?.peers.removeAll { $0.id == id }
        }
        session.start(ownName: ownName)
    }

    private func upsertPeer(id: String, name: String) {
        // Both sides browse each other and may open mirrored connections;
        // keep the first ready one per machine name.
        if peers.contains(where: { $0.name == name && $0.id != id }) {
            sessions[id]?.cancel()
            sessions.removeValue(forKey: id)
            return
        }
        let peer = Peer(id: id, name: name)
        if let index = peers.firstIndex(where: { $0.id == id }) {
            peers[index] = peer
        } else {
            peers.append(peer)
        }
    }

    // MARK: Transfers

    public func sendText(_ text: String, to peerID: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let session = sessions[peerID], session.isReady else {
            lastError = "peer not ready"
            return
        }
        session.sendTransfer(
            text: trimmed,
            transferID: UUID().uuidString,
            senderName: ownName
        )
    }

    public func acceptPrompt() {
        guard let prompt else { return }
        sessions[prompt.id]?.send(.accept(id: prompt.id))
        self.prompt = nil
    }

    public func rejectPrompt() {
        guard let prompt else { return }
        sessions[prompt.id]?.send(.reject(id: prompt.id))
        self.prompt = nil
    }

    private func handle(_ frame: NearbyFrame, from session: NearbyPeerSession, peerID: String) {
        switch frame {
        case .offer(let id, let sender, let kind, let text, _):
            guard kind == "text" else {
                session.send(.reject(id: id)) // file offers: v1 is text-only
                return
            }
            let preview = (text ?? "").prefix(120)
            prompt = Prompt(id: id, peerName: sender, preview: String(preview))
            NearbyCards.present(prompt: prompt!)

        case .accept, .reject:
            session.handleOutgoing(frame)

        case .chunk, .done:
            if let (_, assembled) = session.ingest(frame), let payload = assembled {
                deliver(text: String(data: payload, encoding: .utf8) ?? "", from: session.peerName)
            }

        case .hello:
            break
        }
    }

    private func deliver(text: String, from peerName: String) {
        ClipboardService.shared?.copy(text)
        lastReceived = text
        NearbyCards.presentReceived(from: peerName, preview: String(text.prefix(120)))
    }
}

