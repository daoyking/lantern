import SwiftUI

/// Corner card shown when a focus session completes. Tap to dismiss.
struct FocusDoneCard: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(L("focusDone.title", "🎯 Focus session done"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(L("focusDone.hint", "25 minutes of focus — nice work"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(width: 264, height: 108)
        .background(Color(white: 0.15).opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onTapGesture { onDismiss() }
    }
}
