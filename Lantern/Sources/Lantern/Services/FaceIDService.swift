import AppKit
import AVFoundation
import SwiftUI

// MARK: - FaceID feature service (Sapphire subset)
//
// The feature toggle arms the panel lock: once a face is enrolled, opening
// the menu panel requires a live face match (with a short grace window so
// reopening the panel doesn't re-prompt). Registration and verification run
// in small floating windows owned here.

final class FaceIDService: BaseFeatureService {

    static let shared = FaceIDService(feature: .faceID)

    /// Static so the panel gate can read it without observing.
    static var lastVerifiedAt: Date?

    @Published public private(set) var statusText: String?
    private var controller: FaceIDController?
    private var activeWindow: NSWindow?

    override init(feature: AppFeature) { super.init(feature: feature) }
    deinit { activeWindow?.orderOut(nil) }

    override public func start() throws {
        // The toggle only arms the gate; the camera wakes on demand.
        statusText = nil
    }

    override public func stop() throws {
        controller?.cancel()
        controller = nil
        closeWindow()
        statusText = nil
    }

    var store: FaceIDStore { FaceIDStore() }

    /// Should the next panel open be gated behind face verification?
    static func panelIsLocked() -> Bool {
        guard FeatureCatalog.shared.metadata(for: .faceID).isAction == false else { return false }
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.featureEnabledKey(AppFeature.faceID.rawValue))
        guard enabled else { return false }
        let store = FaceIDStore()
        store.load()
        guard store.hasProfile else { return false }
        if let verified = lastVerifiedAt,
           Date().timeIntervalSince(verified) < FaceIDConfig.verifyGraceSeconds {
            return false
        }
        return true
    }

    // MARK: Verification window

    /// Presents the floating verify window; `onSuccess` fires on a live match.
    func presentVerification(onSuccess: @escaping () -> Void, onFailure: @escaping (String) -> Void = { _ in }) {
        closeWindow()
        let controller = FaceIDController()
        self.controller = controller

        let window = makeWindow(title: L("faceid.verify.title", "Face Verification"))
        let view = FaceIDVerifyView(service: self, controller: controller)
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        activeWindow = window

        controller.beginAuthentication(store: store) { [weak self] in
            self?.closeWindow()
            onSuccess()
        } onFailure: { [weak self] reason in
            self?.statusText = reason
            self?.closeWindow()
            onFailure(reason)
        }
    }

    // MARK: Enrollment window

    func presentEnrollment(onDone: @escaping () -> Void, onError: @escaping (String) -> Void = { _ in }) {
        closeWindow()
        let controller = FaceIDController()
        self.controller = controller

        let window = makeWindow(title: L("faceid.enroll.title", "Enroll Your Face"))
        let view = FaceIDEnrollView(service: self, controller: controller)
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        activeWindow = window

        controller.beginEnrollment(store: store) { [weak self] _ in
            self?.closeWindow()
            onDone()
        } onError: { [weak self] message in
            self?.statusText = message
            self?.closeWindow()
            onError(message)
        }
    }

    func eraseProfile() {
        store.erase()
        FaceIDService.lastVerifiedAt = nil
        statusText = nil
    }

    /// Explicit dismissals from the window close buttons.
    func closeVerification() {
        closeWindow()
    }

    func closeEnrollment() {
        closeWindow()
    }

    // MARK: Window plumbing

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 380),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func closeWindow() {
        controller?.cancel()
        controller = nil
        activeWindow?.orderOut(nil)
        activeWindow = nil
    }
}
