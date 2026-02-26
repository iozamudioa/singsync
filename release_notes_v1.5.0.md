## 🚀 SingSync v1.5.0+7 (sí, sigue vivo y ahora también instala en todos)

Porque aparentemente “que funcione” era solo el mínimo. Ahora también tiene que comportarse bien en landscape, no inventar artistas, y desplegar en varios dispositivos sin drama existencial.

### ✅ Notas ES
1. 🎧 **Listener nativo renombrado y ordenado**
   `PixelNowPlayingNotificationListener` pasó a `NowPlayingNotificationListener` (archivo, clase y referencias). Porque si ya escucha más que Pixel, el nombre anterior era básicamente desinformación.

2. 🧠 **Separación real de parsing Pixel vs media player**
   El flujo `media_player` ya no usa heurísticas “creativas” de Pixel para partir título/artista. Resultado: menos joyas como “Son - Four”.

3. 🖼️ **Render snapshot consistente entre preview y guardado**
   La transparencia y el look final respetan el preview (sí, como debería haber sido desde el inicio del universo).

4. 🌗 **Iconografía de tema corregida**
   En preview: claro muestra luna, oscuro muestra sol. Lo obvio, pero ahora también lo implementado.

5. 🧭 **Animación de guardado al ícono de galería**
   El “fly” de snapshot ahora apunta al destino correcto en navbar (galería), no al ícono equivocado por nostalgia.

6. 🧩 **Layout normal landscape en 3 columnas**
   Ahora es `40/40/20`: vinil | letras | controles. Más legible, más controlable, menos Tetris visual.

7. 📌 **Botones de copiar/compartir/foto reubicados**
   En landscape normal se movieron a la esquina inferior derecha de la columna de controles, en vez de encima del bloque de letras.

8. 🎛️ **Controles prev/play/next escalados por modo**
   Se unificaron tamaños para normal y se ampliaron en extended landscape. Porque dedos humanos > targets microscópicos.

9. 📲 **Deploy Android multi-dispositivo por ADB**
   El script `scripts/deploy-android-release.ps1` ahora instala/valida/lanza en todos los `device` conectados (USB/wireless), no solo en el “elegido por azar”.

---

## 🇺🇸 EN Notes (same release, same pain)

### ✅ Highlights
1. 🎧 **Native listener cleanup and rename**
   `PixelNowPlayingNotificationListener` is now `NowPlayingNotificationListener` everywhere (class/file/references). Naming now matches reality.

2. 🧠 **Strict parsing split: Pixel vs media player**
   `media_player` flow no longer reuses Pixel heuristics for title/artist splitting. Fewer absurd parses, more actual metadata trust.

3. 🖼️ **Snapshot preview/output visual parity**
   Final exported snapshot now matches preview transparency and styling.

4. 🌗 **Theme toggle icon semantics fixed**
   Light preview shows moon, dark preview shows sun. Yes, finally aligned with user expectation.

5. 🧭 **Save-flight animation retargeted to gallery nav icon**
   Snapshot animation now lands on gallery destination instead of unrelated controls.

6. 🧩 **Collapsed landscape switched to 3-column layout**
   `40/40/20`: vinyl | lyrics panel | controls column for cleaner structure.

7. 📌 **Copy/share/camera controls moved**
   In normal landscape, action buttons now sit at bottom-right of controls column instead of overlaying lyrics.

8. 🎛️ **Transport controls resized by mode**
   Normal modes aligned to larger sizing baseline; extended landscape bumped further for better touch ergonomics.

9. 📲 **ADB multi-device deployment script**
   `deploy-android-release.ps1` now loops all active ADB `device` targets for install/validate/launch.

---

### 🛠️ Technical extras
- Version updated to **1.5.0+7**.
- Tag/release aligned to `v1.5.0`.
- Includes current Kotlin/Flutter layout and deployment pipeline updates.

Gracias / Thanks for stress-testing SingSync in real-world chaos.
