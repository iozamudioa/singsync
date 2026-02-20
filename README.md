# SingSync

Bienvenido a **SingSync**, la app que existe porque claramente el mundo necesitaba otro experimento para perseguir notificaciones musicales y convertirlas en letras con UI de vinil.  
¿Era estrictamente necesario? Probablemente no.  
¿Funciona? Sorprendentemente, sí.

---

## ¿Qué es esto (además de una cadena de decisiones cuestionables)?

SingSync escucha el now playing desde Android y te muestra la letra de la canción, con dos caminos distintos porque la realidad nunca es simple:

1. **`media_player`** → cuando hay sesión real de reproductor activa.
2. **`pixel_now_playing`** → cuando Pixel Now Playing detecta una canción ambiental.

La app decide qué tipo de letra mostrar según la fuente, porque sí, el contexto importa incluso cuando uno finge que no.

---

## Funcionalidad principal

- Escucha notificaciones musicales del sistema y eventos de sesión de medios.
- Muestra vinil con portada (si no viene, la busca por metadata).
- Soporta controles multimedia en flujo de reproductor: `prev / play-pause / next`.
- Busca letras en LRCLIB.
- Guarda caché local para no estar preguntando lo mismo al universo en cada refresh.
- Mantiene dos variantes de letra:
	- **plain** (ideal para Pixel Now Playing)
	- **synced/LRC** (ideal para reproductor activo)
- Filtra botones de apps musicales para mostrar solo las instaladas en el dispositivo (porque fingir que tienes Apple Music instalado no lo instala mágicamente).

---

## Flujo de comportamiento

### A) Si la fuente es `media_player`

- UI de reproducción activa.
- Controles multimedia funcionales sobre la sesión activa.
- Letra **synced** prioritaria.
- Si no hay portada en metadata del player, fallback por búsqueda.

### B) Si la fuente es `pixel_now_playing`

- UI orientada a abrir apps musicales instaladas.
- Letra **plain** prioritaria.
- Si luego aparece sesión real de reproductor, migra al flujo `media_player` y cambia a synced cuando corresponde.

### C) Si no hay reproducción activa

- Pantalla de espera con vinil vacío.
- Mensajes según permisos.
- Botones de apps instaladas para abrir el medio y empezar desde ahí.

---

## Stack técnico (el breve resumen de “qué estaba pensando”)

- **Flutter** para UI/estado.
- **Kotlin Android nativo** para NotificationListener, media sessions y bridge con Flutter.
- **LRCLIB** para letras.
- **SQLite (sqflite)** para caché local.
- **MethodChannel/EventChannel** para pasar eventos entre nativo y Flutter.

---

## Apps musicales contempladas

- Spotify → `com.spotify.music`
- YouTube Music → `com.google.android.apps.youtube.music`
- Amazon Music → `com.amazon.mp3`
- Apple Music → `com.apple.android.music`

> Nota: en Android 11+ se declara visibilidad de paquetes en `AndroidManifest` usando `<queries>`, porque Android ya no te deja inspeccionar apps instaladas como en 2016.

---

## Build release (Android)

### APK

```bash
flutter build apk --release
```

Salida esperada:

`build/app/outputs/flutter-apk/app-release.apk`

### AAB

```bash
flutter build appbundle --release
```

---

## Cumplimiento Google Play

Checklist práctico (Data safety + disclosure + riesgos de policy):

- [Google Play Compliance Checklist](docs/google-play-compliance-checklist.md)
- [Privacy Policy](docs/privacy-policy.md)

---

## Firma y secretos (o cómo no autoboicotearte)

La firma release usa `android/key.properties` y keystore local.  
Estos archivos **no** deben ir al repo:

- `android/key.properties`
- `android/app/*.jks`
- `android/app/*.keystore`

Si se filtran, no “pasa nada”: **sí pasa**. Rota credenciales y reemplaza keystore.

---

## TL;DR

SingSync es una app para:

- detectar canciones,
- decidir flujo por tipo de notificación,
- mostrar letra correcta (plain/synced),
- y darte controles útiles sin romper la experiencia.

Todo con un vinil bonito, porque el caos con estética siempre se siente más profesional.
