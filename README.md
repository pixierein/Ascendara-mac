<div align="center">
  <img width="128" height="128" src="./MacPort/Source/Ascendara/Resources/AppIcon.png" alt="Ascendara icon">
  <h1>Ascendara for macOS</h1>
  <p>An unofficial native macOS port of Ascendara</p>
  <p>
    <img src="https://img.shields.io/badge/version-1.1-blue" alt="Version 1.1">
    <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
    <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  </p>
</div>

## About

Ascendara for macOS is an unofficial native port for finding, downloading, organizing, and launching games. It is based on the [original Ascendara project](https://github.com/Ascendara/ascendara) by tagoWorks, with its own SwiftUI interface, macOS helpers, and release versions. Ascend account features are not available in this port; use the [official launcher](https://www.ascendara.app/thank-you) for Ascend.

Quick links: [Build](#build-and-install) · [Project structure](#project-structure) · [TODO](MacPort/TODO.md) · [Original project](https://github.com/Ascendara/ascendara)

## Features

- **Downloads:** Manage direct downloads with live progress, pause, resume, queue suspension, prioritization, bulk retry, and history cleanup. Single-stream and parallel transfers check free space before starting when their size is known, and continue checking while downloading. Provider windows handle hosts that require a countdown, sign-in, or CAPTCHA before handing the file back to the download worker.
- **Extraction:** Space-saving extraction validates an archive and records its read order, then reclaims compressed blocks after their final use. The native library handles supported ZIP, tar, and 7z/RAR files; a bundled 7-Zip helper extends reclamation to split volumes and encryption/compression variants it can decode, including encrypted 7z headers and AES-encrypted ZIP. The validation pass writes sparse output files without duplicating extracted contents. This mode consumes the archive; an interrupted extraction requires downloading every consumed volume again. Undecodable files and drives without block reclamation retain normal extraction with an expanded-size check. Preferences can place extracted games on another drive. Torrent extraction checks space while preserving files used for seeding.
- **Game information:** Browse artwork, screenshots, requirements, ratings, and release details. Catalog sizes are download sizes, not installed sizes.
- **Local index:** Search a cached game catalog, refresh it from the public JSON endpoint, or import an `ascendara_games.json` file. The original app is not required.
- **Library:** Import and launch native or Windows games, track playtime, manage favorites and collections, and back up saves locally. Measured install sizes are saved per game and shown in library cards, game options, and game details. Managed games can be moved or reinstalled into a chosen folder, with independent choices for retaining playtime and achievements. Replacement files are staged before switching the library, with rollback and restart recovery.
- **Mac compatibility:** Use Highball to set up a Wine engine and run supported Windows games on Apple Silicon.
- **Big Picture and Retro:** Browse with a controller-friendly layout and keep console games in a separate library. Automatic setup installs Dolphin, PCSX2, Flycast, xemu, RetroArch, DuckStation, RPCS3, PPSSPP, and melonDS from their published macOS packages and configures supported RetroArch cores. RPCS3 selects its Apple Silicon or Intel package. Nintendo DS has a built-in melonDS preset. Other emulators can still be selected manually.
- **Languages and themes:** The 12 bundled upstream languages use their original i18next JSON dictionaries, with English fallback for missing native-port copy. The complete upstream language catalogue is available for importing additional i18next dictionaries. Create, preview, import, and export custom color palettes in Preferences.
- **Updates and notifications:** Compare installed game versions with the active index. Enable automatic updates per managed game; installation waits until the game stops and retains history and achievements. App updates are detected from optional `macVersion` or `appVersion` index metadata, with `appDownloadURL` for a download-page link. Notifications have a persistent in-app history, category preferences, and optional macOS alerts.
- **Links:** Open supported `ascendara://` links in the app.

## What's new in 1.1

- Reclaim consumed archive blocks across split volumes and additional 7-Zip encryption/compression variants, with validation and recovery for the whole archive set.
- Set up DuckStation, RPCS3, PPSSPP, and melonDS automatically.
- Use the unofficial Mac port's own version, 1.1, in the app, installer, and API headers.

## Build and install

Requires macOS 14 or later and a Swift 6 toolchain. Install Xcode Command Line Tools, then run from the repository root:

```sh
./MacPort/Scripts/Build.sh
```

The app is written to `MacPort/Build/Ascendara.app`. Copy it to Applications if you want to install it locally. To make a DMG:

```sh
./MacPort/Scripts/BuildDmg.sh
```

Local builds use ad hoc signing. A public release needs a Developer ID certificate and notarization. `ASCENDARA_MAC_SIGN_IDENTITY` selects the certificate. `BuildDmg.sh --notarize` also needs `ASCENDARA_MAC_NOTARY_PROFILE`.

The build downloads checksum-pinned 7-Zip 26.03 sources and compiles the reclamation helper with Apple's C++ toolchain. Its original source package, integration source, build script, and license notices are included in the app's `Resources/Licenses/7zip` folder. Set `ASCENDARA_ARCHIVE_ARCHS="arm64 x86_64"` when preparing the helper for a universal app.

## Setup

Release builds try to bundle a fresh game index. If the endpoint is unavailable, the build uses a cached copy when present. Downloads and backups go to the folders selected in Preferences.

For Windows games, open Preferences > Compatibility to check and install the required Highball components. Game support varies by title and Mac. Compatibility labels use [Highball data](https://gethighball.com/docs/data/).

App data is stored in `~/Library/Application Support/Ascendara Native`. Set `ASCENDARA_NATIVE_HOME` to use another metadata folder for testing. Download folders, macOS preferences, and Keychain entries have their own locations.

## Contributing

See the [TODO list](MacPort/TODO.md) for work that remains. Include a build check with code changes. You can open `MacPort/Package.swift` in Xcode or run `swift build` from `MacPort`.

Use Conventional Commits: `feat(scope): description`, `fix(scope): description`, `docs: description`, or `chore(scope): description`. Keep each commit focused on one change.

Include the root `README.md` in every release commit. Update its version badge and What's new section together with `AppVersion.Current` in `MacPort/Source/Ascendara/App/AppSettings.swift` and `CFBundleShortVersionString` in `MacPort/Scripts/Build.sh`, so the documentation, app, and installer all use the same release version.

Before committing, remove test files, verification-only scripts, and code comments. Run the relevant checks before removing temporary verification code, then build the final source from the repository root:

```sh
swift build --package-path MacPort --disable-index-store -Xswiftc -gnone -j 2
```

`python3 MacPort/Scripts/SyncTranslations.py` refreshes the checked-in dictionaries and language catalogue from the [upstream i18n source](https://github.com/Ascendara/ascendara/blob/main/src/i18n.js). Normal builds do not fetch translations.

## Project structure

- `MacPort/Source/Ascendara`: app, models, services, views, and resources.
- `MacPort/Source/AscendaraDownloadWorker`: direct download helper.
- `MacPort/Source/AscendaraGameHandler`: game session helper.
- `MacPort/Source/AscendaraTorrentHandler`: torrent helper.
- `MacPort/Source/AscendaraCrashReporter`: crash reporter.
- `MacPort/Scripts`: build and packaging scripts.

## License

This project uses the [MIT license](LICENSE). Original Ascendara code and artwork remain credited to their authors. Bundled tools include their own license files.
