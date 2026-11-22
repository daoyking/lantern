import SwiftUI

/// Full-screen black overlay with the 20-20-20 countdown. Shown by
/// EyeBreakService for 20 seconds; tap anywhere or the skip button to
/// dismiss (a skipped break still counts as taken).
struct EyeBreakOverlay: View {
    let endDate: Date
    let onSkip: () -> Void

    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var remaining: Int {
        max(0, Int(endDate.timeIntervalSince(now).rounded(.up)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(L("eyebreak.title", "Eye break"))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text(L("eyebreak.hint", "Look at something ~20 feet away"))
                    .font(.system(size: 17))
                    .foregroundColor(.white.opacity(0.7))
                Text("\(remaining)")
                    .font(.system(size: 72, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Button(action: onSkip) {
                    Text(L("eyebreak.skip", "Skip"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(tick) { now = $0 }
    }
}
