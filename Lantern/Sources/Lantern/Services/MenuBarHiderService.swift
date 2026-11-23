// MenuBarHiderService.swift — menu-bar icon hider (Hidden Bar parity)
//
// Two hiding mechanisms, chosen by OS:
//  - macOS 27+: private MenuBarClientCore "assessment mode" assertion — the
//    framework behind the exam-lockdown feature keeps an explicit allow-list
//    visible and hides every other status item. Resolved at runtime via
//    dlopen + objc_msgSend so a macOS that removes it degrades to "legacy"
//    instead of crashing. Mechanism knowledge ported from consolelabs/hidden
//    (MIT, Dwarves Foundation) — reimplemented here in pure Swift.
//  - macOS ≤ 26: the classic separator trick — a second NSStatusItem whose
//    length inflates past the widest screen, pushing every icon to its left
//    out of the bar. On 27 the OS ejects an inflated separator (#360), so
//    legacy is only the fallback.
//
// Hiding is one assertion/inflation toggle away; feature OFF removes our
// items entirely.

import AppKit

final class MenuBarHiderService: BaseFeatureService {
    static let shared = MenuBarHiderService(feature: .menuBarHider)

    enum EngineKind: String {
        case native      // MenuBarClientCore assertion (macOS 27+)
        case legacy      // separator length inflation (macOS ≤ 26)
        case unavailable // private API gone and legacy is broken → no-op
    }

    @Published private(set) var isCollapsed = false
    @Published var engineKind: EngineKind = .unavailable

    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var assertion: AnyObject?

    /// Test hook: true while a native assertion is held.
    static var hasLiveAssertion: Bool { shared.assertion != nil }

    override init(feature: AppFeature) {
        super.init(feature: feature)
    }
    deinit {
        if let held = assertion { Self.nativeInvalidate(held) }
    }

    // MARK: - Feature lifecycle

    override func start() throws {
        engineKind = Self.nativeVisibilityAvailable() ? .native : .legacy
        buildItems()
        isCollapsed = false
    }

    override func stop() throws {
        expand()
        if let item = separatorItem { NSStatusBar.system.removeStatusItem(item) }
        separatorItem = nil
        if let item = toggleItem { NSStatusBar.system.removeStatusItem(item) }
        toggleItem = nil
        engineKind = .unavailable
    }

    private func buildItems() {
        // Creation order matters: status items flow right→left as they are
        // created, so the arrow is created FIRST (rightmost), the separator
        // second (left of the arrow). The user cmd-drags their own icons
        // between the two; inflating the separator pushes everything left of
        // it out of the bar while the arrow survives at the right edge.
        let arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = arrow.button {
            button.image = NSImage(systemSymbolName: "arrowtriangle.left.and.arrowtriangle.right",
                                   accessibilityDescription: "Lantern menu bar hider")
            button.target = self
            button.action = #selector(toggleClicked)
        }
        toggleItem = arrow
        if engineKind == .legacy {
            let separator = NSStatusBar.system.statusItem(withLength: 20)
            separator.button?.isEnabled = false
            separatorItem = separator
        }
    }

    @objc private func toggleClicked() { toggle() }

    func toggle() { isCollapsed ? expand() : collapse() }

    // MARK: - Collapse / expand

    func collapse() {
        switch engineKind {
        case .native:
            // Keep: system-owned items 0..<64 (clock, Spotlight, control
            // centre…) and our own app's items (the arrow itself). Every
            // other app's status item disappears until the assertion is
            // invalidated or this process exits.
            Self.nativeActivate(allowedSystemItems: Array(0..<64),
                                allowedBundleIdentifiers: [Bundle.main.bundleIdentifier ?? "me.lantern.menubar"]) { [weak self] result in
                guard let self else { return }
                if case .success(let assertion) = result {
                    self.assertion = assertion
                    self.isCollapsed = true
                }
            }
        case .legacy:
            // Cover the widest attached display; macOS caps length at 10,000.
            let widest = NSScreen.screens.map { $0.frame.width }.max() ?? 1_728
            separatorItem?.length = max(500, min(widest * 2, 10_000))
            isCollapsed = true
        case .unavailable:
            break
        }
    }

    func expand() {
        if let assertion {
            Self.nativeInvalidate(assertion)
            self.assertion = nil
        }
        separatorItem?.length = 20
        isCollapsed = false
    }

    // MARK: - MenuBarClientCore runtime binding

    // Selectors spelled out exactly; a renamed API fails the availability
    // gate instead of raising mid-call.
    private static let frameworkPath = "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let configurationClass = "MBAssessmentModeConfiguration"
    private static let assertionClass = "MBAssessmentModeAssertion"

    typealias MsgSend4 = @convention(c) (AnyObject, Selector, AnyObject, AnyObject) -> AnyObject
    typealias MsgSend2 = @convention(c) (AnyObject, Selector) -> AnyObject
    typealias MsgSendVoid = @convention(c) (AnyObject, Selector, AnyObject, @escaping (AnyObject?) -> Void) -> Void

    /// True when the framework, both classes and every selector we call
    /// resolve. Read-only — safe to call from tests.
    static func nativeVisibilityAvailable() -> Bool {
        guard dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) != nil else { return false }
        guard let configuration = NSClassFromString(configurationClass),
              let assertion = NSClassFromString(assertionClass)
        else { return false }
        let initSel = NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
        let activateSel = NSSelectorFromString("activateWithConfiguration:completionHandler:")
        let invalidateSel = NSSelectorFromString("invalidate")
        return configuration.instancesRespond(to: initSel)
            && assertion.instancesRespond(to: activateSel)
            && assertion.instancesRespond(to: invalidateSel)
    }

    private static func msgSend2() -> MsgSend2? {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else { return nil }
        return unsafeBitCast(sym, to: MsgSend2.self)
    }

    private static func msgSend4() -> MsgSend4? {
        guard let sym = dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend") else { return nil }
        return unsafeBitCast(sym, to: MsgSend4.self)
    }

    /// Build the assessment-mode configuration via
    /// `initWithAllowedSystemItems:allowedBundleIdentifiers:`.
    /// Both arrays MUST be NSArray (the framework indexes into them).
    static func makeConfiguration(systemItems: [Int], bundleIDs: [String]) -> AnyObject? {
        guard let msgSend = msgSend2(), let msgSend4 = msgSend4(),
              let configuration = NSClassFromString(configurationClass)
        else { return nil }
        let alloc = msgSend(configuration, NSSelectorFromString("alloc"))
        let items = systemItems.map { NSNumber(value: $0) } as NSArray
        let bundles = bundleIDs as NSArray
        return msgSend4(alloc, NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"), items, bundles)
    }

    /// Activate the assertion. Completion runs on an arbitrary queue with the
    /// opaque assertion handle (keep it; invalidate restores the bar) or nil
    /// on failure.
    static func nativeActivate(allowedSystemItems: [Int],
                               allowedBundleIdentifiers: [String],
                               completion: @escaping (Result<AnyObject, Error>) -> Void) {
        guard let configuration = makeConfiguration(systemItems: allowedSystemItems, bundleIDs: allowedBundleIdentifiers),
              let assertionClass = NSClassFromString(assertionClass),
              let msgSend = msgSend2()
        else {
            completion(.failure(NativeVisibilityError.unavailable))
            return
        }
        let assertion = msgSend(assertionClass, NSSelectorFromString("alloc"))
        let initSel = NSSelectorFromString("init")
        let initFn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"),
                                   to: (@convention(c) (AnyObject, Selector) -> AnyObject).self)
        _ = initFn(assertion, initSel)

        let activateSel = NSSelectorFromString("activateWithConfiguration:completionHandler:")
        let activateFn = unsafeBitCast(dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend"),
                                       to: MsgSendVoid.self)
        activateFn(assertion, activateSel, configuration) { error in
            if error == nil {
                completion(.success(assertion))
            } else {
                completion(.failure(NativeVisibilityError.activation))
            }
        }
    }

    /// Invalidate a held assertion — the bar returns immediately.
    static func nativeInvalidate(_ assertion: AnyObject) {
        guard let msgSend = msgSend2() else { return }
        _ = msgSend(assertion, NSSelectorFromString("invalidate"))
    }

    enum NativeVisibilityError: Error {
        case unavailable
        case activation
    }
}
