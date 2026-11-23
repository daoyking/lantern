import AppKit
import AVFoundation
import Accelerate
import CoreML
import CryptoKit
import Vision

// MARK: - Face ID (Sapphire subset): webcam face verification for panel lock
//
// Sapphire authenticates the user with a software face pipeline: the FaceTime
// camera feeds Vision face landmarks → 112×112 aligned crop → ArcFace Core ML
// embedding → cosine similarity against an enrolled profile, with a passive
// anti-spoof model guarding against photos. No TrueDepth hardware involved —
// this runs on any Mac with a camera, which is why it belongs in Lantern too.
//
// Lean-port scope (documented simplifications):
// - Built-in front camera only (no RotationCoordinator dance).
// - Single embedding color order (.rgb) — Sapphire's own enrollment only
//   produces rgb profiles, so the adaptive-order auth path is dead weight.
// - No debug capture folder, no idle unloading (models load once per session).
// - Storage uses CryptoKit AES-GCM with a Keychain-held key instead of
//   Sapphire's CryptoManager. Same on-disk idea: encrypted JSON in
//   Application Support.

// MARK: Configuration

enum FaceIDConfig {
    /// Cosine score above which a frame counts as a match.
    static let identityThreshold: Float = 0.48
    /// Consecutive matching frames required to authenticate.
    static let consecutiveFrames = 3
    /// Liveness logit (10-frame window mean) above which the face is real.
    static let livenessLogitThreshold: Double = -0.42
    /// Frames averaged for the liveness decision.
    static let livenessWindow = 10
    /// Face crop must be at least this wide (px) for a usable embedding.
    static let minFacePixels: CGFloat = 64
    /// Laplacian-variance sharpness gate (×1000): below = blurry frame.
    static let sharpnessSoft: Float = 3.5
    static let sharpnessHard: Float = 5.5
    /// Sustained-spoof lockout / overall mismatch timeout.
    static let spoofSustainedSeconds: TimeInterval = 2.5
    static let mismatchTimeoutSeconds: TimeInterval = 6.0
    /// A panel verification stays valid this long before re-prompting.
    static let verifyGraceSeconds: TimeInterval = 60
    /// Registration buckets: two frontal takes, one from each side.
    static let registrationBuckets: [(name: String, yaw: ClosedRange<Float>)] = [
        ("center", -0.14...0.14),
        ("center2", -0.14...0.14),
        ("left", 0.20...0.9),
        ("right", -0.9...(-0.20)),
    ]
    static let framesPerBucket = 4
}

// MARK: Math

enum FaceIDMath {
    /// L2-normalize in place; nil-safe for zero vectors.
    static func l2Normalize(_ vector: [Float]) -> [Float] {
        var v = vector
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        let n = sqrtf(norm)
        guard n > 0 else { return v }
        var scale = 1 / n
        vDSP_vsmul(v, 1, &scale, &v, 1, vDSP_Length(v.count))
        return v
    }

    /// Cosine similarity of two equal-length vectors.
    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        var na: Float = 0, nb: Float = 0
        vDSP_svesq(a, 1, &na, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &nb, vDSP_Length(b.count))
        let denom = sqrtf(na) * sqrtf(nb)
        return denom > 0 ? dot / denom : 0
    }

    /// Sapphire blend: identity score mixes best single print and centroid.
    static func profileScore(embedding: [Float], prints: [[Float]], centroid: [Float]) -> Float {
        let best = prints.map { cosine(embedding, $0) }.max() ?? 0
        return 0.85 * best + 0.15 * cosine(embedding, centroid)
    }

    /// Test-time augmentation: average of the original and mirrored embeddings.
    static func ttaEmbedding(original: [Float], flipped: [Float]) -> [Float] {
        guard original.count == flipped.count, !original.isEmpty else { return l2Normalize(original) }
        var sum = [Float](repeating: 0, count: original.count)
        vDSP_vadd(original, 1, flipped, 1, &sum, 1, vDSP_Length(original.count))
        return l2Normalize(sum)
    }

    /// Crop rect for the anti-spoof model: expand the face box by 1.256,
    /// shift up by 11.4 %, then take a square of `faceSide * cropScale`.
    static func livenessCropRect(faceBox: CGRect, imageSize: CGSize, cropScale: Double) -> CGRect {
        let expanded = faceBox.insetBy(dx: -faceBox.width * 0.128, dy: -faceBox.height * 0.128)
        let raised = expanded.offsetBy(dx: 0, dy: -expanded.height * 0.114)
        let side = CGFloat(cropScale) * max(raised.width, raised.height)
        var center = CGPoint(x: raised.midX, y: raised.midY)
        center.x = min(max(center.x, side / 2), imageSize.width - side / 2)
        center.y = min(max(center.y, side / 2), imageSize.height - side / 2)
        return CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }
}

// MARK: Encrypted profile store

struct FaceProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var prints: [[Float]]
    var centroid: [Float]
}

/// Face profiles on disk, AES-GCM sealed with a Keychain-held key.
final class FaceIDStore {
    static let fileName = "faceprints_fast.encrypted"

    private let fileURL: URL
    private let keyProvider: () throws -> SymmetricKey

    init(keyProvider: @escaping () throws -> SymmetricKey = FaceIDStore.keychainKey,
         filePath: URL? = nil) {
        if let filePath {
            fileURL = filePath
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = support.appendingPathComponent("Lantern", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent(Self.fileName)
        }
        self.keyProvider = keyProvider
    }

    var profile: FaceProfile?

    func load() {
        guard let sealed = try? Data(contentsOf: fileURL), sealed.count > 12 else { return }
        guard let key = try? keyProvider() else { return }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key)
            profile = try JSONDecoder().decode(FaceProfile.self, from: plain)
        } catch {
            profile = nil
        }
    }

    func save(_ newProfile: FaceProfile) throws {
        let key = try keyProvider()
        let plain = try JSONEncoder().encode(newProfile)
        let sealed = try AES.GCM.seal(plain, using: key).combined!
        try sealed.write(to: fileURL)
        profile = newProfile
    }

    func erase() {
        profile = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    var hasProfile: Bool { profile != nil }

    /// Best score across every stored print plus the centroid.
    func score(embedding: [Float]) -> Float {
        guard let profile else { return 0 }
        return FaceIDMath.profileScore(embedding: embedding, prints: profile.prints, centroid: profile.centroid)
    }

    // MARK: Keychain

    /// 32-byte random key persisted in the login keychain.
    static func keychainKey() throws -> SymmetricKey {
        let service = "me.lantern.menubar.faceid"
        let account = "faceprints-key"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        SecItemDelete(query as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: raw,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: "FaceIDStore", code: Int(addStatus))
        }
        return key
    }
}

// MARK: Core ML models

/// ArcFace embedding + passive liveness, loaded from the app bundle.
final class FaceIDModels {
    private(set) var face: MLModel?
    private(set) var liveness: MLModel?
    private var faceInputName: String = "image"
    private var faceOutputName: String = "embedding"
    private var livenessInputName: String = "colorImage"
    private var livenessOutputName: String = "liveness_logit"
    private var livenessCropScale: Double = 1.5

    static func resourceURL(_ name: String) -> URL? {
        // Compiled models land in the bundle root via build.sh.
        Bundle.main.url(forResource: name, withExtension: "mlmodelc")
    }

    func load() {
        if face == nil, let url = Self.resourceURL("ArcFace") {
            face = try? MLModel(contentsOf: url)
            resolveIO(model: face, preferInput: "image", preferOutput: "embedding")
        }
        if liveness == nil, let url = Self.resourceURL("PassiveLiveness_v4_ANE") {
            liveness = try? MLModel(contentsOf: url)
            resolveIO(model: liveness, preferInput: "colorImage", preferOutput: "liveness_logit")
            if let metadata = liveness?.modelDescription.metadata {
                let creator = metadata[.creatorDefinedKey] as? [String: Any]
                if let scale = creator?["crop_scale"] as? Double { livenessCropScale = scale }
                if let thr = creator?["thr_default"] as? Double {
                    // Model metadata may override the built-in threshold.
                    FaceIDConfig_livenessOverride = thr
                }
            }
        }
    }

    /// Models missing from the bundle → verification runs face-match only.
    var livenessAvailable: Bool { liveness != nil }

    private var currentLivenessThreshold: Double {
        FaceIDConfig_livenessOverride ?? FaceIDConfig.livenessLogitThreshold
    }
    private var faceInputSize: CGSize {
        if let desc = face?.modelDescription.inputDescriptionsByName[faceInputName]?.imageConstraint {
            return CGSize(width: desc.pixelsWide, height: desc.pixelsHigh)
        }
        return CGSize(width: 112, height: 112)
    }

    func reset() {
        face = nil
        liveness = nil
        FaceIDConfig_livenessOverride = nil
    }

    private func resolveIO(model: MLModel?, preferInput: String, preferOutput: String) {
        guard let model else { return }
        var inputName = preferInput
        var outputName = preferOutput
        let inputs = model.modelDescription.inputDescriptionsByName
        let outputs = model.modelDescription.outputDescriptionsByName
        if inputs[inputName] == nil, let first = inputs.keys.first { inputName = first }
        if outputs[outputName] == nil, let first = outputs.keys.first { outputName = first }
        if model === face {
            faceInputName = inputName
            faceOutputName = outputName
        } else {
            livenessInputName = inputName
            livenessOutputName = outputName
        }
    }

    // MARK: Embedding

    /// Embedding of a 112×112 RGBA crop; `mirror` flips horizontally first.
    func predictEmbeddingOnly(crop: Data, width: Int, height: Int, mirror: Bool) -> [Float]? {
        guard let face, let buffer = FaceIDModels.rgbaBuffer(from: crop, width: width, height: height) else { return nil }
        let effective = mirror ? FaceIDModels.mirrored(buffer) : buffer
        guard let value = try? MLFeatureValue(pixelBuffer: effective),
              let out = try? face.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                  faceInputName: value,
              ])) else { return nil }
        guard let multi = out.featureValue(for: faceOutputName)?.multiArrayValue else { return nil }
        let count = multi.count
        guard count > 0 else { return nil }
        let ptr = multi.dataPointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: ptr, count: count))
    }

    // MARK: Passive liveness

    /// Liveness logit for the frame containing `faceBox`; nil when unusable.
    func evaluateAntiSpoof(pixelBuffer: CVPixelBuffer, faceBox: CGRect) -> Double? {
        guard let liveness else { return nil }
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let rect = FaceIDMath.livenessCropRect(
            faceBox: faceBox, imageSize: CGSize(width: w, height: h), cropScale: livenessCropScale
        )
        guard let cropped = FaceIDModels.cropScaled(pixelBuffer: pixelBuffer, rect: rect, size: 224) else { return nil }
        guard let value = try? MLFeatureValue(pixelBuffer: cropped),
              let out = try? liveness.prediction(from: MLDictionaryFeatureProvider(dictionary: [
                  livenessInputName: value,
              ])) else { return nil }
        guard let multi = out.featureValue(for: livenessOutputName)?.multiArrayValue, multi.count > 0 else { return nil }
        return multi[multi.count - 1].doubleValue
    }

    func isFaceReal(logit: Double, window: inout [Double]) -> Bool {
        window.append(logit)
        if window.count > FaceIDConfig.livenessWindow { window.removeFirst() }
        let mean = window.reduce(0, +) / Double(window.count)
        return mean > currentLivenessThreshold
    }

    // MARK: Pixel plumbing

    private static func rgbaBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32RGBA, attrs as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        data.withUnsafeBytes { raw in
            for row in 0..<height {
                memcpy(base!.advanced(by: row * stride), raw.baseAddress!.advanced(by: row * width * 4), width * 4)
            }
        }
        return buffer
    }

    private static func mirrored(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var out: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(buffer), nil, &out)
        guard let out else { return buffer }
        CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(out, []) }
        let src = CVPixelBufferGetBaseAddress(buffer)!
        let dst = CVPixelBufferGetBaseAddress(out)!
        let srcStride = CVPixelBufferGetBytesPerRow(buffer)
        let dstStride = CVPixelBufferGetBytesPerRow(out)
        for row in 0..<height {
            let srcRow = src.advanced(by: row * srcStride).assumingMemoryBound(to: UInt8.self)
            let dstRow = dst.advanced(by: row * dstStride).assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                memcpy(dstRow + col * 4, srcRow + (width - 1 - col) * 4, 4)
            }
        }
        return out
    }

    /// Scale the `rect` region of `src` into a black-padded `size`×`size` BGRA buffer.
    static func cropScaled(pixelBuffer src: CVPixelBuffer, rect: CGRect, size: Int) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(src, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(src, .readOnly) }

        var dst: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, size, size, kCVPixelFormatType_32BGRA, nil, &dst)
        guard let dst else { return nil }
        CVPixelBufferLockBaseAddress(dst, [])
        defer { CVPixelBufferUnlockBaseAddress(dst, []) }

        // Fill black first (letterboxes when the crop exceeds the frame).
        let dstBase = CVPixelBufferGetBaseAddress(dst)!
        let dstStride = CVPixelBufferGetBytesPerRow(dst)
        memset(dstBase, 0, dstStride * size)

        let srcW = CVPixelBufferGetWidth(src)
        let srcH = CVPixelBufferGetHeight(src)
        let srcStride = CVPixelBufferGetBytesPerRow(src)
        let x0 = max(0, Int(rect.minX.rounded(.down)))
        let y0 = max(0, Int(rect.minY.rounded(.down)))
        let x1 = min(srcW, Int(rect.maxX.rounded(.up)))
        let y1 = min(srcH, Int(rect.maxY.rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }

        var vImageSrc = vImage_Buffer(data: CVPixelBufferGetBaseAddress(src), height: UInt(srcH), width: UInt(srcW), rowBytes: srcStride)
        var vImageDst = vImage_Buffer(data: dstBase, height: UInt(size), width: UInt(size), rowBytes: dstStride)
        // Dest region inside the padded square.
        let scale = CGFloat(size) / rect.width
        let dx = Int((CGFloat(x0) - rect.minX) * scale)
        let dy = Int((CGFloat(y0) - rect.minY) * scale)
        let dw = Int(CGFloat(x1 - x0) * scale)
        let dh = Int(CGFloat(y1 - y0) * scale)
        var translated = vImage_Buffer(
            data: dstBase.advanced(by: dy * dstStride + dx * 4),
            height: UInt(min(dh, size - dy)),
            width: UInt(min(dw, size - dx)),
            rowBytes: dstStride
        )
        vImageScale_ARGB8888(&vImageSrc, &translated, nil, 0)
        return dst
    }
}

/// Optional model-metadata override for the liveness threshold.
var FaceIDConfig_livenessOverride: Double?
