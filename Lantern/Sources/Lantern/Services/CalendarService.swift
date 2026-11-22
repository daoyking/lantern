import Foundation
import EventKit

/// Read-only calendar service: surfaces the next upcoming event on the
/// island (Sapphire-style "what's next"). Zero-dependency: EventKit only,
/// no private frameworks.
///
/// Authorization is user-driven: the island slot flips the service on,
/// which requests calendar access once (TCC prompt). If the user denies,
/// the slot simply stays hidden — no nagging, no crash.
final class CalendarService: NSObject, ObservableObject {

    static let shared = CalendarService()

    /// Next upcoming calendar event within the look-ahead window.
    struct Reading: Equatable {
        let title: String
        let start: Date
        let allDay: Bool
    }

    @Published public private(set) var nextEvent: Reading?
    @Published public private(set) var authorized: Bool = false

    private let store = EKEventStore()
    private var running = false
    private var refreshTimer: Timer?
    /// Re-query this often; EKEventStoreChanged notifications also trigger.
    private let refreshInterval: TimeInterval = 15 * 60
    /// How far ahead to look for the "next" event.
    static let lookAheadDays: Int = 7

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        refreshTimer?.invalidate()
    }

    // MARK: - Lifecycle (driven by the island slot)

    public func setRunning(_ active: Bool) {
        guard active != running else { return }
        running = active
        if active {
            requestAccessThenRefresh()
            refreshTimer = Timer.scheduledTimer(
                withTimeInterval: refreshInterval, repeats: true
            ) { [weak self] _ in self?.refresh() }
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            nextEvent = nil
        }
    }

    private func requestAccessThenRefresh() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized:
            authorized = true
            refresh()
        case .notDetermined:
            // macOS 14+ request API; read-only usage.
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.authorized = granted
                        if granted { self?.refresh() }
                    }
                }
            } else {
                store.requestAccess(to: .event) { [weak self] granted, _ in
                    DispatchQueue.main.async {
                        self?.authorized = granted
                        if granted { self?.refresh() }
                    }
                }
            }
        default:
            // Denied / restricted: stay silent, slot hides itself.
            authorized = false
            nextEvent = nil
        }
    }

    @objc private func storeChanged() {
        guard running, authorized else { return }
        refresh()
    }

    public func refresh() {
        guard running, authorized else { return }
        let now = Date()
        guard let end = Calendar.current.date(
            byAdding: .day, value: Self.lookAheadDays, to: now
        ) else { return }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        nextEvent = Self.nextEvent(from: events, after: now, calendar: Calendar.current)
    }

    // MARK: - Pure selection logic (tested)

    /// Earliest event after `now` (same-day events that already started
    /// count too); all-day events sort by their start date and surface
    /// with `allDay: true`.
    ///
    /// Note: EKEvent.isDeclined does not exist on macOS (iOS-only API),
    /// so declined invitations are not filtered here.
    public static func nextEvent(
        from events: [EKEvent], after now: Date, calendar: Calendar
    ) -> Reading? {
        let upcoming = events
            .filter { $0.startDate >= now || calendar.isDate($0.startDate, inSameDayAs: now) }
            .sorted { $0.startDate < $1.startDate }
        guard let first = upcoming.first else { return nil }
        return Reading(
            title: first.title ?? "—",
            start: first.startDate,
            allDay: first.isAllDay
        )
    }

    /// Compact island caption: all-day → "全天"-style key; else HH:mm.
    public static func timeCaption(for reading: Reading, calendar: Calendar) -> String {
        if reading.allDay { return "•" }
        let comps = calendar.dateComponents([.hour, .minute], from: reading.start)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
