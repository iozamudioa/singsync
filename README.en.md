# SingSync

Welcome to **SingSync**: an Android app that detects what is playing, fetches lyrics, shows a stylish vinyl UI, and acts like this was always a perfectly calm and linear plan.  
It was not. It works anyway.

> Primary project language is **Spanish**.  
> Main documentation (mandatory): [README.md](README.md)

---

## What SingSync does

SingSync listens to Android now-playing signals and selects behavior based on source:

1. `media_player` → active media session from a player app.
2. `pixel_now_playing` → ambient song recognition from the system.

Then it decides what lyrics mode and controls should be active.

---

## Core features

### Playback and lyrics

- Detects currently playing tracks from notifications/media sessions.
- Media controls where supported: `prev / play-pause / next`.
- Fetches lyrics from LRCLIB in two modes:
  - **plain** (best for ambient detection flow)
  - **synced/LRC** (best for active player sessions)
- Manual lyrics search with candidate selection.

### UI and experience

- Vinyl-centered now-playing UI with artwork fallback.
- Quick snapshot generation and sharing.
- Top overlay feedback (no navbar overlap drama).
- Better keyboard/search behavior and smoother gallery interactions.

### Gallery and favorites

- Saved snapshots gallery with:
  - search by song/artist,
  - grouping by **Today / This Week / Older**,
  - preview, share, and delete.
- “My Songs” favorites view with search and quick management.

### Sleep Timer (new in 1.3.1+5)

- Sleep timer by:
  1. **Time duration**
  2. **Song count**
- Setup modal + active status modal.
- Active timer indicator in header.
- Simplified completion message: **“Temporizador completo.”**
- Native best-effort screen-off attempt when timer completes.

### Music app integration

- Supported app packages:
  - Spotify → `com.spotify.music`
  - YouTube Music → `com.google.android.apps.youtube.music`
  - Amazon Music → `com.amazon.mp3`
  - Apple Music → `com.apple.android.music`
- Unknown players try native Android app-icon extraction as fallback.

---

## Tech stack

- **Flutter** (UI + state)
- **Native Android Kotlin** (notification listener, media sessions, platform bridges)
- **LRCLIB** (lyrics provider)
- **SQLite / sqflite** (local cache)
- **MethodChannel / EventChannel** (Flutter ↔ Android communication)

Because one layer would have been too easy.

---

## Localization

- Active languages: **Spanish** and **English**.
- Recent touched flows were migrated away from hardcoded strings.
- Base files:
  - `lib/l10n/app_es.arb`
  - `lib/l10n/app_en.arb`

---

## Android build and release

### Manual APK build

```bash
flutter build apk --release
```

Expected APK path:

`build/app/outputs/flutter-apk/app-release.apk`

### Recommended deployment script

Use:

`scripts/deploy-android-release.ps1`

It runs analysis, release build, install, version/timestamp validation, and launch.

### AAB build

```bash
flutter build appbundle --release
```

---

## Google Play compliance

- [Google Play Compliance Checklist](docs/google-play-compliance-checklist.md)
- [Privacy Policy](docs/privacy-policy.md)

---

## Signing and secrets

Release signing relies on `android/key.properties` and a local keystore.

Do **not** commit:

- `android/key.properties`
- `android/app/*.jks`
- `android/app/*.keystore`

If leaked, rotate credentials and replace keystore.

---

## Current status

- Version: **1.3.1+5**
- Static analysis: **clean** (`flutter analyze --no-fatal-infos --no-fatal-warnings`)

Enjoy it while it lasts.

---

## TL;DR

SingSync detects songs, routes behavior by source, shows the right lyrics mode, provides practical controls, supports snapshots/favorites/sleep timer, and wraps it all in a vinyl UI that is intentionally prettier than strictly necessary.
