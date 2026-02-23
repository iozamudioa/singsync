# Changelog

## 1.3.1+5 - 2026-02-23

### Features
- Added sleep timer with two modes: by duration and by song count.
- Added sleep timer setup/detail modals with live countdown/status updates.
- Added timer active indicator in playback header with direct access to timer details.
- Moved timer and app info actions into overflow submenu in bottom navigation.
- Added dynamic app icon loading for unknown media players (native Android icon fallback).
- Added searchable My Songs and Snapshot Gallery views.
- Added snapshot metadata parsing (title/artist/source package) and gallery grouping by Today / This Week / Older.

### Improvements
- Improved keyboard behavior to prevent artwork background resizing on search input.
- Added outside-tap keyboard dismiss for gallery/favorites search fields.
- Synced snapshot preview thumbnail strip auto-scroll with active page.
- Standardized modal visual style (transparent blur) for timer and supporting dialogs.
- Updated snapshot naming format to embed metadata for better gallery indexing.
- Replaced snackbar-based top feedback with overlay feedback above navigation area.

### Localization
- Removed hardcoded strings in touched playback/timer/search/header flows.
- Added new localization keys in English and Spanish for timer, submenu, search, section labels, and status messages.
- Regenerated localization files.
- Simplified timer completion message to: "Temporizador completo.".

### Android / Native
- Added `getMediaAppIcon` method channel for package icon extraction.
- Added `turnScreenOffIfPossible` method channel (best-effort behavior, device dependent).

### Release / Build
- Bumped app version to `1.3.1+5`.
- Added deployment helper script at `scripts/deploy-android-release.ps1` for analyze/build/install/validate/launch flow.
- Verified release APK generation for current build.
