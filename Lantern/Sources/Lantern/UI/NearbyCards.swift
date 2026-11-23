import AppKit
import SwiftUI

// MARK: - Corner cards for Nearby transfers
//
// Inline palette (PanelSurface equivalents) — this file is in the test
// compile list, which does not include MenuPanelView.

enum NearbyCards {

    private static var promptWindow: NSWindow?
    private static var receivedWindow: NSWindow?

    static func dismissAll() {
        promptWindow?.orderOut(nil); promptWindow = nil
        receivedWindow?.orderOut(nil); receivedWindow = nil
    }

    static func present(prompt: NearbyShareService.Prompt,
                        onAccept: (() -> Void)? = nil,
                        onReject: (() -> Void)? = nil) {
        show(window: &promptWindow, content: NearbyPromptCard(
            prompt: prompt,
            onAccept: {
                promptWindow?.orderOut(nil); promptWindow = nil
                onAccept?()
            },
            onReject: {
                promptWindow?.orderOut(nil); promptWindow = nil
                onReject?()
            }
        ))
    }

    static func presentReceived(from peerName: String, preview: String) {
        show(window: &receivedWindow, content: NearbyReceivedCard(from: peerName, preview: preview))
    }

    private static func show<V: View>(window: inout NSWindow?, content: V,
                                      autoDismissAfter: TimeInterval? = nil,
                                      onDismiss: (() -> Void)? = nil) {
        window?.orderOut(nil); window = nil
        let width: CGFloat = 300, height: CGFloat = 132
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.maxX - width - 16,
            y: screen.frame.maxY - height - 16,
            width: width,
            height: height
        )
        let panel = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        panel.orderFrontRegardless()
        window = panel

        if let autoDismissAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter) { [weak window] in
                window?.orderOut(nil)
                window = nil
                onDismiss?()
            }
        }
    }
}

/// Incoming-transfer prompt with Accept/Reject. Auto-rejects after 20s
/// if untouched (the service cancels the pending offer).
struct NearbyPromptCard: View {
    let prompt: NearbyShareService.Prompt
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "personalhotspot")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cyan)
                Text(prompt.peerName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            Text(prompt.preview.isEmpty
                 ? L("nearby.preview.empty", "Text snippet")
                 : prompt.preview)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
            HStack(spacing: 10) {
                Button(L("nearby.accept", "Accept"), action: onAccept)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
                Button(L("nearby.reject", "Reject"), action: onReject)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Spacer()
            }
        }
        .padding(14)
        .frame(width: 300, height: 132, alignment: .leading)
        .background(Color(white: 0.15).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Shown when a snippet lands (it is already in the clipboard history).
struct NearbyReceivedCard: View {
    let from: String
    let preview: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                Text(String(format: L("nearby.received", "Received from %@"), from))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            Text(preview.isEmpty ? L("nearby.preview.empty", "Text snippet") : preview)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(3)
        }
        .padding(14)
        .frame(width: 300, height: 132, alignment: .leading)
        .background(Color(white: 0.15).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
