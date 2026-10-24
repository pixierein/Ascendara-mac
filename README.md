<div align="center">
  <img width="128" height="128" src="./MacPort/Source/Ascendara/Resources/AppIcon.png" alt="Ascendara icon">
  <h1>Ascendara for macOS</h1>
  <p>Native SwiftUI port of Ascendara</p>
  <p>
    <img src="https://img.shields.io/badge/version-11.6.1-blue" alt="Version 11.6.1">
    <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
    <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
  </p>
</div>

## About

Ascendara for macOS is a native app for finding, downloading, organizing, and launching games. It is based on the [original Ascendara project](https://github.com/Ascendara/ascendara), but has its own SwiftUI interface and macOS helpers. Ascend account features are not available in this port; use the [official launcher](https://www.ascendara.app/thank-you) for Ascend.

Quick links: [Build](#build-and-install) · [Project structure](#project-structure) · [TODO](MacPort/TODO.md) · [Original project](https://github.com/Ascendara/ascendara)

## Features

- **Downloads:** Manage direct downloads with live progress, pause, resume, and cancellation. Supported ZIP, 7z, and RAR archives can be extracted after download. Parallel transfers check available space when the host reports a file size.
- **Game information:** Browse artwork, screenshots, requirements, ratings, and release details. Catalog sizes are download sizes, not installed sizes.
- **Local index:** Search a cached game catalog, refresh it from the public JSON endpoint, or import an `ascendara_games.json` file. The original app is not required.
- **Library:** Import and launch native or Windows games, track playtime, manage favorites and collections, and back up saves locally. The library space panel measures files on disk.
- **Mac compatibility:** Use Highball to set up a Wine engine and run supported Windows games on Apple Silicon.
- **Big Picture and Retro:** Browse with a controller-friendly layout and keep console games in a separate library.
- **Themes and links:** Choose a theme and open supported `ascendara://` links in the app.

## What's new in 11.6.1

- Desktop game cards, search results, and game details label catalog sizes as **download sizes**.
- The app, installer, and API version headers use 11.6.1.

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

## Setup

Release builds try to bundle a fresh game index. If the endpoint is unavailable, the build uses a cached copy when present. Downloads and backups go to the folders selected in Preferences.

For Windows games, open Preferences > Compatibility to check and install the required Highball components. Game support varies by title and Mac. Compatibility labels use [Highball data](https://gethighball.com/docs/data/).

App data is stored in `~/Library/Application Support/Ascendara Native`. Set `ASCENDARA_NATIVE_HOME` to use another metadata folder for testing. Download folders, macOS preferences, and Keychain entries have their own locations.

## Contributing

See the [TODO list](MacPort/TODO.md) for work that remains. Include a build check with code changes. You can open `MacPort/Package.swift` in Xcode or run `swift build` from `MacPort`.

## Project structure

- `MacPort/Source/Ascendara`: app, models, services, views, and resources.
- `MacPort/Source/AscendaraDownloadWorker`: direct download helper.
- `MacPort/Source/AscendaraGameHandler`: game session helper.
- `MacPort/Source/AscendaraTorrentHandler`: torrent helper.
- `MacPort/Source/AscendaraCrashReporter`: crash reporter.
- `MacPort/Scripts`: build and packaging scripts.

## License

This project uses the [MIT license](LICENSE). Original Ascendara code and artwork remain credited to their authors. Bundled tools include their own license files.
