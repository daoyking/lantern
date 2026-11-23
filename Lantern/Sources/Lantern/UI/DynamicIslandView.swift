// DynamicIslandView.swift — the island's face, Sapphire-style
//
// Idle state is a plain black slab matching the hardware notch — no
// content, no shadow, so it blends in as "the original notch".
//
// Expanded state follows Sapphire's notch-hub language: one glass card
// (ultraThinMaterial under a black veil, continuous 20pt corners) with a
// **hero zone** right below the notch — the music player when something
// plays, otherwise a large clock — and a scrolling chip row of live
// metrics beneath. Chips are the Sapphire widget-card primitive: small
// translucent rounded rectangles, icon + value, spring animations.

import SwiftUI

struct DynamicIslandFace: View {
    @ObservedObject var service: DynamicIslandService
    // Owns the music controller reactively — without observing it, the
    // face would only refresh track changes on the 1s metric tick.
    @ObservedObject var music: MusicControllerService
    // Calendar next-event slot: observed so a fresh reading repaints it.
    @ObservedObject var calendar: CalendarService
    // Quick timer: observed so the countdown repaints on the 1s metric tick.
    @ObservedObject var timer: QuickTimerService
    @ObservedObject var gemini: GeminiLiveService
    @ObservedObject var focus: FocusService
    @AppStorage(DefaultsKey.islandShowTime.rawValue) private var showTime = true
    @AppStorage(DefaultsKey.islandShowDate.rawValue) private var showDate = false
    @AppStorage(DefaultsKey.islandShowWeather.rawValue) private var showWeather = false
    @AppStorage(DefaultsKey.islandShowMusic.rawValue) private var showMusic = false
    @AppStorage(DefaultsKey.islandShowNextEvent.rawValue) private var showNextEvent = false
    @AppStorage(DefaultsKey.islandShowGemini.rawValue) private var showGemini = false
    // Timer slot follows the quickTimer feature toggle, not a dedicated key.
    @AppStorage(DefaultsKey.featureEnabledKey("quickTimer")) private var showTimer = false
    // Focus slot likewise follows the focusMode feature toggle.
    @AppStorage(DefaultsKey.featureEnabledKey("focusMode")) private var showFocus = false
    @AppStorage(DefaultsKey.islandShowVolume.rawValue) private var showVolume = false
    @AppStorage(DefaultsKey.islandShowCPU.rawValue) private var showCPU = true
    @AppStorage(DefaultsKey.islandShowMemory.rawValue) private var showMemory = true
    @AppStorage(DefaultsKey.islandShowBattery.rawValue) private var showBattery = true
    @AppStorage(DefaultsKey.islandShowNetwork.rawValue) private var showNetwork = true

    private enum IslandSlot { case nextEvent, timer, focus, gemini, volume, cpu, memory, battery, network }

    init(service: DynamicIslandService) {
        self.service = service
        // AppDelegate creates the controller at registration time; tests
        // may run without it, so fall back to a throwaway instance.
        _music = ObservedObject(wrappedValue: MusicControllerService.shared
            ?? MusicControllerService(feature: .musicPlayPause))
        _calendar = ObservedObject(wrappedValue: CalendarService.shared)
        _timer = ObservedObject(wrappedValue: QuickTimerService.shared)
        _focus = ObservedObject(wrappedValue: FocusService.shared)
        _gemini = ObservedObject(wrappedValue: GeminiLiveService.shared)
    }

    /// First line of the live/last Gemini reply for the island chip.
    private var replySnippet: String {
        let raw = gemini.streamingReply.isEmpty ? (gemini.lastReply ?? "") : gemini.streamingReply
        let line = raw.split(separator: "\n").first.map(String.init) ?? raw
        return line.isEmpty ? L("island.gemini", "Gemini") : line
    }

    /// Music owns the hero zone when it plays and the island shows it.
    private var musicHeroActive: Bool {
        showMusic && music.trackTitle != nil
    }

    private var enabledSlots: [IslandSlot] {
        var slots: [IslandSlot] = []
        // Time / date / weather live on the IDLE wing, not in the expanded
        // hub (user request) — the hero clock already covers time+date there.
        if showNextEvent, calendar.nextEvent != nil { slots.append(.nextEvent) }
        if showTimer, timer.endAt != nil { slots.append(.timer) }
        if showFocus, focus.endAt != nil { slots.append(.focus) }
        if showGemini, gemini.isOpen { slots.append(.gemini) }
        if showVolume, service.volumePercent >= 0 { slots.append(.volume) }
        if showCPU { slots.append(.cpu) }
        if showMemory { slots.append(.memory) }
        if showBattery, service.batteryPercent >= 0 { slots.append(.battery) }
        if showNetwork { slots.append(.network) }
        return slots
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Compact = solid black (the notch illusion). Expanded = one
            // Sapphire glass card with continuous corners.
            ZStack {
                if service.expanded {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                RoundedRectangle(cornerRadius: service.expanded ? 20 : 0, style: .continuous)
                    .fill(Color.black.opacity(service.expanded ? 0.45 : 0.92))
            }
            .overlay(
                RoundedRectangle(cornerRadius: service.expanded ? 20 : 0, style: .continuous)
                    .stroke(service.expanded ? Color.white.opacity(0.12) : .clear, lineWidth: 1)
            )
            // The real notch casts no shadow — only the expanded state
            // floats above the menu bar and gets one.
            .shadow(color: service.expanded ? .black.opacity(0.35) : .clear,
                    radius: 6, y: 2)

            if service.expanded {
                expandedContent
            } else {
                idleWing
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { service.toggleExpanded() }
        .contextMenu {
            Button(L("island.openPanel", "Open Lantern Panel")) {
                NotificationCenter.default.post(name: .lanternTogglePanel, object: nil)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.expanded)
    }

    // MARK: - Idle: the clock wing (time / date / weather beside the notch)

    /// Right wing of the idle slab: time, date and weather in one row.
    /// The slab (460pt) is centred, the hardware notch occupies the middle
    /// 184pt, so the wing area right of it hosts this row.
    private var idleWing: some View {
        HStack(spacing: 7) {
            if showTime {
                Text(Self.timeFormatter.string(from: service.now))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            if showDate {
                Text(Self.dateFormatter.string(from: service.now))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            if showWeather, let temp = service.weatherTempC {
                HStack(spacing: 2) {
                    if let code = service.weatherCode {
                        Image(systemName: IslandWeatherService.symbol(for: code))
                            .font(.system(size: 9))
                            .foregroundColor(.cyan)
                    }
                    Text("\(Int(temp))°")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        // Park the row in the right wing: notch region (184pt) sits centred,
        // so the row hugs the right edge with a small margin.
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 14)
        .padding(.leading, 184 + 8)
        .contentShape(Rectangle())
        .onTapGesture { service.toggleExpanded() }
        .animation(.snappy(duration: 0.3), value: service.weatherTempC)
    }

    // MARK: - Expanded: hero + chip row (Sapphire notch-hub layout)

    private var expandedContent: some View {
        VStack(spacing: 10) {
            hero
            chipRow
        }
        // The hardware notch hides the top band at the screen's horizontal
        // centre — park the content just below it.
        .padding(.top, DynamicIslandService.notchHeight + 4)
        .padding(.bottom, 10)
        .padding(.horizontal, 14)
    }

    /// Hero zone: music player when playing, otherwise the big clock.
    @ViewBuilder
    private var hero: some View {
        if musicHeroActive {
            musicHero
        } else {
            clockHero
        }
    }

    private var musicHero: some View {
        VStack(spacing: 5) {
            Text(music.trackTitle ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if let artist = music.trackArtist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 22) {
                Button(action: music.previousTrack) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                Button(action: music.playPause) {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: music.isPlaying)
                Button(action: music.nextTrack) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var clockHero: some View {
        VStack(spacing: 2) {
            Text(Self.timeFormatter.string(from: service.now))
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundColor(.white)
            Text(Self.dateFormatter.string(from: service.now))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    /// Live metric chips — the Sapphire widget-card primitive.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(enabledSlots.enumerated()), id: \.offset) { _, slot in
                    chip(slot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func chip(_ slot: IslandSlot) -> some View {
        HStack(spacing: 5) {
            chipIcon(slot)
            chipValue(slot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    @ViewBuilder
    private func chipIcon(_ slot: IslandSlot) -> some View {
        switch slot {
        case .nextEvent:
            Image(systemName: "calendar")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        case .timer:
            Image(systemName: "timer")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .focus:
            Image(systemName: "scope")
                .font(.system(size: 10))
                .foregroundColor(.purple)
        case .gemini:
            Image(systemName: gemini.voiceMode ? "waveform" : "sparkles")
                .font(.system(size: 10))
                .foregroundColor(.cyan)
        case .volume:
            Image(systemName: volumeIcon)
                .font(.system(size: 10))
                .foregroundColor(service.volumeMuted ? .orange : .white.opacity(0.85))
        case .cpu:
            Image(systemName: "cpu.fill")
                .font(.system(size: 10))
                .foregroundColor(cpuColor)
        case .memory:
            Image(systemName: "memorychip.fill")
                .font(.system(size: 10))
                .foregroundColor(.purple)
        case .battery:
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
        case .network:
            Image(systemName: "arrow.down")
                .font(.system(size: 10))
                .foregroundColor(.teal)
        }
    }

    @ViewBuilder
    private func chipValue(_ slot: IslandSlot) -> some View {
        switch slot {
        case .nextEvent:
            if let reading = calendar.nextEvent {
                Text("\(Self.eventTimeFormatter.string(from: reading.start)) \(reading.title)")
                    .chipText()
            }
        case .timer:
            Text(timer.caption)
                .chipText()
        case .focus:
            Text("\(L("island.focus", "Focus")) \(focus.caption)")
                .chipText()
        case .gemini:
            Text(replySnippet)
                .chipText()
        case .volume:
            Text("\(Int(service.volumePercent))%")
                .chipText()
        case .cpu:
            Text("\(Int(service.cpuPercent))%")
                .chipText()
        case .memory:
            Text("\(Int(service.memoryPercent))%")
                .chipText()
        case .battery:
            Text("\(Int(service.batteryPercent))%")
                .chipText()
        case .network:
            Text(String(format: "%.0fKB/s", service.networkDownKBps))
                .chipText()
        }
    }

    // MARK: - Helpers

    private var cpuColor: Color {
        switch service.cpuPercent {
        case ..<50: return .green
        case ..<80: return .orange
        default: return .red
        }
    }

    /// Speaker icon tracks the live master-volume level (waves grow with it).
    private var volumeIcon: String {
        if service.volumeMuted || service.volumePercent < 1 { return "speaker.slash.fill" }
        switch service.volumePercent {
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // Cached formatters — the face re-renders every second via service.now.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MdEEE") // e.g. 12/22 周一
        return f
    }()

    // Next-event start time in the chip (HH:mm; the all-day marker "•"
    // comes from CalendarService.timeCaption).
    private static let eventTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

extension Text {
    /// Shared chip typography: compact, monospaced digits for live values.
    func chipText() -> Text {
        self.font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
    }
}
