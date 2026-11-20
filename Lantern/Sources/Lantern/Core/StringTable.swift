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
        let bundle = Bundle.main
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
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
