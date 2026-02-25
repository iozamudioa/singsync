# SingSync

Bienvenido a **SingSync** 🎵💿: una app para detectar lo que suena, traer letras, mostrar un vinil bonito y fingir que todo esto fue una decisión serena, lineal y madura desde el día uno.  
Spoiler: hubo café, bugs y decisiones "temporales" que claramente nunca se volvieron permanentes. 😌

## ⭐ Enfoque principal: Google Pixel + Pixel Now Playing

Sí, **SingSync funciona con Pixel Now Playing** y este no es un detalle escondido: es parte central del producto.  
Si usas Pixel, aquí es donde la app brilla más fuerte 🔥:

- Integración con la detección ambiental de canciones de Pixel.
- Flujo dedicado para fuente `pixel_now_playing`.
- Letra en modo `plain` priorizada para este escenario.
- Transición inteligente a flujo `media_player` cuando aparece sesión activa real.

En resumen: no solo "también" funciona en Pixel… **está diseñado para aprovecharlo**. 🚀

Y si no tienes Pixel, no te preocupes: también funciona en cualquier Android compatible (**Android 7.0 / API 24 o superior**).  
Así que sí, Pixel es el protagonista… pero nadie se queda fuera de la fiesta. 🎉

> Idioma obligatorio del proyecto: **español**.  
> ¿Quieres leerlo en inglés? Sí, también somos internacionales: [README.en.md](README.en.md) 🌍

---

## ¿Qué hace SingSync?

SingSync escucha el *now playing* en Android y decide el flujo según la fuente:

1. `media_player` → sesión multimedia real activa (cuando todo coopera).
2. `pixel_now_playing` → detección ambiental del sistema, especialmente útil en **Google Pixel** (cuando Android quiere ser detective privado).

Con eso decide qué mostrar y cómo comportarse (porque sí, el contexto importa, aunque a veces queramos ignorarlo con elegancia y fe ciega). 🧠✨

---

## Funcionalidades principales

### Novedades v1.4.0 (sí, salió)

- **Custom snapshot**: ahora el snapshot no es “lo que tocó”, es lo que realmente querías armar.
- **Flujo para seleccionar letra y color**: primero eliges líneas, luego color/estilo en preview, porque improvisar en producción ya lo hicimos suficiente.
- **Extracción de color desde carátula**: la app toma color dominante del artwork para que todo combine sin que tengas que jugar a diseñador a las 2 a.m.

### Reproducción y letras

- Detección de canción actual por notificaciones/sesión multimedia 🔎.
- Compatibilidad destacada con **Pixel Now Playing** para usuarios Google Pixel 📱.
- Controles multimedia cuando aplica: `prev / play-pause / next` ⏮️⏯️⏭️.
- Letras desde LRCLIB con dos variantes:
  - **plain** (ideal para flujo ambiental)
  - **synced/LRC** (ideal para sesión activa del reproductor)
- Búsqueda manual de letras y selección de coincidencias, porque a veces el automático se toma vacaciones. 🫠

### UI y experiencia

- Vinil con portada, fallback inteligente por metadata y modo expandido 💿.
- Snapshot/imagen para compartir de forma rápida 📸.
- Feedback superior con overlay (sin pelearse con la navbar, por fin) ✅.
- Teclado mejor controlado en búsquedas (sin encoger fondos “porque sí”, milagrosamente). 🙏

### Galería y favoritos

- Galería de snapshots guardados con:
  - búsqueda por canción/artista,
  - agrupación por **Hoy / Esta semana / Anteriores**,
  - preview, compartir y eliminar.
- Biblioteca “Mis canciones” con búsqueda y gestión rápida de favoritos ❤️.

### Sleep Timer (nuevo en 1.3.1+5)

- Temporizador por:
  1. **Duración** (tiempo)
  2. **Número de canciones**
- Modal de configuración + modal de estado activo ⏱️.
- Indicador activo en header 💤.
- Finalización simplificada: **“Temporizador completo.”**
- Intento nativo de apagar pantalla al completar (*best effort*; Android decide si coopera y si los astros se alinean). 🌙

### Integración de apps de música

- Apps contempladas:
  - Spotify → `com.spotify.music`
  - YouTube Music → `com.google.android.apps.youtube.music`
  - Amazon Music → `com.amazon.mp3`
  - Apple Music → `com.apple.android.music`
- Para reproductores no reconocidos, intenta cargar ícono real de la app desde Android nativo (sí, hasta para los rebeldes). 🎯

---

## Stack técnico

- **Flutter** (UI + estado)
- **Kotlin Android nativo** (NotificationListener, media session, bridges)
- **LRCLIB** (fuente de letras)
- **SQLite / sqflite** (caché local)
- **MethodChannel / EventChannel** (Flutter ↔ Android)

Porque claramente una sola capa no era suficiente para divertirnos ni para complicarnos con estilo. 🧩

---

## Localización (i18n)

- Idiomas activos: **Español** y **English** 🌍.
- Se eliminaron hardcoded strings en los flujos tocados recientemente (sí, crecimos).
- Archivos base:
  - `lib/l10n/app_es.arb`
  - `lib/l10n/app_en.arb`

Si agregas UI nueva y no la internacionalizas, el linter no te va a abrazar… y nosotros tampoco. 🤝❌

---

## Build y release (Android)

### Build manual

```bash
flutter build apk --release
```

APK esperado:

`build/app/outputs/flutter-apk/app-release.apk`

### Script de despliegue (recomendado)

Usa:

`scripts/deploy-android-release.ps1`

Este script corre análisis, build, validación de versión/timestamp, instalación y lanzamiento.  
Sí, es más estricto que ese “yo lo probé en mi cel y todo bien”. 🚨

### AAB

```bash
flutter build appbundle --release
```

---

## Cumplimiento Google Play

- [Google Play Compliance Checklist](docs/google-play-compliance-checklist.md)
- [Privacy Policy](docs/privacy-policy.md)

---

## Firma y secretos

La firma release usa `android/key.properties` + keystore local.

**No** subas estos archivos al repo:

- `android/key.properties`
- `android/app/*.jks`
- `android/app/*.keystore`

Si se filtran, no es “detallito”: rota credenciales y reemplaza keystore. Sí, duele. 🔥

---

## Estado actual

- Versión actual: **1.4.0+6**
- Análisis estático: **sin issues** (`flutter analyze --no-fatal-infos --no-fatal-warnings`)

Milagro temporal, disfrútalo antes de abrir el próximo PR y convocar a los bugs de regreso. 🫡

---

## TL;DR

SingSync detecta canciones, trae letras correctas según contexto, ofrece controles útiles, snapshots, favoritos, temporizador de apagado y una UI de vinil que se ve mejor de lo que estrictamente necesita verse.

Porque cuando el caos tiene estética, parece estrategia. 🎭
