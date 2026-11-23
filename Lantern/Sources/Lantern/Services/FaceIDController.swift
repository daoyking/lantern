import AVFoundation
import CoreGraphics
import Vision

// MARK: Face capture + enrollment + authentication controller
//
// Drives the front camera through AVCaptureSession, finds faces with Vision,
// aligns them to the 112×112 ArcFace template, and runs the two flows:
// enrollment (3 pose buckets × 4 frames) and authentication (streak of
// matches gated by the passive liveness model).

final class FaceIDController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    enum Phase: Equatable {
        case idle
        case cameraDenied
        case enrolling(bucket: Int, captured: Int)
        case authenticating(matches: Int)
        case spoofLocked
        case mismatchTimeout
        case succeeded
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lantern.faceid.capture")
    private let output = AVCaptureVideoDataOutput()
    private let models = FaceIDModels()

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var instruction: String = ""

    /// Optional preview surface; set before startCamera.
    var previewSink: ((CVPixelBuffer) -> Void)?

    private var enrollBucketIndex = 0
    private var enrollCaptured = 0
    private var enrollPrints: [[Float]] = []
    private var enrollStore: FaceIDStore?
    private var enrollFinish: ((FaceProfile) -> Void)?
    private var enrollError: ((String) -> Void)?

    private var authStore: FaceIDStore?
    private var authMatchStreak = 0
    private var authStartedAt = Date()
    private var authSucceeded: (() -> Void)?
    private var authFailed: ((String) -> Void)?
    private var livenessWindow: [Double] = []
    private var spoofSince: Date?
    private var processing = false
    private var authEmbeddingPending: [Float]?

    // MARK: Camera

    func startCamera() {
        models.load()
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.beginSession() : self?.setDenied()
                }
            }
            return
        default:
            setDenied()
            return
        }
        beginSession()
    }

    private func setDenied() {
        phase = .cameraDenied
        instruction = "camera denied"
    }

    private func beginSession() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.session.inputs.isEmpty else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .vga640x480
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.setDenied() }
                return
            }
            self.session.addInput(input)
            self.output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            self.output.setSampleBufferDelegate(self, queue: self.queue)
            guard self.session.canAddOutput(self.output) else {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.setDenied() }
                return
            }
            self.session.addOutput(self.output)
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func stopCamera() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async {
                self.phase = .idle
                self.instruction = ""
            }
        }
    }

    // MARK: Enrollment

    /// Starts enrollment; `completion` gets the stored profile on success.
    func beginEnrollment(store: FaceIDStore, completion: @escaping (FaceProfile) -> Void, onError: @escaping (String) -> Void) {
        enrollBucketIndex = 0
        enrollCaptured = 0
        enrollPrints.removeAll()
        enrollStore = store
        enrollFinish = completion
        enrollError = onError
        phase = .enrolling(bucket: 0, captured: 0)
        updateEnrollInstruction()
        startCamera()
    }

    private func updateEnrollInstruction() {
        let bucket = FaceIDConfig.registrationBuckets[min(enrollBucketIndex, 3)]
        let name = bucketName(bucket.name)
        instruction = "\(name) \(enrollCaptured)/\(FaceIDConfig.framesPerBucket)"
        phase = .enrolling(bucket: enrollBucketIndex, captured: enrollCaptured)
    }

    private func bucketName(_ key: String) -> String {
        switch key {
        case "center": return L("faceid.pose.center", "Look straight ahead")
        case "center2": return L("faceid.pose.center", "Look straight ahead")
        case "left": return L("faceid.pose.left", "Turn slightly left")
        case "right": return L("faceid.pose.right", "Turn slightly right")
        default: return key
        }
    }

    // MARK: Authentication

    func beginAuthentication(store: FaceIDStore, onSuccess: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        authStore = store
        authSucceeded = onSuccess
        authFailed = onFailure
        authMatchStreak = 0
        authStartedAt = Date()
        livenessWindow.removeAll()
        spoofSince = nil
        authEmbeddingPending = nil
        phase = .authenticating(matches: 0)
        instruction = L("faceid.verify.hint", "Look at the camera")
        startCamera()
    }

    func cancel() {
        enrollFinish = nil
        enrollError = nil
        authSucceeded = nil
        authFailed = nil
        stopCamera()
    }

    // MARK: Frame pipeline

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !processing, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processing = true
        defer { processing = false }

        if let sink = previewSink { sink(pixelBuffer) }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            guard let self else { return }
            guard let observation = (request.results as? [VNFaceObservation])?.first,
                  let landmarks = observation.landmarks else {
                DispatchQueue.main.async { self.handleNoFace() }
                return
            }
            DispatchQueue.main.async {
                self.handleFace(observation: observation, landmarks: landmarks, pixelBuffer: pixelBuffer)
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }

    private func handleNoFace() {
        guard phase != .succeeded else { return }
        authMatchStreak = 0
        if case .authenticating = phase {
            instruction = L("faceid.verify.hint", "Look at the camera")
            phase = .authenticating(matches: 0)
            if Date().timeIntervalSince(authStartedAt) > FaceIDConfig.mismatchTimeoutSeconds {
                finishAuthFailure("timeout")
            }
        }
    }

    private func handleFace(observation: VNFaceObservation, landmarks: VNFaceLandmarks2D, pixelBuffer: CVPixelBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let box = normalizedToPixels(observation.boundingBox, width: width, height: height)

        switch phase {
        case .enrolling:
            runEnrollFrame(observation: observation, landmarks: landmarks, pixelBuffer: pixelBuffer, box: box, size: CGSize(width: width, height: height))
        case .authenticating:
            runAuthFrame(observation: observation, landmarks: landmarks, pixelBuffer: pixelBuffer, box: box, size: CGSize(width: width, height: height))
        default:
            break
        }
    }

    // MARK: Enrollment frame

    private func runEnrollFrame(observation: VNFaceObservation, landmarks: VNFaceLandmarks2D, pixelBuffer: CVPixelBuffer, box: CGRect, size: CGSize) {
        guard enrollBucketIndex < FaceIDConfig.registrationBuckets.count else { return }
        let bucket = FaceIDConfig.registrationBuckets[enrollBucketIndex]
        guard bucketMatches(bucket: bucket, observation: observation) else { return }
        guard box.width >= FaceIDConfig.minFacePixels else { return }

        guard let crop = alignedFaceCrop(pixelBuffer: pixelBuffer, observation: observation, landmarks: landmarks, size: size) else { return }
        guard let emb = embedFace(crop: crop) else { return }
        enrollPrints.append(emb)
        enrollCaptured += 1

        if enrollCaptured >= FaceIDConfig.framesPerBucket {
            enrollBucketIndex += 1
            enrollCaptured = 0
        }
        if enrollBucketIndex >= FaceIDConfig.registrationBuckets.count {
            finalizeEnrollment()
        } else {
            updateEnrollInstruction()
        }
    }

    private func bucketMatches(bucket: (name: String, yaw: ClosedRange<Float>), observation: VNFaceObservation) -> Bool {
        let yaw = Float(observation.yaw ?? 0)
        return bucket.yaw.contains(yaw)
    }

    private func finalizeEnrollment() {
        guard let store = enrollStore else { return }
        guard enrollPrints.count >= 2 else {
            enrollError?(L("faceid.error.frames", "Not enough usable frames — better lighting helps"))
            resetEnrollment()
            return
        }
        let profile = FaceProfile(
            id: UUID(),
            name: L("faceid.default.name", "My face"),
            createdAt: Date(),
            prints: enrollPrints.map { FaceIDMath.l2Normalize($0) },
            centroid: FaceIDMath.l2Normalize(
                enrollPrints.reduce(into: [Float](repeating: 0, count: enrollPrints[0].count)) { acc, v in
                    for i in acc.indices { acc[i] += v[i] }
                }
            )
        )
        do {
            try store.save(profile)
            let stored = store.profile
            phase = .succeeded
            instruction = ""
            enrollFinish?(stored!)
        } catch {
            enrollError?(L("faceid.error.save", "Could not store the face profile"))
        }
        resetEnrollment()
    }

    private func resetEnrollment() {
        enrollStore = nil
        enrollFinish = nil
        enrollError = nil
        enrollPrints.removeAll()
        enrollBucketIndex = 0
        enrollCaptured = 0
        stopCamera()
    }

    // MARK: Auth frame

    private func runAuthFrame(observation: VNFaceObservation, landmarks: VNFaceLandmarks2D, pixelBuffer: CVPixelBuffer, box: CGRect, size: CGSize) {
        guard box.width >= FaceIDConfig.minFacePixels else { return }

        // Liveness first: photos and screens must not pass.
        if models.livenessAvailable {
            let logit = models.evaluateAntiSpoof(pixelBuffer: pixelBuffer, faceBox: box)
            if let logit {
                let real = models.isFaceReal(logit: logit, window: &livenessWindow)
                if !real {
                    if spoofSince == nil { spoofSince = Date() }
                    instruction = L("faceid.verify.spoof", "That doesn't look like a live face")
                    if let since = spoofSince, Date().timeIntervalSince(since) > FaceIDConfig.spoofSustainedSeconds {
                        finishAuthFailure("spoof")
                    }
                    return
                }
                spoofSince = nil
            }
        }

        guard let crop = alignedFaceCrop(pixelBuffer: pixelBuffer, observation: observation, landmarks: landmarks, size: size) else { return }
        guard let embedding = embedFace(crop: crop) else { return }
        guard let store = authStore else { return }

        let score = store.score(embedding: embedding)
        if score >= FaceIDConfig.identityThreshold {
            authMatchStreak += 1
            instruction = "\(Int(score * 100))%"
            if authMatchStreak >= FaceIDConfig.consecutiveFrames {
                finishAuthSuccess()
            } else {
                phase = .authenticating(matches: authMatchStreak)
            }
        } else {
            authMatchStreak = 0
            phase = .authenticating(matches: 0)
            instruction = L("faceid.verify.retry", "Face not recognized")
            if Date().timeIntervalSince(authStartedAt) > FaceIDConfig.mismatchTimeoutSeconds {
                finishAuthFailure("mismatch")
            }
        }
    }

    private func finishAuthSuccess() {
        phase = .succeeded
        instruction = L("faceid.verify.ok", "Verified")
        FaceIDService.lastVerifiedAt = Date()
        let callback = authSucceeded
        authSucceeded = nil
        authFailed = nil
        stopCamera()
        callback?()
    }

    private func finishAuthFailure(_ reason: String) {
        phase = reason == "spoof" ? .spoofLocked : .mismatchTimeout
        instruction = reason == "spoof"
            ? L("faceid.verify.spoof.locked", "Verification stopped")
            : L("faceid.verify.timeout", "Could not verify you")
        let callback = authFailed
        authFailed = nil
        authSucceeded = nil
        stopCamera()
        callback?(reason)
    }

    // MARK: Face geometry

    private func normalizedToPixels(_ box: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        // Vision boxes are normalized bottom-left; pixel space is top-left.
        CGRect(
            x: box.minX * width,
            y: (1 - box.maxY) * height,
            width: box.width * width,
            height: box.height * height
        )
    }

    private func landmarkPixel(_ point: CGPoint, box: CGRect) -> CGPoint {
        let x = box.minX + point.x * box.width
        let y = (1 - (box.minY + point.y * box.height)) / 1
        return CGPoint(x: x, y: y)
    }

    /// Standard ArcFace canonical five points on a 112×112 canvas.
    static let canonical112: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]

    private func facePoints(landmarks: VNFaceLandmarks2D, box: CGRect) -> [CGPoint]? {
        guard let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let nose = landmarks.nose, let outerLips = landmarks.outerLips else {
            return nil
        }
        func centroid(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
            var x: CGFloat = 0, y: CGFloat = 0
            for i in 0..<region.pointCount {
                let p = region.normalizedPoints[i]
                x += p.x; y += p.y
            }
            guard region.pointCount > 0 else { return .zero }
            return CGPoint(x: x / CGFloat(region.pointCount), y: y / CGFloat(region.pointCount))
        }
        let eyeL = centroid(leftEye)
        let eyeR = centroid(rightEye)
        let noseTip = centroid(nose)
        // Mouth corners = extremes along x of the outer lip contour.
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -minX
        var mouthL = CGPoint.zero, mouthR = CGPoint.zero
        for p in outerLips.normalizedPoints {
            if p.x < minX { minX = p.x; mouthL = p }
            if p.x > maxX { maxX = p.x; mouthR = p }
        }
        // Convert landmark (bbox-relative, Vision bottom-left) into pixel space.
        func pixel(_ p: CGPoint) -> CGPoint {
            let inBox = CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
            return CGPoint(x: inBox.x, y: 1 - inBox.y)
        }
        // box here is already in normalized Vision space; caller passes raw box.
        return [pixel(eyeL), pixel(eyeR), pixel(noseTip), pixel(mouthL), pixel(mouthR)]
    }

    /// Warp the face into the 112×112 RGBA template via a similarity transform
    /// fitted to the five canonical points.
    private func alignedFaceCrop(pixelBuffer: CVPixelBuffer, observation: VNFaceObservation, landmarks: VNFaceLandmarks2D, size: CGSize) -> Data? {
        let width = Int(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int(CVPixelBufferGetHeight(pixelBuffer))
        let rawBox = observation.boundingBox
        guard let points = facePoints(landmarks: landmarks, box: rawBox) else { return nil }

        // Scale factor between raw normalized image coords and pixels.
        let sx = CGFloat(width), sy = CGFloat(height)
        let src = points.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        guard let transform = FaceIDController.similarityTransform(from: src, to: FaceIDController.canonical112) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(pixelBuffer)!
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytesPerPixel = 4

        var out = [UInt8](repeating: 0, count: 112 * 112 * 4)
        for y in 0..<112 {
            for x in 0..<112 {
                let dst = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let srcPt = apply(transform, to: dst)
                let xi = Int(srcPt.x.rounded(.down))
                let yi = Int(srcPt.y.rounded(.down))
                guard xi >= 0, xi < width, yi >= 0, yi < height else { continue }
                let srcOffset = yi * stride + xi * bytesPerPixel
                let srcBytes = base.advanced(by: srcOffset).assumingMemoryBound(to: UInt8.self)
                // BGRA pixel buffer → RGBA output.
                let outOffset = (y * 112 + x) * 4
                out[outOffset] = srcBytes[2]     // R
                out[outOffset + 1] = srcBytes[1] // G
                out[outOffset + 2] = srcBytes[0] // B
                out[outOffset + 3] = srcBytes[3] // A
            }
        }
        return Data(out)
    }

    /// Least-squares similarity (scale + rotation + translation), Umeyama-style.
    static func similarityTransform(from src: [CGPoint], to dst: [CGPoint]) -> (scale: CGFloat, cos: CGFloat, sin: CGFloat, tx: CGFloat, ty: CGFloat)? {
        guard src.count == dst.count, src.count >= 2 else { return nil }
        let n = CGFloat(src.count)
        let srcMean = CGPoint(x: src.map(\.x).reduce(0, +) / n, y: src.map(\.y).reduce(0, +) / n)
        let dstMean = CGPoint(x: dst.map(\.x).reduce(0, +) / n, y: dst.map(\.y).reduce(0, +) / n)

        var numerator = 0.0, srcVar = 0.0
        for i in 0..<src.count {
            let dx = src[i].x - srcMean.x, dy = src[i].y - srcMean.y
            numerator += Double(dx * (dst[i].x - dstMean.x) + dy * (dst[i].y - dstMean.y))
            srcVar += Double(dx * dx + dy * dy)
        }
        guard srcVar > 1e-8 else { return nil }
        let scale = CGFloat(numerator / srcVar)
        guard scale.isFinite, abs(scale) > 1e-6 else { return nil }

        var cosSum = 0.0, sinSum = 0.0
        for i in 0..<src.count {
            let dx = src[i].x - srcMean.x, dy = src[i].y - srcMean.y
            cosSum += Double(dx * (dst[i].x - dstMean.x) + dy * (dst[i].y - dstMean.y))
            sinSum += Double(dx * (dst[i].y - dstMean.y) - dy * (dst[i].x - dstMean.x))
        }
        let norm = sqrt(cosSum * cosSum + sinSum * sinSum)
        guard norm > 1e-8 else { return nil }
        let cosT = CGFloat(cosSum / norm)
        let sinT = CGFloat(sinSum / norm)

        let tx = dstMean.x - scale * (cosT * srcMean.x - sinT * srcMean.y)
        let ty = dstMean.y - scale * (sinT * srcMean.x + cosT * srcMean.y)
        return (scale, cosT, sinT, tx, ty)
    }

    private func apply(_ transform: (scale: CGFloat, cos: CGFloat, sin: CGFloat, tx: CGFloat, ty: CGFloat), to p: CGPoint) -> CGPoint {
        CGPoint(
            x: transform.scale * (transform.cos * p.x - transform.sin * p.y) + transform.tx,
            y: transform.scale * (transform.sin * p.x + transform.cos * p.y) + transform.ty
        )
    }

    // MARK: Embedding path

    private func embedFace(crop: Data) -> [Float]? {
        models.load()
        let original = models.predictEmbeddingOnly(crop: crop, width: 112, height: 112, mirror: false)
        let flipped = models.predictEmbeddingOnly(crop: crop, width: 112, height: 112, mirror: true)
        guard original != nil || flipped != nil else { return nil }
        return FaceIDMath.ttaEmbedding(original: original ?? [], flipped: flipped ?? [])
    }
}
