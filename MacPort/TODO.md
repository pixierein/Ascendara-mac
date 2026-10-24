# TODO

## Check before release

- Test index refresh and download links with live providers.
- Test pause, resume, cancel, archive extraction, and recovery after closing the app.
- Test Highball setup and game launch on a clean Apple Silicon Mac.
- Test native and Windows games, playtime, and save backups.
- Test torrents, TorBox, and Workshop downloads with real accounts.
- Test Big Picture with a physical controller and TV.
- Test on Intel Macs where supported.
- Add screenshots from the native app.
- Sign and notarize a public release.

## Still to build

- Extract archives without needing space for both the full archive and extracted files.
- Store each game's measured install size and show it in the library and game details.
- Warn early when a single-stream download or extraction will not fit on the drive.
- Let users choose a reinstall folder and whether to keep playtime and achievements.
- Finish the remaining download providers and queue controls.
- Add translations and theme editing.
- Finish automatic game updates, mods, and trainers.
- Add automatic emulator setup and more library tools.
- Finish the updater and notifications.

The app and its build scripts are under `Source/` and `Scripts/`. Use `./Scripts/Build.sh` to make a local build.
