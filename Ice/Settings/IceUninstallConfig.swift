//
//  IceUninstallConfig.swift
//  Ice
//

import DragonKit
import Foundation

/// App-owned Uninstall configuration for missbar, rendered by DragonKit's
/// ``UninstallSettingsPane`` and performed by ``DragonUninstaller``.
///
/// Only missbar's own content lives here — the confirmation layout and the teardown are owned
/// by DragonKit. missbar's settings live in its `UserDefaults` domain (`Defaults.store` is
/// `.standard`), which the shared teardown wipes from `bundleID` along with the matching
/// preference plist and saved application state, so there are no extra suites. missbar keeps no
/// separate user data either — its settings *are* its data, always removed — so there is no
/// optional "also delete data" toggle, unlike ClipMenu.
///
/// `extraCleanupPaths` covers the per-bundle-id folders the shared teardown can't know about:
/// the `Caches` and `HTTPStorages` folders macOS creates for the app's own network traffic
/// (Sparkle's appcast fetches), plus `Application Support`. missbar writes nothing to
/// `Application Support` today, but it is listed so the in-app uninstall, the manual `rm -rf`
/// in `README.md`, and the Homebrew cask's `zap trash:` all remove the same five paths —
/// keeping those three from drifting is the point, and removing an absent folder is a no-op.
enum IceUninstallConfig {
    /// The bundle id Homebrew installed: the fallback for the running bundle's id below, and the
    /// gate the cask token is issued against — deliberately not both at once, see
    /// ``homebrewCask(forBundleID:)``.
    ///
    /// Aliases ``Constants/releaseBundleIdentifier`` rather than repeating the literal: three
    /// places now ask "is this the installed release, or the isolated debug build?", and a
    /// second copy of that id is exactly the kind of literal that drifts.
    private static let releaseBundleID = Constants.releaseBundleIdentifier

    /// Always `nil`: missbar is not distributed through Homebrew.
    ///
    /// Ice 2 ships as the cask `ice-2` and issues that token here so its teardown can clear
    /// brew's receipt, which otherwise keeps claiming the cask is installed after the app has
    /// deleted itself. missbar has no cask and so no receipt to clear.
    ///
    /// The token is not merely unnecessary here — it is unsafe. `brew uninstall --cask` is not
    /// bundle-scoped: it quits and deletes whatever app brew's receipt points at. Inherited
    /// unchanged, missbar's uninstaller would run `brew uninstall --cask --force ice-2` and
    /// delete a *different* app that happens to be installed beside it.
    static func homebrewCask(forBundleID _: String?) -> String? {
        nil
    }

    @MainActor
    static var config: UninstallConfig {
        // The running bundle's id, so a debug build (com.nexuskfk.missbar.debug) cleans its OWN
        // domain/state/caches and never the installed release's.
        let bundleID = Bundle.main.bundleIdentifier ?? releaseBundleID
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return UninstallConfig(
            appName: Constants.displayName,
            bundleID: bundleID,
            // Resolved here, not keyed: `UninstallConfig` is built fresh each time the pane
            // renders and the kit shows these strings as-is (its own doc comment says to
            // localize them in the app), so `L(_:)` reads the language selected right now.
            checklistItems: [
                L("app.uninstall.item.app"),
                L("app.uninstall.item.settings"),
                L("app.uninstall.item.state"),
                L("app.uninstall.item.caches"),
            ],
            extraCleanupPaths: [
                library.appending(path: "Application Support/\(bundleID)"),
                library.appending(path: "Caches/\(bundleID)"),
                library.appending(path: "HTTPStorages/\(bundleID)"),
            ],
            // The *raw* identifier, never `bundleID` above: that one falls back to the release id
            // so a build which can't state its own still cleans a sensible domain, which is
            // harmless there and authorises a delete of the installed release here.
            homebrewCask: homebrewCask(forBundleID: Bundle.main.bundleIdentifier)
        )
    }
}
