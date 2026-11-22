# Launchpad

Launchpad is a native macOS app launcher built with SwiftUI and AppKit. It displays installed apps in a full-screen panel and supports search, sorting, and folders.

## Features

- Scans `/Applications`, `/System/Applications`, and the current user's `~/Applications` directory.
- Automatically groups apps by their containing directory; directories with multiple apps appear as folders.
- Searches app names and paths. Press Return on the root page to launch the first matching app.
- Drag icons to reorder apps or drop them onto other apps and folders to create or expand groups.
- Open folders to browse their apps. Rename manual groups or remove apps from them by dragging apps out.
- Saves app ordering and manual groups automatically so they are restored on the next launch.

## Usage

When Launchpad starts, the search field receives focus automatically. Click an app icon to launch it or a folder to open it. Press `Esc` or click the background to go back; on the root page, this closes the panel.

Drag icons to reorder them. Drop an app onto another app or folder to create or expand a manual group. Double-click a manual group name to edit it, or use the context menu and choose **Rename Folder**. To remove an app from a group, drag it to the **Remove from Folder** area.

Search filters the current page by app name or path. On the root page, press Return to launch the first matching app.

## Requirements

- macOS 13 or later
- Swift 5.9 or later and the Xcode Command Line Tools

## Development and Checks

Run these commands from the project root:

```sh
# Build
swift build

# Run native logic checks
swift run LaunchpadCoreChecks

# Run the app in debug configuration
swift run LaunchpadApp
```

`LaunchpadCoreChecks` is an executable check suite that uses assertions to verify core logic, including app grouping, search, folder management, ordering, and persistence.

## Build a macOS App Bundle

Run the packaging script:

```sh
./scripts/build-macos.sh
```

The script builds the app in Release configuration and creates `LaunchpadApp.app` and `LaunchpadApp-mac-x64.zip` in `dist/`. Open the app bundle with:

```sh
open dist/LaunchpadApp.app
```

## Project Structure

```text
Sources/
  LaunchpadApp/        SwiftUI interface and AppKit app entry point
  LaunchpadCore/       App scanning, grouping, ordering, and persistence
  LaunchpadCoreChecks/ Core logic check executable
app-resources/         Info.plist for the macOS app bundle
scripts/               macOS app bundle build script
Launchpad.icns         App icon
Package.swift          Swift Package definition
```

## Local Data

Launchpad stores data in:

```text
~/Library/Application Support/launchpadapp/
```

- `app-order.json`: App ordering on the root page and in automatic folders.
- `app-groups.json`: Manual group names, parent directories, and app paths.
- `apps-cache.json`: Cached list of installed apps for faster startup.

Launchpad scans installed apps but does not move or modify them.
