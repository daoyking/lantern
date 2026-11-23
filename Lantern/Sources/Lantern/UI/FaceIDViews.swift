import AVFoundation
import SwiftUI

// MARK: Face windows (verification + enrollment)
//
// Build-only views (not in the test compile list): live camera preview via
// AVCaptureVideoPreviewLayer, phase-driven instructions, close button.

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewLayerView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.contentsGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("no storyboard") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> PreviewLayerView {
        let view = PreviewLayerView()
        view.previewLayer.session = session
        DispatchQueue.main.async {
            view.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            view.previewLayer.connection?.isVideoMirrored = true
        }
        return view
    }

    func updateNSView(_ nsView: PreviewLayerView, context: Context) {}
}

/// Face verification window content: camera, hint, live match count.
struct FaceIDVerifyView: View {
    @ObservedObject var service: FaceIDService
    @ObservedObject var controller: FaceIDController

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: controller.session)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack {
                    Spacer()
                    Text(controller.instruction)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(radius: 3)
                        .padding(.bottom, 12)
                }
                if controller.phase == .cameraDenied {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.75))
                        .frame(height: 240)
                        .overlay(
                            Image(systemName: "video.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
            }
            .frame(height: 240)

            if case .authenticating(let matches) = controller.phase {
                HStack(spacing: 8) {
                    ForEach(0..<FaceIDConfig.consecutiveFrames, id: \.self) { i in
                        Circle()
                            .fill(i < matches ? Color.green : Color.white.opacity(0.25))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            if controller.phase == .spoofLocked {
                Label(FaceIDVerifyView.spoofText, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            Button(L("faceid.cancel", "Cancel")) {
                service.closeVerification()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
    }

    static let spoofText = L("faceid.verify.spoof", "That doesn't look like a live face")
}

/// Enrollment window content: pose instruction with per-bucket progress.
struct FaceIDEnrollView: View {
    @ObservedObject var service: FaceIDService
    @ObservedObject var controller: FaceIDController

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CameraPreview(session: controller.session)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack {
                    Spacer()
                    Text(controller.instruction)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(radius: 3)
                        .padding(.bottom, 12)
                }
            }
            .frame(height: 240)

            HStack(spacing: 8) {
                let bucketCount = FaceIDConfig.registrationBuckets.count
                ForEach(0..<bucketCount, id: \.self) { bucket in
                    Circle()
                        .fill(bucketFill(bucket))
                        .frame(width: 10, height: 10)
                }
            }

            Text(L("faceid.enroll.hint", "Follow the prompts — this takes about 10 seconds"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(L("faceid.cancel", "Cancel")) {
                service.closeEnrollment()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 300)
    }

    private func bucketFill(_ bucket: Int) -> Color {
        if case .enrolling(let currentIndex, let captured) = controller.phase {
            if bucket < currentIndex { return .blue }
            if bucket == currentIndex && captured > 0 { return Color.blue.opacity(0.5) }
            return Color.white.opacity(0.25)
        }
        return controller.phase == .succeeded ? .blue : Color.white.opacity(0.25)
    }
}
