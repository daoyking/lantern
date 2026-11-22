// StringTable.swift — Type-safe localization framework

import Foundation

/// Supported languages for Lantern
public enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"
    case portuguese = "pt"
    case brazilianPortuguese = "pt-BR"
    case italian = "it"
    case dutch = "nl"
    case turkish = "tr"
    case arabic = "ar"

    public var id: String { rawValue }

    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .russian: return "Русский"
        case .portuguese: return "Português"
        case .brazilianPortuguese: return "Português (Brasil)"
        case .italian: return "Italiano"
        case .dutch: return "Nederlands"
        case .turkish: return "Türkçe"
        case .arabic: return "العربية"
        }
    }
}

/// 应用内语言选择。默认简体中文，也可跟随系统或强制英文。
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return L("language.system", "Follow System")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    private static let preferenceKey = "lantern.appLanguage"

    public static var current: AppLanguage {
        get {
            let stored = UserDefaults.standard.string(forKey: preferenceKey) ?? ""
            return AppLanguage(rawValue: stored) ?? .simplifiedChinese
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey)
            NotificationCenter.default.post(name: .lanternLanguageChanged, object: nil)
        }
    }

    /// "跟随系统" 的具体落点：中文系统（含繁体）走简体中文，其余英文。
    public static var resolved: AppLanguage {
        guard current != .system else {
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
        }
        return current
    }

    /// 显式加载对应 .lproj，避免系统语言与应用内选择不一致。
    public var bundle: Bundle {
        switch self {
        case .system:
            return Bundle.main
        case .simplifiedChinese, .english:
            guard let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { return Bundle.main }
            return bundle
        }
    }
}

extension Notification.Name {
    /// 语言切换后让 SwiftUI 视图整体刷新（菜单是启动时构建的，需重启更新）。
    public static let lanternLanguageChanged = Notification.Name("lanternLanguageChanged")
    /// Island right-click → AppDelegate toggles the main panel.
    public static let lanternTogglePanel = Notification.Name("lanternTogglePanel")
}

/// 统一查表入口：命中 .strings 就用译文，否则用代码里的英文兜底。
/// @inline(__always) 让热路径（每次列表刷新）没有额外开销。
@inline(__always)
public func L(_ key: String, _ englishFallback: String) -> String {
    AppLanguage.resolved.bundle.localizedString(
        forKey: key, value: englishFallback, table: nil
    )
}

/// File-scope indirection: inside `LocalizedString`, the bare name `L` resolves
/// to its own static initializer, so go through this helper to reach the
/// module-level lookup function.
@inline(__always)
private func lookupLocalized(_ key: String, _ fallback: String) -> String {
    L(key, fallback)
}

/// Centralized string table providing compile-time safety
public struct Strings {
    // MARK: - App-level strings

    public static let appName = LocalizedString(key: "app_name", defaultValue: "Lantern", comment: "Application name")
    public static let menuTitle = LocalizedString(key: "menu_title", defaultValue: "Lantern", comment: "Menu bar title")
    public static let quit = LocalizedString(key: "quit", defaultValue: "Quit Lantern", comment: "Quit menu item")

    // MARK: - Panel strings

    public static let features = LocalizedString(key: "features", defaultValue: "Features", comment: "Features tab title")
    public static let tools = LocalizedString(key: "tools", defaultValue: "Tools", comment: "Tools tab title")
    public static let settings = LocalizedString(key: "settings", defaultValue: "Settings", comment: "Settings tab title")

    // MARK: - Onboarding strings

    public static let onboardingWelcome = LocalizedString(
        key: "onboarding_welcome",
        defaultValue: "Welcome to Lantern",
        comment: "Onboarding welcome message"
    )
    public static let onboardingPurpose = LocalizedString(
        key: "onboarding_purpose",
        defaultValue: "Lantern gives you quick access to useful utilities right from your menu bar.",
        comment: "Onboarding purpose description"
    )
    public static let onboardingPermissions = LocalizedString(
        key: "onboarding_permissions",
        defaultValue: "Grant permissions to unlock all features.",
        comment: "Onboarding permissions step"
    )
    public static let onboardingDone = LocalizedString(
        key: "onboarding_done",
        defaultValue: "You're all set!",
        comment: "Onboarding completion"
    )

    // MARK: - Permission strings

    public static let permissionRequired = LocalizedString(
        key: "permission_required",
        defaultValue: "Permission Required",
        comment: "Permission dialog title"
    )
    public static let grantPermission = LocalizedString(
        key: "grant_permission",
        defaultValue: "Grant Permission",
        comment: "Grant permission button"
    )
    public static let grantAndContinue = LocalizedString(
        key: "grant_and_continue",
        defaultValue: "Grant & Continue",
        comment: "Grant and continue button"
    )

    // MARK: - Error strings

    public static let errorTitle = LocalizedString(
        key: "error_title",
        defaultValue: "Error",
        comment: "Error dialog title"
    )
    public static let unknownError = LocalizedString(
        key: "unknown_error",
        defaultValue: "An unexpected error occurred.",
        comment: "Generic error message"
    )

    // MARK: - Feature group labels

    public static let windowsDock = LocalizedString(key: "group_windows_dock", defaultValue: "Windows & Dock", comment: "Feature group label")
    public static let mouseKeyboard = LocalizedString(key: "group_mouse_keyboard", defaultValue: "Mouse & Keyboard", comment: "Feature group label")
    public static let clipboard = LocalizedString(key: "group_clipboard", defaultValue: "Clipboard", comment: "Feature group label")
    public static let sound = LocalizedString(key: "group_sound", defaultValue: "Sound", comment: "Feature group label")
    public static let energyDisplay = LocalizedString(key: "group_energy_display", defaultValue: "Energy Display", comment: "Feature group label")
    public static let toolsGroup = LocalizedString(key: "group_tools", defaultValue: "Tools", comment: "Feature group label")
    public static let dynamicIsland = LocalizedString(key: "group_dynamic_island", defaultValue: "Dynamic Island", comment: "Feature group label")
}

/// Wrapper for localized strings with compile-time safety
public struct LocalizedString {
    public let key: String
    public let defaultValue: String
    public let comment: String?

    public init(key: String, defaultValue: String, comment: String? = nil) {
        self.key = key
        self.defaultValue = defaultValue
        self.comment = comment
    }

    /// Returns the localized string for the current language
    public var value: String {
        lookupLocalized(key, defaultValue)
    }
}

/// Extension to make string interpolation easier
extension LocalizedString {
    /// Convenience initializer for common usage
    public static func L(_ key: String, defaultValue: String, comment: String? = nil) -> LocalizedString {
        LocalizedString(key: key, defaultValue: defaultValue, comment: comment)
    }
}

/// Helper for string formatting with arguments
extension LocalizedString {
    /// Format the string with arguments
    public func formatted(_ args: CVarArg...) -> String {
        let format = value
        return String(format: format, locale: Locale.current, arguments: args)
    }
}
