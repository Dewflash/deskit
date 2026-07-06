# DeskIt

DeskIt is a single macOS menu-bar host for small desktop utilities.

The host app is named `DeskIt`. `Dewdrops` is one internal app inside the suite, alongside Pomodewro, ColourDrop, DewQRaft, and TextCleaner.

## Architecture

- `config/apps.json` is the app registry source of truth.
- `scripts/sync-apps.swift` copies web app snapshots from sibling project folders into the DeskIt bundle and emits `Contents/Resources/app-registry.json`.
- Native modules live in DeskIt as small SwiftUI views.
- Web modules are loaded from `Contents/Resources/apps/{appId}/`.
- Each internal app has a `deskit.{appId}.` storage namespace so DeskIt state does not collide with standalone apps.
- DeskIt uses the bundle identifier `com.kevinyongcj.deskit`, separate from the standalone apps.

## Build

```sh
./scripts/build-mac-app.sh
```

The output is:

```text
build/DeskIt.app
```

## Updating Apps

Rerun the build script. The sync step recopies the latest web snapshots from:

- `../mac-pomodoro`
- `../mac-dewdrops`
- `../dewQRaft`

Native DeskIt modules are compiled from the Swift source in `macos/`.

## Removing Apps

Delete the app entry from `config/apps.json`, then rebuild. Web snapshots are regenerated from the registry on each build, so removed apps are not carried forward into the bundle.
