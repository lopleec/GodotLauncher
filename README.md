# Godot Launcher

<p align="center">
  <img src="Resources/VersionLogo.png" width="96" alt="Godot Launcher logo">
</p>

<p align="center">
  A native macOS SwiftUI launcher, downloader, installer, and updater for Godot Engine builds.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-orange">
  <img alt="UI" src="https://img.shields.io/badge/UI-SwiftUI-lightgrey">
</p>

> Godot Launcher is an unofficial community tool. It is not affiliated with or endorsed by the Godot Foundation or the Godot Engine project.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Build, Run, and Test](#build-run-and-test)
- [How Installation Works](#how-installation-works)
- [Download Sources](#download-sources)
- [Settings](#settings)
- [Localization](#localization)
- [Project Structure](#project-structure)
- [Architecture Notes](#architecture-notes)
- [Security and Privacy](#security-and-privacy)
- [Troubleshooting](#troubleshooting)
- [Preparing a Release](#preparing-a-release)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## Overview

Godot Launcher provides a desktop-native way to browse Godot releases, inspect release metadata, download macOS packages, and install or update Godot in the Applications folder.

The app is built with SwiftPM and SwiftUI. It uses native macOS patterns: `NavigationSplitView`, `Table`, toolbar controls, a dedicated Settings scene, application menus, progress alerts, Finder reveal actions, and system notifications.

The main window is split into two panes:

- Left pane: latest stable build or the selected release details.
- Right pane: complete release history, including stable, RC, beta, and development builds.

## Features

### Release browsing

- Fetches releases from the official [`godotengine/godot-builds`](https://github.com/godotengine/godot-builds/releases) GitHub Releases API.
- Shows the latest stable release in the detail pane.
- Keeps the latest version visible in the historical release table.
- Supports Stable, RC, Beta, Alpha, Dev, and preview-style release channels.
- Provides a channel filter menu.
- Provides release search.
- Shows release notes summary text.
- Loads release artwork from the official Godot archive page when available.
- Provides release note and archive page links.

### Native historical table

- Uses native SwiftUI `Table`.
- Supports sortable columns:
  - Version
  - Channel
  - Release date
  - Package size
- Package size sorting uses the currently selected edition:
  - Standard
  - .NET
- Includes row actions:
  - Show Info
  - Open release notes
  - Install / Reinstall / Update

### Downloading

- Supports 2 to 8 download connections.
- Uses HTTP Range requests for multipart downloads.
- Falls back to a single connection when a server does not support ranged downloads.
- Shows real-time download progress:
  - progress bar
  - completed bytes
  - total bytes
  - speed
  - estimated remaining time
- Supports cancelling the active download while it is still cancellable.

### Verification

- Verifies SHA-256 digests when GitHub release assets provide a digest.
- Uses streaming checksum calculation, so large archives are not loaded fully into memory.

### Installation and update behavior

- Extracts `.zip` archives with the macOS system `ditto` tool.
- Finds the Godot `.app` bundle inside the extracted archive.
- Supports two default behaviors:
  - Install: keep existing apps and avoid name collisions.
  - Update: replace the existing `Godot.app` with the downloaded version.
- Supports install locations:
  - `/Applications`
  - `~/Applications`
- Shows completion alerts.
- Supports system notifications.
- Can reveal the installed app in Finder.
- Can launch Godot automatically after installation.
- Tracks installed releases and removes stale receipts when the installed app no longer exists.

### Name collision policy

Install mode never overwrites an existing application. It resolves collisions in this order:

1. `Godot.app`
2. `Godot <version>.app`
3. `Godot <version> <MM_dd_yy_HH_mm_ss>.app`
4. If the timestamped name still exists, a numeric suffix is appended.

Update mode targets `Godot.app` and uses a staged replacement flow with rollback when possible.

### Download sources

- Official GitHub release assets.
- GodotHub.com mirror for stable builds.
- Custom HTTPS URL templates.

GodotHub is intentionally stable-only because the configured GodotHub mirror does not provide RC, beta, or development builds.

### Localization

- English.
- Simplified Chinese.
- Follow System mode.
- Language can be changed inside the app without restarting.
- Window title and native macOS menus are updated at runtime.
- The application name remains `Godot Launcher` across languages.

## Requirements

- macOS 14.0 or later.
- Xcode Command Line Tools or Xcode.
- Swift toolchain compatible with SwiftPM package tools version 6.0.
- Network access to the selected download source.

Install Command Line Tools if needed:

```bash
xcode-select --install
```

## Quick Start

Clone the repository:

```bash
git clone <repository-url>
cd godot_update
```

Build and launch:

```bash
./script/build_and_run.sh
```

Run tests:

```bash
swift test
```

## Build, Run, and Test

This project is SwiftPM-first. The main package file is [`Package.swift`](Package.swift).

### Build

```bash
swift build
```

### Test

```bash
swift test
```

### Build and run the app bundle

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM executable, stages a macOS app bundle, signs it ad hoc, and launches:

```text
dist/Godot Launcher.app
```

### Verify app launch

```bash
./script/build_and_run.sh --verify
```

### Stream logs

```bash
./script/build_and_run.sh --logs
```

### Launch under LLDB

```bash
./script/build_and_run.sh --debug
```

## How Installation Works

1. The app fetches release metadata from GitHub or cache.
2. The selected release is matched to a macOS archive asset.
3. The selected download source resolves the final archive URL.
4. The archive is downloaded with multipart HTTP Range requests when supported.
5. SHA-256 verification runs when a digest is available.
6. The archive is extracted into a temporary working directory.
7. The first valid `.app` bundle is located.
8. The app is copied or staged into the selected Applications directory.
9. A receipt is saved to Application Support.
10. The temporary working directory is removed.

If the selected destination requires administrator privileges, macOS shows the standard authorization dialog.

## Download Sources

### Official

Uses the `browser_download_url` from the official GitHub release asset.

### GodotHub.com

Uses this pattern:

```text
https://atomgit.com/godothub/godot/releases/download/{tag}/{asset}
```

Example:

```text
https://atomgit.com/godothub/godot/releases/download/4.7-stable/Godot_v4.7-stable_macos.universal.zip
```

Limitations:

- Stable builds only.
- RC, beta, alpha, dev, and preview builds are disabled for this source.

### Custom

Custom sources must use HTTPS and must include the `{asset}` placeholder.

Supported placeholders:

- `{tag}`: release tag, for example `4.7-stable`
- `{asset}`: release asset file name, for example `Godot_v4.7-stable_macos.universal.zip`

Example:

```text
https://mirror.example.com/godot/{tag}/{asset}
```

Preview builds are disabled for custom sources unless the matching Settings option is enabled.

## Settings

Godot Launcher includes a native macOS Settings window.

### General

- Application language:
  - Follow System
  - English
  - Simplified Chinese
- Default edition:
  - Standard
  - .NET
- Show release summary
- Refresh releases at launch
- Cache duration
- Clear release cache

### Versions

- Show Stable builds
- Show RC builds
- Show Beta builds
- Show development builds
- Confirm before installing preview builds

### Downloads

- Download source:
  - Official
  - GodotHub.com
  - Custom
- Multipart download connections
- Default action:
  - Install
  - Update
- Install location
- Keep downloaded archives
- SHA-256 verification status

### Completion

- Send system notification
- Reveal app in Finder
- Launch Godot after installation

## Localization

Localization files are stored in:

```text
Resources/en.lproj/Localizable.strings
Resources/zh-Hans.lproj/Localizable.strings
Resources/en.lproj/InfoPlist.strings
Resources/zh-Hans.lproj/InfoPlist.strings
```

The app uses a small localization helper so app-language preferences can be applied immediately. Standard SwiftUI views receive the selected `Locale`, and a narrow AppKit bridge updates window titles and native macOS menus at runtime.

## Project Structure

```text
.
├── Package.swift
├── README.md
├── Resources
│   ├── AppIcon.icns
│   ├── VersionLogo.png
│   ├── en.lproj
│   └── zh-Hans.lproj
├── Sources
│   └── GodotLauncher
│       ├── App
│       ├── Models
│       ├── Services
│       ├── Stores
│       ├── Support
│       └── Views
├── Tests
│   └── GodotLauncherTests
└── script
    └── build_and_run.sh
```

## Architecture Notes

### App

The SwiftUI entry point configures:

- main `WindowGroup`
- native Settings scene
- toolbar commands
- app defaults
- activation policy

### Models

The model layer defines release metadata, release assets, edition/channel classification, preferences, download sources, and installation state.

### Services

Services own side effects:

- GitHub release fetching and caching
- multipart downloads
- SHA-256 verification
- archive extraction and installation
- release artwork lookup
- notifications
- optional archive retention

### Store

`LauncherStore` owns observable app state:

- release list
- loading state
- active installation job
- completion state
- pending preview confirmation
- installation receipts

### Views

Views are split by screen responsibility:

- `ContentView`: root split view and toolbar.
- `LatestReleaseView`: selected/latest release details.
- `HistoryView`: native release table and actions.
- `SettingsView`: native macOS settings.
- `ActivityBar`: bottom progress surface.
- `ReleaseArtworkView`: release artwork loading.

### Support

Support files contain formatting, localization, constants, app-directory helpers, title/menu runtime localization, and destination-name resolution.

## Security and Privacy

- The app downloads Godot release metadata and archives from the selected source.
- Custom download sources must use HTTPS.
- SHA-256 verification runs when an official digest is available.
- No telemetry or analytics are collected by this app.
- Installation receipts are stored locally in the user's Application Support directory.
- Downloaded temporary files are removed after installation unless "Keep downloaded archives" is enabled.
- Administrator authorization may be requested by macOS when writing to protected application locations.

## Troubleshooting

### GitHub rate limit

If release fetching fails with a GitHub rate-limit message, wait for the limit to reset or use cached data if available.

### GodotHub source cannot install RC or beta builds

This is expected. GodotHub support is stable-only in this app.

### Custom source is disabled

Check that the template:

- starts with `https://`
- includes `{asset}`
- points to a valid host
- supports the selected release channel

### Installation asks for administrator permission

Writing to `/Applications` can require administrator authorization. Use `~/Applications` if you want a user-local install location.

### Download falls back to a single connection

The server may not support HTTP Range requests. Godot Launcher automatically falls back to a single connection.

### App bundle does not launch from `dist`

Run:

```bash
./script/build_and_run.sh --verify
```

The script clears common extended attributes, signs the bundle ad hoc, launches it, and checks that the process exists.

## Preparing a Release

Before tagging a release:

```bash
swift test
./script/build_and_run.sh --verify
```

Recommended manual checks:

- Switch language between English and Simplified Chinese without restarting.
- Confirm title bar and menu bar update after language changes.
- Sort the history table by package size for both Standard and .NET editions.
- Verify Stable, RC, Beta, and development channel filters.
- Verify Official, GodotHub.com, and Custom download source validation.
- Install to `~/Applications` first.
- Test update mode only with a disposable `Godot.app`.

The local bundle is produced at:

```text
dist/Godot Launcher.app
```

For public distribution, replace ad-hoc signing with a Developer ID signing and notarization workflow.

## Contributing

Contributions are welcome.

Suggested workflow:

1. Open an issue describing the bug or feature.
2. Keep UI changes native to macOS SwiftUI unless AppKit is required for a narrow platform bridge.
3. Add or update tests for behavior changes.
4. Run `swift test`.
5. Run `./script/build_and_run.sh --verify` for UI or launch changes.
6. Keep generated files out of commits.

## License

This project is licensed under the GNU General Public License. See [LICENSE](LICENSE) for details.

## Acknowledgements

- [Godot Engine](https://godotengine.org/)
- [godotengine/godot-builds](https://github.com/godotengine/godot-builds)
- [GodotHub.com](https://godothub.com/download)
