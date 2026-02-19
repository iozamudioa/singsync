## What's new in v1.2.0 (since v1.1.0)

### ✨ Features
- Added snapshot capture flow from the lyrics panel camera action with polished pre-share animation.
- Added Android native share sheet integration with a direct Guardar imagen option.
- Added dynamic snapshot backgrounds based on the dominant album-art color for song-specific visuals.
- Added higher-quality snapshot export at 2x render resolution for better share fidelity.

### 🛠️ Fixes
- Removed the reverted native Android screenshot-listener path and kept camera-driven behavior only.
- Removed extra share caption text so snapshots are shared as image-only.
- Fixed snapshot animation responsiveness by starting visual feedback immediately.
- Fixed duplicate save-flight animation playback.
- Fixed snapshot canvas clipping at high-resolution export that could hide title/artist/lyrics.
- Unified save feedback with the app UI snackbar style instead of a different native toast.
- Improved snapshot text hierarchy and readability:
  - stronger artist contrast,
  - tighter title/artist/lyrics spacing,
  - clearer footer branding text.

### 🌍 Localization
- Added/updated i18n keys for snapshot footer branding text in English and Spanish.
- Corrected brand typo to SingSync in localized snapshot footer text.
