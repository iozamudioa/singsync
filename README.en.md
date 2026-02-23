# SingSync

Welcome to **SingSync** 🎵💿: an Android app that detects what is playing, fetches lyrics, shows a stylish vinyl UI, and pretends this was always a calm, perfectly linear master plan.  
It was not. It works anyway. You're welcome. 😌

## ⭐ Main focus: Google Pixel + Pixel Now Playing

Yes, **SingSync works with Pixel Now Playing**, and this is not a hidden side detail: it is a core product pillar.  
If you use a Pixel, this is where the app shines brightest 🔥:

- Integration with Pixel ambient song detection.
- Dedicated flow for `pixel_now_playing` source.
- `plain` lyrics mode prioritized for this scenario.
- Smart transition to `media_player` flow when a real active session appears.

In short: it doesn't just "also" work on Pixel… **it is designed to take advantage of it**. 🚀

And if you don't have a Pixel, no worries: it also works on any compatible Android device (**Android 7.0 / API 24 or higher**).  
So yes, Pixel is the main character… but nobody is left out of the party. 🎉

> Primary project language is **Spanish**.  
> Main documentation (mandatory): [README.md](README.md) 🇪🇸

---

## What SingSync does

SingSync listens to Android now-playing signals and selects behavior based on source:

1. `media_player` → active media session from a player app (when life is good).
2. `pixel_now_playing` → ambient system recognition, especially valuable on **Google Pixel** (when Android feels mysterious).

Then it decides what lyrics mode and controls should be active, because context matters even when we wish it didn't. 🧠✨

---

## Core features

### Playback and lyrics

- Detects currently playing tracks from notifications/media sessions 🔎.
- Highlighted compatibility with **Pixel Now Playing** for Google Pixel users 📱.
- Media controls where supported: `prev / play-pause / next` ⏮️⏯️⏭️.
- Fetches lyrics from LRCLIB in two modes:
  - **plain** (best for ambient detection flow)
  - **synced/LRC** (best for active player sessions)
- Manual lyrics search with candidate selection, because auto-detection occasionally chooses chaos. 🫠

### UI and experience

- Vinyl-centered now-playing UI with artwork fallback 💿.
- Quick snapshot generation and sharing 📸.
- Top overlay feedback (no navbar overlap drama, finally) ✅.
- Better keyboard/search behavior and smoother gallery interactions.

### Gallery and favorites

- Saved snapshots gallery with:
  - search by song/artist,
  - grouping by **Today / This Week / Older**,
  - preview, share, and delete.
- “My Songs” favorites view with search and quick management ❤️.

### Sleep Timer (new in 1.3.1+5)

- Sleep timer by:
  1. **Time duration**
  2. **Song count**
- Setup modal + active status modal.
- Active timer indicator in header 💤.
- Simplified completion message: **“Temporizador completo.”**
- Native best-effort screen-off attempt when timer completes (device policy permitting, moon phase optional). 🌙

### Music app integration

- Supported app packages:
  - Spotify → `com.spotify.music`
  - YouTube Music → `com.google.android.apps.youtube.music`
  - Amazon Music → `com.amazon.mp3`
  - Apple Music → `com.apple.android.music`
- Unknown players try native Android app-icon extraction as fallback (yes, even the weird ones). 🎯

---

## Tech stack

- **Flutter** (UI + state)
- **Native Android Kotlin** (notification listener, media sessions, platform bridges)
- **LRCLIB** (lyrics provider)
- **SQLite / sqflite** (local cache)
- **MethodChannel / EventChannel** (Flutter ↔ Android communication)

Because one layer would have been too easy, and apparently we enjoy complexity with confidence. 🧩

---

## Localization

- Active languages: **Spanish** and **English** 🌍.
- Recently touched flows were migrated away from hardcoded strings.
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
Yes, it's stricter than "works on my phone". 🚨

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
No, this is not optional if you enjoy sleeping peacefully.

---

## Current status

- Version: **1.3.1+5**
- Static analysis: **clean** (`flutter analyze --no-fatal-infos --no-fatal-warnings`)

Enjoy it while it lasts before the next PR reintroduces character development. 🫡

---

## TL;DR

SingSync detects songs, routes behavior by source, shows the right lyrics mode, provides practical controls, supports snapshots/favorites/sleep timer, and wraps it all in a vinyl UI that is intentionally prettier than strictly necessary.

Because when chaos looks polished, people call it strategy. 🎭
