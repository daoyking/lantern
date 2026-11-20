// LanternTests.swift — Regression + edge-case coverage for the menu panel logic.
//
// These tests specifically target the bugs found during manual QA:
//  - toggles for catalog-only features (no registered service) were dead
//  - rapid repeated toggles must stay consistent
//  - every feature group must render content, none may be empty
//  - enable state must round-trip through UserDefaults

import XCTest
@testable import Lantern

final class LanternTests: XCTestCase {

    private let runtime = FeatureRuntime.shared

    override func setUp() {
        super.setUp()
        // Start from a clean slate for every test — clear all feature prefs.
        for feature in AppFeature.allCases {
            UserDefaults.standard.removeObject(
                forKey: DefaultsKey.featureEnabledKey(feature.rawValue)
            )
        }
        // Disable everything that might be left active from a prior test.
        for feature in Array(runtime.activeFeatures) {
            runtime.stop(feature)
        }
    }

    override func tearDown() {
        for feature in Array(runtime.activeFeatures) {
            runtime.stop(feature)
        }
        super.tearDown()
    }

    // MARK: - Toggle correctness (the reported bug)

    /// pasteAsPlainText / syncClipboardAcrossDevices have NO registered service.
    /// Before the fix, start()/stop() early-returned on a missing service so the
    /// switch never changed state. Every catalog feature must now toggle.
    func testEveryFeatureCanToggleWithoutAService() {
        for feature in AppFeature.allCases {
            XCTAssertFalse(runtime.activeFeatures.contains(feature),
                           "\(feature.rawValue) should start inactive")

            runtime.toggle(feature)
            XCTAssertTrue(runtime.activeFeatures.contains(feature),
                          "toggle ON failed for \(feature.rawValue) (dead switch regression)")

            runtime.toggle(feature)
            XCTAssertFalse(runtime.activeFeatures.contains(feature),
                           "toggle OFF failed for \(feature.rawValue)")
        }
    }

    /// Specifically pin the three Clipboard features from the screenshot.
    func testClipboardGroupSwitchesAreLive() {
        let clipboardFeatures: [AppFeature] = [
            .clipboardHistory, .pasteAsPlainText, .syncClipboardAcrossDevices
        ]
        for feature in clipboardFeatures {
            runtime.toggle(feature)
            XCTAssertTrue(runtime.activeFeatures.contains(feature),
                          "\(feature.rawValue) switch is dead")
        }
        XCTAssertEqual(runtime.activeFeatures.count, 3)
    }

    // MARK: - Extreme / stress cases

    /// Rapid alternating toggles must always converge to the parity of the
    /// click count — no stuck state, no duplicated insert/remove.
    func testRapidRepeatedToggleStaysConsistent() {
        let feature: AppFeature = .pasteAsPlainText
        for i in 1...101 { // odd count → ends enabled
            runtime.toggle(feature)
            XCTAssertEqual(
                runtime.activeFeatures.contains(feature),
                i % 2 == 1,
                "state diverged after \(i) rapid toggles"
            )
        }
    }

    /// Calling start/stop twice must be idempotent (no crash, no double state).
    func testRepeatedStartAndStopAreIdempotent() {
        let feature: AppFeature = .syncClipboardAcrossDevices
        runtime.start(feature)
        runtime.start(feature)
        XCTAssertTrue(runtime.activeFeatures.contains(feature))
        runtime.stop(feature)
        runtime.stop(feature)
        XCTAssertFalse(runtime.activeFeatures.contains(feature))
    }

    // MARK: - Group / layout invariants

    /// A group rendered with zero features shows the empty placeholder, but
    /// with the current catalog every group should actually have content.
    func testNoFeatureGroupIsEmpty() {
        for group in FeatureGroup.allCases {
            let features = runtime.orderedFeatures(in: group)
            XCTAssertFalse(features.isEmpty, "group \(group.rawValue) is empty")
        }
    }

    /// Every feature is classified into exactly one group, and appears in it.
    func testEveryFeatureAppearsInItsOwnGroup() {
        for feature in AppFeature.allCases {
            let groupFeatures = runtime.orderedFeatures(in: feature.group)
            XCTAssertTrue(groupFeatures.contains(feature),
                          "\(feature.rawValue) missing from group \(feature.group.rawValue)")
        }
    }

    /// Group ordering is stable (no duplicates, deterministic priority sort).
    func testOrderedFeaturesAreUniqueAndStable() {
        for group in FeatureGroup.allCases {
            let first = runtime.orderedFeatures(in: group)
            let second = runtime.orderedFeatures(in: group)
            XCTAssertEqual(first, second, "unstable ordering in \(group.rawValue)")
            XCTAssertEqual(Set(first).count, first.count, "duplicate features in \(group.rawValue)")
        }
    }

    /// Short labels must be single words short enough for the 360pt tab bar.
    func testShortLabelsAreCompact() {
        for group in FeatureGroup.allCases {
            XCTAssertLessThanOrEqual(
                group.shortLabel.count, 10,
                "\(group.rawValue) short label too long: \(group.shortLabel)"
            )
        }
    }

    // MARK: - Persistence round-trip

    /// Toggling must persist immediately so state survives a relaunch.
    func testTogglePersistsToUserDefaults() {
        let feature: AppFeature = .pasteAsPlainText
        let key = DefaultsKey.featureEnabledKey(feature.rawValue)

        runtime.toggle(feature)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key),
                      "enabled state was not persisted")

        runtime.toggle(feature)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key),
                       "disabled state was not persisted")
    }

    /// syncFromDefaults must restore persisted enabled features.
    func testSyncFromDefaultsRestoresState() {
        let feature: AppFeature = .syncClipboardAcrossDevices
        UserDefaults.standard.set(true, forKey: DefaultsKey.featureEnabledKey(feature.rawValue))

        runtime.syncFromDefaults()
        XCTAssertTrue(runtime.activeFeatures.contains(feature),
                      "persisted enabled feature was not restored")
    }

    // MARK: - Metadata edge cases

    /// PermissionType.none must be treated as always granted (the earlier
    /// ambiguity with Optional.none could mark a feature unavailable).
    func testNonePermissionIsAlwaysAvailable() {
        XCTAssertTrue(Permissions.shared.isGranted(.none))
        XCTAssertTrue(FeatureCatalog.shared.isAvailable(.syncClipboardAcrossDevices),
                      "a .none-permission feature should not be gated")
    }

    /// Unknown/default metadata must not crash or gate a feature.
    func testCatalogMetadataLookupAlwaysReturnsAValue() {
        for feature in AppFeature.allCases {
            let meta = FeatureCatalog.shared.metadata(for: feature)
            XCTAssertGreaterThanOrEqual(meta.displayPriority, 0)
        }
    }
}
