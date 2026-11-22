// DynamicIslandView.swift — the island's face: notch-shaped, live slots
//
// Rendered inside the service's floating panel. Idle state is a plain
// black slab matching the hardware notch — no content, no shadow, so it
// blends in as "the original notch". Tapping expands the slab to show
// every enabled slot (time, date, weather, volume, cpu, memory, battery,
// network) with values; each slot is individually toggleable from the
// island tab via plain UserDefaults keys, and the service widens the
// panel to match, so nothing clips.

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
    @AppStorage(DefaultsKey.islandShowTime.rawValue) private var showTime = true
    @AppStorage(DefaultsKey.islandShowDate.rawValue) private var showDate = false
    @AppStorage(DefaultsKey.islandShowWeather.rawValue) private var showWeather = false
    @AppStorage(DefaultsKey.islandShowMusic.rawValue) private var showMusic = false
    @AppStorage(DefaultsKey.islandShowNextEvent.rawValue) private var showNextEvent = false
    // Timer slot follows the quickTimer feature toggle, not a dedicated key.
    @AppStorage(DefaultsKey.featureEnabledKey("quickTimer")) private var showTimer = false
    @AppStorage(DefaultsKey.islandShowVolume.rawValue) private var showVolume = false
    @AppStorage(DefaultsKey.islandShowCPU.rawValue) private var showCPU = true
    @AppStorage(DefaultsKey.islandShowMemory.rawValue) private var showMemory = true
    @AppStorage(DefaultsKey.islandShowBattery.rawValue) private var showBattery = true
    @AppStorage(DefaultsKey.islandShowNetwork.rawValue) private var showNetwork = true

    private enum IslandSlot { case time, date, weather, music, nextEvent, timer, volume, cpu, memory, battery, network }

    init(service: DynamicIslandService) {
        self.service = service
        // AppDelegate creates the controller at registration time; tests
        // may run without it, so fall back to a throwaway instance.
        _music = ObservedObject(wrappedValue: MusicControllerService.shared
            ?? MusicControllerService(feature: .musicPlayPause))
        _calendar = ObservedObject(wrappedValue: CalendarService.shared)
        _timer = ObservedObject(wrappedValue: QuickTimerService.shared)
    }

    /// Fixed priority order — enabled slots surface left to right.
    private var enabledSlots: [IslandSlot] {
        var slots: [IslandSlot] = []
        if showTime { slots.append(.time) }
        if showDate { slots.append(.date) }
        if showWeather, service.weatherTempC != nil { slots.append(.weather) }
        if showMusic, music.trackTitle != nil { slots.append(.music) }
        if showNextEvent, calendar.nextEvent != nil { slots.append(.nextEvent) }
        if showTimer, timer.endAt != nil { slots.append(.timer) }
        if showVolume, service.volumePercent >= 0 { slots.append(.volume) }
        if showCPU { slots.append(.cpu) }
        if showMemory { slots.append(.memory) }
        if showBattery, service.batteryPercent >= 0 { slots.append(.battery) }
        if showNetwork { slots.append(.network) }
        return slots
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.92))
                // The real notch casts no shadow — only the expanded state
                // floats above the menu bar and gets one.
                .shadow(color: service.expanded ? .black.opacity(0.35) : .clear,
                        radius: 6, y: 2)

            if service.expanded {
                expandedContent
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { service.toggleExpanded() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.expanded)
    }

    // MARK: - Expanded: every enabled slot with its value, below the notch

    private var expandedContent: some View {
        HStack(spacing: 14) {
            ForEach(Array(enabledSlots.enumerated()), id: \.offset) { _, slot in
                expandedSlot(slot)
            }
        }
        // The hardware notch hides the top band at the screen's horizontal
        // centre — park the content just below it.
        .padding(.top, DynamicIslandService.notchHeight + 6)
    }

    @ViewBuilder
    private func expandedSlot(_ slot: IslandSlot) -> some View {
        switch slot {
        case .time:
            VStack(spacing: 2) {
                Text(Self.timeFormatter.string(from: service.now))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Text(Self.dateFormatter.string(from: service.now))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.55))
            }
        case .date:
            VStack(spacing: 2) {
                Text(Self.dateFormatter.string(from: service.now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                Text(L("island.date", "Date"))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.55))
            }
        case .weather:
            if let temp = service.weatherTempC {
                let code = service.weatherCode ?? 3
                let cond = IslandWeatherService.condition(for: code)
                metric(icon: IslandWeatherService.symbol(for: code),
                       color: .cyan,
                       label: L("island.weather", "Weather"),
                       value: "\(L(cond.key, cond.english)) \(Int(temp))°")
            }
        case .music:
            // Wide slot: track title over artist, transport buttons below.
            if let title = music.trackTitle {
                VStack(spacing: 3) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 96)
                    if let artist = music.trackArtist, !artist.isEmpty {
                        Text(artist)
                            .font(.system(size: 8))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 96)
                    }
                    HStack(spacing: 14) {
                        Button(action: music.previousTrack) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        Button(action: music.playPause) {
                            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        Button(action: music.nextTrack) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        case .nextEvent:
            // Narrow slot: start time above, event title below.
            if let reading = calendar.nextEvent {
                VStack(spacing: 2) {
                    Text(Self.eventTimeFormatter.string(from: reading.start))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(reading.title)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 96)
                }
            }
        case .timer:
            if timer.endAt != nil {
                VStack(spacing: 2) {
                    Text(timer.caption)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(L("island.timer", "Timer"))
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        case .volume:
            VStack(spacing: 3) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 11))
                    .foregroundColor(service.volumeMuted ? .orange : .white)
                volumeBar(level: service.volumeMuted
                            ? 0
                            : min(max(service.volumePercent / 100, 0), 1))
                Text("\(Int(service.volumePercent))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        case .cpu:
            metric(icon: "cpu.fill", color: cpuColor,
                   label: L("island.cpu", "CPU"),
                   value: "\(Int(service.cpuPercent))%")
        case .memory:
            metric(icon: "memorychip.fill", color: .purple,
                   label: L("island.memory", "Memory"),
                   value: "\(Int(service.memoryPercent))%")
        case .battery:
            metric(icon: "bolt.fill", color: .green,
                   label: L("island.battery", "Battery"),
                   value: "\(Int(service.batteryPercent))%")
        case .network:
            metric(icon: "arrow.down", color: .teal,
                   label: L("island.network", "Net"),
                   value: String(format: "%.0fKB/s", service.networkDownKBps))
        }
    }

    private func metric(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.55))
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

    /// Thin horizontal gauge whose filled width tracks the volume level.
    private func volumeBar(level: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white.opacity(0.25))
            .frame(width: 36, height: 3)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(service.volumeMuted ? Color.orange : Color.white)
                    .frame(width: max(2, 36 * level), height: 3)
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

    // Next-event start time in the slot's narrow caption (HH:mm; the
    // all-day marker "•" comes from CalendarService.timeCaption).
    private static let eventTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
