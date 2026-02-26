## 🎉 SingSync v1.4.0+6 (sí, sobrevivió a los modales)

Porque aparentemente no era suficiente con generar snapshots: ahora también tenían que ser editables, coherentes y no romperse al rotar la pantalla. Qué exigentes. 😌

### ✅ Qué trae este release (ES)
1. 🧩 **Custom Snapshot de verdad**  
   Ya no es “toma lo que salió”. Ahora puedes ajustar el resultado como una persona con estándares.

2. ✍️🎨 **Flujo de selección de letra + color**  
   Primero eliges líneas, luego ajustas color/tema/fondo en preview. Sí, orden lógico. Sí, nos tomó varias iteraciones.

3. 🖼️ **Extracción de color desde carátula**  
   El snapshot usa color dominante del artwork para que el resultado combine y no parezca accidente cromático.

4. 💾 **Editar snapshot de galería reemplazando el archivo original**  
   Se acabó eso de “editar” y terminar con otro archivo nuevo. Editar ahora edita. Revolucionario.

5. 🖼️♻️ **Refresh real de miniaturas en galería tras editar**  
   Invalidación de caché y recarga para que veas cambios al instante, no en la próxima encarnación.

6. 💿 **Scrub del vinil más fluido + haptics mejor calibrado**  
   Menos lag subjetivo, más control fino. Tus dedos lo notan, y tu paciencia también.

7. 🛠️ **Unificación del renderer de snapshots**  
   Una sola ruta de render (`SnapshotRenderer.buildPng`) para evitar diferencias mágicas entre flujos.

8. 📐 **Preview modal mejorado en portrait/landscape**  
   Layout más consistente, controles reorganizados y menos caos espacial cuando giras el dispositivo.

9. 🌍 **i18n real en selector de líneas (ES/EN)**  
   Títulos y textos sin hardcodes; internacionalización como debería ser, no como “luego lo vemos”.

10. 🔁 **Flujo desacoplado de selección de líneas vs preview**  
   Estado de líneas seleccionado persiste fuera del preview para que volver siempre recupere selección previa.

11. ✅ **Compatibilidad con navegación de back moderna (`PopScope`)**  
   Menos advertencias, mejor soporte para back predictivo, más paz mental en `flutter analyze`.

---

## 🇺🇸 English Notes (same release, same drama)

### ✅ What’s in this release (EN)
1. 🧩 **Actual Custom Snapshot**  
   Not just “here’s whatever got rendered.” You can now customize the snapshot like a civilized human.

2. ✍️🎨 **Lyric-line + color selection flow**  
   Pick lines first, then tune color/theme/background in preview. Yes, this is the logical order. Yes, it took work.

3. 🖼️ **Artwork color extraction**  
   Snapshot styling now pulls dominant album-art colors so outputs look intentional instead of randomly generated.

4. 💾 **Gallery edit now replaces original file**  
   “Edit” no longer creates another file clone. Editing now actually edits. Groundbreaking.

5. 🖼️♻️ **Real thumbnail refresh after edits**  
   Cache invalidation + reload so changes appear immediately, not eventually.

6. 💿 **Smoother vinyl scrub + better haptic timing**  
   Less perceived lag, tighter control, and fewer “why is this fighting me?” moments.

7. 🛠️ **Unified snapshot renderer path**  
   One render pipeline (`SnapshotRenderer.buildPng`) to avoid drift between flows.

8. 📐 **Improved preview modal in portrait/landscape**  
   Cleaner layout, better control placement, fewer rotation-related UX surprises.

9. 🌍 **Proper i18n in line-selection UI (ES/EN)**  
   Hardcoded strings removed where it matters. Localization done like adults.

10. 🔁 **Decoupled line-selection state from preview modal**  
   Selected lines persist outside preview so returning always restores previous selection.

11. ✅ **Modern back handling with `PopScope`**  
   Better compatibility with predictive back and cleaner analyzer output.

---

### 🛠️ Extras técnicos / Technical extras
- Versionado actualizado a **1.4.0+6**.
- APK release generado y adjuntado.
- Código fuente empaquetado automáticamente por GitHub.

### 📦 Asset principal / Main asset
- `app-release.apk`

Gracias por usar SingSync.  
Seguiremos mejorando… y tomando decisiones “rápidas” que después convertimos en arquitectura oficial. 🚀
