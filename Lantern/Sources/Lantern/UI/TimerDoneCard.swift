import SwiftUI

/// Small dark corner card shown when a quick timer expires. Auto-dismissed
/// by QuickTimerService after 8 seconds; tap to dismiss sooner.
struct TimerDoneCard: View {
    let minutes: Int
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(L("timerDone.title", "⏰ Time's up"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(String(format: L("timerDone.hint", "%d minute timer finished"), minutes))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(width: 264, height: 108)
        // Matches PanelSurface.cardBackground without importing the panel file.
        .background(Color(white: 0.15).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onTapGesture { onDismiss() }
    }
}
