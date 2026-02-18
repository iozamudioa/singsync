# SingSync

SingSync es una app Flutter para Android que detecta la canción actual desde notificaciones del sistema y muestra su letra en tiempo real.

## ¿Qué hace la app?

- Escucha dos fuentes de now playing:
	- notificaciones de reproductores multimedia (`media_player`)
	- Pixel Now Playing (`pixel_now_playing`)
- Muestra portada en vinil (usa metadata del reproductor y fallback a búsqueda de artwork cuando falta).
- Controla reproducción para la sesión activa (`prev / play-pause / next`) cuando la fuente es reproductor.
- Busca letra en LRCLIB y alterna tipo de letra por fuente:
	- `media_player`: prioriza letra sincronizada (LRC) con soporte de seek por línea.
	- `pixel_now_playing`: prioriza letra plain.
- Cachea letras y metadata localmente para reducir búsquedas repetidas.
- Permite abrir apps musicales compatibles y, según contexto, abrir app o buscar canción.

## Flujo funcional

### 1) Fuente: `media_player`

- UI de reproducción activa con controles multimedia.
- Botón del reproductor activo.
- Letra sincronizada cuando está disponible.
- Si no llega portada desde metadata, intenta resolverla por búsqueda.

### 2) Fuente: `pixel_now_playing`

- UI enfocada en abrir canción en apps instaladas.
- Letra plain prioritaria.
- Si luego se detecta sesión real de reproductor, la app migra a flujo `media_player` y utiliza letra synced.

### 3) Sin reproducción activa

- Pantalla de espera con vinil vacío.
- Mensaje contextual según permisos.
- Botones de apps musicales instaladas (solo las detectadas en el dispositivo).

## Requisitos

- Android con acceso a notificaciones concedido para SingSync.
- Conexión a internet para consultas LRCLIB y metadata.

## Compatibilidad de apps musicales

Actualmente se detectan/usan estos paquetes:

- Spotify: `com.spotify.music`
- YouTube Music: `com.google.android.apps.youtube.music`
- Amazon Music: `com.amazon.mp3`
- Apple Music: `com.apple.android.music`

## Build release (Android)

### APK

`flutter build apk --release`

Salida:

`build/app/outputs/flutter-apk/app-release.apk`

### AAB

`flutter build appbundle --release`

## Firma y archivos sensibles

La firma release usa `android/key.properties`.

Archivos sensibles ignorados por git:

- `android/key.properties`
- `android/app/*.jks`
- `android/app/*.keystore`

> Recomendación: resguarda la keystore y rota credenciales si migras el proyecto a otro entorno.
