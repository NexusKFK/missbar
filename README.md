<div align="center">
    <img src="Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="160" height="160" alt="missbar app icon">
    <h1>missbar</h1>
    <p><strong>Menu bar management for macOS 26 and 27</strong></p>
</div>

missbar hides and shows the items in your macOS menu bar. It splits the menu bar into
visible, hidden, and always-hidden sections that you reveal by click, hover, scroll, or
hotkey. It also customizes the menu bar's appearance, saves layout profiles, and searches
your items.

## Lineage

missbar is a fork of a fork, and both ancestors deserve the credit:

| | |
|---|---|
| [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | The original. Last code commit June 2025; its `macos-26` branch stopped in September 2025 without a stable release. |
| [teddychan/ice-2](https://github.com/teddychan/ice-2) | The maintained fork that did the real work of restoring menu bar management on macOS 26 and then macOS 27. |
| **missbar** (this repo) | A personal rebuild of ice-2 under its own name and bundle identifier, built and installed without an Apple Developer ID. |

This fork exists because the last *official* Ice release (0.11.12, October 2024) no longer
manages anything on macOS 27 — the app launches and every icon stays visible. Essentially all
of the engineering that fixes that belongs to the two projects above.

## What this fork changes

Almost nothing about how the app works. The changes are identity and distribution:

- **Renamed** to missbar, with its own bundle identifier `com.nexuskfk.missbar`, so it can be
  installed beside Ice or Ice 2 without either one clobbering the other's preferences, control
  items or saved state.
- **Unhooked from Ice 2's update feed.** `SUFeedURL` pointed at ice-2's appcast, which would
  have made missbar download an Ice 2 release and replace itself with it. It now points at an
  empty appcast in this repo, so "Check for Updates…" simply reports the app is up to date.
- **Issues no Homebrew cask token.** missbar is not distributed through Homebrew. Inherited
  unchanged, its uninstaller would have run `brew uninstall --cask --force ice-2`, which is not
  bundle-scoped and would have quit and deleted a *different* app installed beside it.
- **Own release identity.** `Constants.releaseBundleIdentifier` is how the app recognizes its
  own other build, so that applying a menu bar spacing offset — which quits and relaunches every
  app that owns a menu bar item — skips itself. Left on Ice 2's identifier, missbar would have
  treated itself as a third-party app.
- **Builds unsigned in CI**, replacing the upstream release pipeline, which needs an Apple
  Developer ID certificate and notarization credentials this fork does not have.
- **Disables library validation** (`App/missbar.entitlements`). The hardened runtime only lets a
  process load libraries sharing its Team ID, and an ad-hoc signature has none — so dyld refused
  to load the app's own bundled Sparkle.framework and it died at launch. Worth knowing that
  `codesign --verify --deep --strict` passes on such a build: it checks that each component is
  validly signed, not that the Team IDs agree. CI now loads the binary to catch this.

Upstream's own release infrastructure (DragonKit conformance workflow, signed release workflow,
Homebrew tap wiring, internal planning docs) is removed rather than left in place to fail.

## Requirements

- macOS 26 (Tahoe) or macOS 27.
- An Apple Silicon Mac. The app is built for arm64 only.
- Accessibility and Screen Recording permissions. missbar asks for both on first launch and
  cannot manage menu bar items without them.

## Install

There is no signed release. Download `missbar.zip` from
[Actions → Build missbar](https://github.com/NexusKFK/missbar/actions/workflows/build.yml) —
pick the latest successful run and take the artifact — or from
[Releases](https://github.com/NexusKFK/missbar/releases) if one has been tagged.

### Recommended: install with a local signing identity

```sh
git clone https://github.com/NexusKFK/missbar.git && cd missbar
./scripts/create-signing-identity.sh   # once per machine
./scripts/install-local.sh             # downloads, re-signs, installs, launches
```

Then grant **Accessibility** and **Screen Recording** when missbar asks. You only have to do
that once — including across updates, which is the reason for the first script. Re-run
`./scripts/install-local.sh` to move to a newer build.

<details>
<summary>Why re-signing matters</summary>

macOS pins a permission to the app's *designated requirement*. For an ad-hoc signed build that
requirement is a bare hash of the code:

```
designated => cdhash H"500f28937ed4b40dae09dc89ed968af5d0e06a15"
```

It changes with every build, so each update looks like a different program and silently loses
its Accessibility and Screen Recording grants — the toggle stays switched on in System Settings
while the running app is not the one it refers to.

`create-signing-identity.sh` makes a self-signed certificate that never leaves your Mac, and
`install-local.sh` re-signs each download with it. The requirement then becomes:

```
designated => identifier "com.nexuskfk.missbar" and certificate root = H"04c1d506…"
```

which is identical for every build signed with that certificate, so the grants carry over.

This is not an Apple Developer ID. It does nothing for Gatekeeper and nothing on anyone else's
machine; it exists only so this Mac can recognize successive builds as the same program. Keep
`~/.local/share/missbar-signing` backed up — losing the key means granting everything again.

</details>

### Plain install

```sh
unzip missbar.zip
mv missbar.app /Applications/
# The build is ad-hoc signed, not Developer ID-signed and notarized, so Gatekeeper
# quarantines the download. Clear the attribute or macOS will refuse to open it:
xattr -dr com.apple.quarantine /Applications/missbar.app
open /Applications/missbar.app
```

Then grant **Accessibility** and **Screen Recording** in System Settings ▸ Privacy & Security.

> [!IMPORTANT]
> Installed this way, both permissions have to be granted again after every update, and the
> stale entry has to be removed first (`tccutil reset Accessibility com.nexuskfk.missbar`).
> `scripts/install-local.sh` above exists to avoid this.

### Uninstall

Quit missbar, delete `/Applications/missbar.app`, then:

```sh
rm -rf ~/Library/Application\ Support/com.nexuskfk.missbar \
       ~/Library/Caches/com.nexuskfk.missbar \
       ~/Library/HTTPStorages/com.nexuskfk.missbar \
       ~/Library/Preferences/com.nexuskfk.missbar.plist \
       ~/Library/Saved\ Application\ State/com.nexuskfk.missbar.savedState
```

## macOS 27: what works and what does not

macOS 27 changed how the menu bar is assembled, and the window-based approach every version of
Ice used cannot see individual icons there any more. On macOS 27 the app uses a different
backend: Accessibility to discover app bundles and system items, and runtime-loaded
`MenuBarClientCore` assertions to hide them. macOS 26 keeps the original backend and the full
feature set.

What this means in practice on macOS 27:

- **Sections are per app, not per icon.** Every menu bar icon belonging to one app shares a
  section. You choose a section per app in Layout.
- **Hidden items reveal in the menu bar itself**, not in a separate floating bar.
- **Three features are unavailable:** the separate floating bar, searching for a single menu bar
  icon, and temporarily revealing one icon. Their controls and hotkeys are disabled, but your
  saved bindings and macOS 26 preferences are left intact.
- **Some system items cannot be assigned independently:** the clock, Control Center, and
  SystemUIServer extras. They appear separately under "Managed by macOS".
- **Command-drag in the menu bar** is still how you change the physical order of items.
- The hiding mechanism rests on a private API behind runtime capability checks. It works today;
  a future macOS release can take it away again.

`docs/testing/macos27-integration.md` documents the backend in detail.

## Features

### Menu bar item management

- [x] Hide menu bar items
- [x] "Always-hidden" menu bar section
- [x] Show hidden menu bar items when hovering over the menu bar
- [x] Show hidden menu bar items when an empty area in the menu bar is clicked
- [x] Show hidden menu bar items by scrolling or swiping in the menu bar
- [x] Automatically rehide menu bar items
- [x] Hide application menus when they overlap with shown menu bar items
- [x] Drag and drop interface to arrange menu bar items
- [x] Display hidden menu bar items in a separate bar (macOS 26 only)
- [x] Search menu bar items (macOS 26 only)
- [x] Menu bar item spacing (BETA)
- [x] Profiles for menu bar layout
- [x] Individual spacer items
- [x] Show menu bar items when trigger conditions are met

### Menu bar appearance

- [x] Menu bar tint (solid and gradient)
- [x] Menu bar shadow
- [x] Menu bar border
- [x] Custom menu bar shapes (rounded and/or split)
- [x] Different settings for light/dark mode
- [x] Remove background behind menu bar
- [x] Rounded screen corners

### Hotkeys

- [x] Toggle individual menu bar sections
- [x] Show the search panel (macOS 26 only)
- [x] Enable/disable the floating bar (macOS 26 only)
- [x] Show/hide section divider icons
- [x] Toggle application menus
- [x] Enable/disable auto rehide
- [x] Temporarily show individual menu bar items (macOS 26 only)

### Other

- [x] Launch at login
- [x] Back up & restore settings to a folder you choose
- [ ] Automatic updates — deliberately disabled in this fork; see [What this fork changes](#what-this-fork-changes)

## Menu bar sections

missbar divides the menu bar into three sections — **Visible**, **Hidden**, and
**Always-Hidden** — and installs one control item per enabled section as a divider between
them. macOS adds new items to the left end of the menu bar, which is where the always-hidden
section lives.

- **Click** missbar's icon to toggle its section.
- **Option-click** it to toggle the always-hidden section.
- **Control-click** it to open missbar's menu. Turn this off under
  **Settings ▸ Advanced ▸ Other**.
- **Command-drag** an item along the menu bar to move it into another section.

The always-hidden section is enabled by default. Turn it off, or change how the dividers look,
under **Settings ▸ Advanced ▸ Menu Bar Sections**.

## Building from source

Requires Xcode 26 or later (a full Xcode install — Command Line Tools alone cannot build an
`.xcodeproj` app target).

```sh
git clone https://github.com/NexusKFK/missbar.git
cd missbar
xcodebuild build -project Ice.xcodeproj -scheme Ice -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""
```

The app lands at `build/Build/Products/Release/missbar.app`.

If you have no local Xcode, push to this repo instead and let
`.github/workflows/build.yml` build it on a GitHub-hosted runner.

The Debug configuration builds as `com.nexuskfk.missbar.debug`, displayed as **missbar Debug**,
so it runs beside an installed missbar without touching its preferences.

## Tests

```sh
xcodebuild test -project Ice.xcodeproj -scheme Ice -destination 'platform=macOS,arch=arm64'
```

Also run in CI by `.github/workflows/tests.yml`.

## Credits

- [Jordan Baird](https://github.com/jordanbaird) — the original
  [Ice](https://github.com/jordanbaird/Ice).
- [Teddy Chan](https://github.com/teddychan) — [Ice 2](https://github.com/teddychan/ice-2),
  including the macOS 26 and macOS 27 backends this fork depends on entirely.

## License

GPL-3.0, inherited from Ice and Ice 2. See [LICENSE](LICENSE).
