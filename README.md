# Launchpad

Launchpad is a native macOS application built with SwiftUI and AppKit.

## Build

Requires macOS 13 or later and the Xcode command-line tools.

```sh
swift build
swift run LaunchpadCoreChecks
./scripts/build-macos.sh
```

The app bundle and distributable ZIP are written to `dist/`.

The app scans `/Applications`, `/System/Applications`, and the current user's
`~/Applications` folder. Application ordering and manually created folders are
stored in `~/Library/Application Support/launchpadapp/`.
