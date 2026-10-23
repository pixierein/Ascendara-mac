<div align="center">
    <img align="center" width="128" height="128" src="./MacPort/Sources/Ascendara/Resources/AppIcon.png" alt="Ascendara Logo">
    <h1>Ascendara for macOS</h1>
    <p><em>Less setup. More play.</em></p>
    <p>
        <a href="https://discord.gg/ap6W3xMTKW"><img src="https://img.shields.io/discord/939249162887766139?color=7289da&label=discord&logo=discord&logoColor=white" alt="Discord"></a>
        <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 or later">
        <img src="https://img.shields.io/badge/SwiftUI-native-orange?logo=swift&logoColor=white" alt="Native SwiftUI">
        <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
    </p>
    <p>
        <a href="https://github.com/Ascendara/ascendara/releases"><img src="https://img.shields.io/github/v/release/Ascendara/ascendara?include_prereleases&label=upstream%20release" alt="Upstream Release"></a>
        <a href="https://github.com/Ascendara/ascendara/stargazers"><img src="https://img.shields.io/github/stars/Ascendara/ascendara?style=social&label=Upstream%20Stars" alt="Upstream GitHub Stars"></a>
    </p>
</div>

## 🎮 About

Ascendara simplifies your game management experience by providing a seamless way to discover, organize, and test pre-installed games. No more hassle with extracting, installing, or moving files. The game library is powered by a custom webscraper, currently featuring titles mainly from [STEAMRIP](https://ascendara.app/sources/steamrip) with plans to expand to more sources and is brought to macOS through this native SwiftUI and AppKit port.

This is an unofficial macOS port, based on Ascendara 11.6.0. Follow the [macOS checklist](MacPort/TODO.md) for completed features and remaining work.

### 🔗 Quick Links

- [Build and run on macOS](#-running-from-source)
- [macOS development checklist](MacPort/TODO.md)
- [Join the Ascendara Discord](https://ascendara.app/discord)
- [Original Ascendara project](https://github.com/Ascendara/ascendara)
- [Read the upstream changelog](https://ascendara.app/changelog)
- [Learn about Ascend](https://ascendara.app/ascend)

## ✨ Features

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🚀 Seamless Downloads</h3>
      <p>Download supported games with native progress, queue controls, pause/resume, and archive extraction.</p>
    </td>
    <td width="50%" valign="top">
      <h3>☁️ Cloud Backups</h3>
      <p>Back up saves locally, with Ascend cloud-backup integration available through account configuration.</p>
    </td>
  </tr>

  <tr>
    <td width="50%" valign="top">
      <h3>🔌 Game Information</h3>
      <p>View game details, artwork, story information, screenshots, requirements, and public ratings.</p>
    </td>
    <td width="50%" valign="top">
      <h3>🌐 Browser Integration</h3>
      <p>Open supported ascendara:// game links directly in the native macOS app.</p>
    </td>
  </tr>

  <tr>
    <td width="50%" valign="top">
      <h3>🎨 Theme Customization</h3>
      <p>Customize Ascendara with twelve original themes, native animations, and reduced-motion controls.</p>
    </td>
    <td width="50%" valign="top">
      <h3>🕑 Local Indexing</h3>
      <p>Search through supported games quickly using Ascendara's cached catalogue and custom sources.</p>
    </td>
  </tr>

  <tr>
    <td width="50%" valign="top">
      <h3>📱 Ascendara Companion</h3>
      <p>Companion pairing and remote download monitoring are planned for the macOS port. Track progress in the TODO checklist.</p>
    </td>
    <td width="50%" valign="top">
      <h3>🕹️ Big Picture Mode</h3>
      <p>Browse installed games and launch them through a large-screen interface with keyboard navigation. Full controller support is planned.</p>
    </td>
  </tr>

  <tr>
    <td width="50%" valign="top">
      <h3>💾 Ascendara Retro</h3>
      <p>Keep your older console games in their own library with artwork, setup memory, and easy launching.</p>
    </td>
    <td width="50%" valign="top">
      <h3>🌍 Language Support</h3>
      <p>The macOS interface is currently English. Additional languages and translation packs are on the roadmap.</p>
    </td>
  </tr>
</table>

## 🖼️ Preview App Pages

These screenshots show the original Ascendara design used as the macOS port’s reference. Native macOS screenshots are tracked in the [TODO checklist](MacPort/TODO.md).

<details>
<summary>Dropdown all pages</summary>
<div style="display: flex; flex-wrap: wrap; justify-content: center;">
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Home Page</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/home.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Search Page</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/search.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Download Game</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/download-game.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Game Metadata</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/game-metadata.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Library</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/library.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Play Game</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/playgame.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Downloads</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/downloads.png" width="100%"/>
  </div>
  <div style="margin: 1%; width: 24%;">
    <h3 style="text-align: center;">Profile</h3>
    <img src="https://raw.githubusercontent.com/pixierein/ascendara/88f2e323cd58213975806a4cb62d5496f1e136c7/readme/profile.png" width="100%"/>
  </div>
</div>
</details>

## 📦 Install Ascendara for macOS

Requires **macOS 14 or later**. Open the macOS DMG and drag **Ascendara** onto **Applications**. To make a local installer, use the [DMG build command](#dmg-installer) below. You can also build the app from source and copy `MacPort/Build/Ascendara.app` into Applications.

The app builds for the current Mac’s architecture. Highball support for Windows games requires Apple Silicon; Wine engines, Rosetta where needed, and game compatibility are separate setup requirements.

## 🤝 Contributing

Contributing to Ascendara for macOS helps bring more features and improvements to the native app. Check the [TODO checklist](MacPort/TODO.md), choose an open item, and include relevant verification with your pull request. Use simple PascalCase identifiers except where Swift APIs require specific names.

The original Ascendara project and its contribution information are available [here](https://github.com/Ascendara/ascendara).

## 📂 Project Structure

The native macOS project lives in **MacPort/**:

- **Sources/Ascendara/App/** — application, custom titlebar, navigation, state, and preferences.
- **Sources/Ascendara/Models/** — game, catalogue, and runtime models.
- **Sources/Ascendara/Services/** — downloads, library storage, accounts, backups, and process management.
- **Sources/Ascendara/Views/** and **IntegrationViews/** — SwiftUI screens and integrations.
- **Sources/Ascendara/Resources/** — app icons and retro console metadata.
- **Scripts/** — app/DMG builds, helper setup, and launch commands.
- **TODO.md** — completed features and remaining work.

Generated apps, helper binaries, and compiler caches are ignored by Git.

## 🛠️ Running from Source

### Prerequisites

- macOS 14 or later.
- A Swift 6 toolchain. Apple’s Command Line Tools are sufficient; full Xcode is optional.
- Python 3 and Git only if building the optional Highball helper.

The app itself uses SwiftUI and AppKit, with no Electron, Chromium, Node, or Python runtime.

### Quick Start

From the repository root:

```sh
cd MacPort
./Scripts/Build.sh
open Build/Ascendara.app
```

For a debug build and launch:

```sh
./Scripts/Run.sh
```

Open `MacPort/Package.swift` in Xcode to work on the native project. The build automatically downloads and verifies the pinned 7-Zip 26.03 helper when needed, and packages its license notices.

### Windows Game Compatibility

From `MacPort`, optionally build and bundle Highball:

```sh
python3 Scripts/BuildHighball.py
./Scripts/Build.sh
```

The helper builds the pinned Highball v0.10.22 CLI for Apple Silicon. In Preferences → Compatibility, configure Highball engines and bottles or select an installed Wine executable. Engines are installed separately; D3DMetal license acceptance and Rosetta setup remain explicit actions. SteamCMD and retro emulators can also be selected in Preferences.

### Accounts and App Data

Firebase account configuration is entered in Ascend → Account configuration. Account services require a valid configuration; TorBox requires its own account key. Credentials use macOS Keychain where supported.

App metadata lives in `~/Library/Application Support/Ascendara Native`. Existing Electron libraries can be imported explicitly. Downloads and backups use the locations selected in Preferences.

<details>
<summary>Isolated development data</summary>

Set `ASCENDARA_NATIVE_HOME=/absolute/test/directory` when launching the executable to redirect app metadata, the catalogue cache, and Highball engine/bottle storage. Download and backup destinations, UserDefaults, and Keychain retain their own locations. Use separate paths and test credentials when exercising those integrations.

</details>

### Verify the Build

From `MacPort`:

```sh
./Scripts/Build.sh
codesign --verify --deep --strict Build/Ascendara.app
```

Live provider/account verification is tracked in [TODO.md](MacPort/TODO.md). `swift package clean` removes compiler output while keeping the packaged app and prepared helpers.

### Release Builds

Release packaging optimizes for size, strips unused symbols and helper architectures, and applies transparent APFS/HFS+ compression. The app keeps its original full-resolution artwork and native animations. Current local packaging uses about **4.7 MB on disk**, with **8.6 MB of uncompressed contents**; allocation depends on filesystem support.

Builds use ad-hoc signing by default. `ASCENDARA_MAC_SIGN_IDENTITY` selects an installed signing identity and enables hardened runtime and secure timestamps for the app and bundled executables.

### DMG Installer

From the repository root:

```sh
./MacPort/Scripts/BuildDmg.sh
```

This builds the release app and creates `MacPort/Build/Ascendara-Mac-<version>-<architecture>.dmg` with an Applications shortcut and a matching `.dmg.sha256` checksum. The version comes from the app's `Info.plist`; the architecture comes from its executable. `MacPort/Build` is ignored by Git.

To package the existing app without compiling it again:

```sh
./MacPort/Scripts/BuildDmg.sh --skip-build
```

### Signed and Notarized Releases

Install your Developer ID Application certificate in Keychain, then save notarization credentials using `xcrun notarytool store-credentials Ascendara`. See [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) for credential setup.

```sh
ASCENDARA_MAC_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
ASCENDARA_MAC_NOTARY_PROFILE="Ascendara" \
./MacPort/Scripts/BuildDmg.sh --notarize
```

The script signs the app, its helpers, and the DMG, submits the image to Apple, requires an accepted result, and staples and validates the ticket. Notarization reports stay in `MacPort/Build`. The checksum is generated after signing and stapling. An unsuccessful run keeps the previous completed DMG intact.

Without `--notarize`, packaging stays local and produces a non-notarized DMG. Developer ID signing and Apple's notarization service need your configured credentials; the local build does not establish acceptance by Gatekeeper.

## 🗺️ Development Roadmap

The macOS roadmap is maintained as a [checkable TODO list](MacPort/TODO.md). The original Ascendara roadmap is available [here](https://ascendara.app/roadmap).

## 📝 License & Contact

Licensed under [MIT](./LICENSE) - 2026 tagoWorks. Original code and artwork attribution is preserved. Bundled 7-Zip and optional Highball have their own license notices.

### Original Project Contact

- Email: [santiago@tago.works](mailto:santiago@tago.works)
- Website: [tago.works](https://tago.works)
- Discord: [Join the community](https://ascendara.app/discord)

---

<div align="center">
    <sub>Original Ascendara built with ❤️ by <a href="https://tago.works">tago</a> · Native macOS community port</sub>
</div>
