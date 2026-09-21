# Releasing missbar

missbar has no Apple Developer ID, so there is no signed, notarized release pipeline. What
upstream Ice 2 does with Developer ID certificates, notarization and a Homebrew tap, this fork
replaces with a single unsigned build in `.github/workflows/build.yml`.

## Every build

Pushing to `main` (or running the workflow by hand from the Actions tab) builds the Release
configuration on a `macos-26` runner, ad-hoc signs it, and uploads `missbar.zip` as a workflow
artifact. That artifact is the normal way to get a build.

## Tagged releases

Pushing a `vX.Y.Z` tag runs the same job and additionally attaches `missbar.zip` to a GitHub
Release. No secrets are required — the workflow uses the automatic `github.token`.

```sh
git tag v2.16.0
git push origin v2.16.0
```

Bump `MARKETING_VERSION` (and, if you want it to move, `CURRENT_PROJECT_VERSION`) in
`Ice.xcodeproj` first. Nothing enforces that the tag and the version agree; upstream's release
workflow had a guard for that, and it went with the rest of the signing pipeline.

## What the app does about updates

Nothing automatic, deliberately.

`SUFeedURL` in `App/Info.plist` points at `docs/appcast.xml` in this repo, which is a valid
appcast with no items. "Check for Updates…" therefore reports that the app is up to date
instead of erroring, and missbar can never download a release of a different app.

This matters because of what it replaced: the feed was inherited pointing at ice-2's appcast,
which would have made missbar update itself into Ice 2 at the first background check.

`SUPublicEDKey` was removed along with it — it was Ice 2's release keypair, and Sparkle will not
install an update it cannot verify against a key we do not hold. Publishing real updates through
Sparkle would mean generating an EdDSA keypair, putting the public half back in `Info.plist`,
and signing each release. Installing by hand from the Releases page avoids all of it.

## Installing what you built

The build is ad-hoc signed, so Gatekeeper quarantines the download and macOS treats every build
as a different program. See [Install](../README.md#install) in the README — in particular, both
Accessibility and Screen Recording have to be granted again after replacing the app.
