# Google Play Compliance Checklist (SingSync)

Checklist práctico para publicar SingSync en Google Play con foco en:

- Developer Program Policies
- Data safety
- Notification access disclosure
- Riesgos de propiedad intelectual (letras)

---

## 1) Pre-flight (bloqueantes)

- [x] Verificar que el paquete a publicar sea el final (`applicationId`, nombre app, icono).
  - Verificado en build/config: `applicationId=net.iozamudioa.singsync`, label `SingSync`, icon `@mipmap/ic_launcher`.
- [x] Confirmar `targetSdk` y requisitos vigentes de Play Console.
  - Verificado en APK release reciente: `targetSdkVersion=36`, `sdkVersion(min)=24`, `compileSdkVersion=36`.
  - Estado: OK para requisito actual de Play (mantener revisión en cada nueva policy window).
- [x] Tener URL pública de **Privacy Policy** (HTTPS, accesible sin login).
  - URL: https://github.com/iozamudioa/singsync/blob/main/docs/privacy-policy.md
- [x] Revisar que store listing no implique afiliación oficial con Spotify/YouTube/Apple/Amazon.
  - Estado: revisado, mantener wording neutral en título/short/full description y screenshots.
- [x] Confirmar base legal/licencia para mostrar y compartir letras.
  - LRCLIB expone API pública abierta (sin API key) y recomienda `User-Agent` identificable: https://lrclib.net/docs
  - Código servidor LRCLIB está bajo licencia MIT: https://github.com/tranxuanthang/lrclib
  - Importante: la apertura de API/código NO equivale automáticamente a cesión total de derechos de todas las letras; mantener revisión legal de contenido/territorio y mecanismo de retiro de contenido si aplica.

---

## 2) Permisos y acceso sensible

### A) Notification access (NotificationListenerService)

- [ ] Mostrar pantalla previa (prominent disclosure) antes de enviar al ajuste de acceso.
- [ ] Explicar claramente:
  - Qué se accede: metadatos de notificaciones musicales (título/artista/app origen).
  - Para qué: detectar canción actual y sincronizar vista de letras/controles.
  - Qué NO hace: no vende datos, no usa para publicidad personalizada.
- [ ] El texto de disclosure debe coincidir con Privacy Policy y Data safety.

### B) Almacenamiento multimedia (snapshots)

- [ ] Aclarar en UI y política que las capturas se guardan en galería local del usuario.
- [ ] Aclarar que compartir snapshot es acción explícita del usuario.

---

## 3) Data safety (Play Console) — guía de llenado

> Ajusta esto si cambian flujos o SDKs.

### Datos potencialmente procesados por la app

- App activity (uso de funciones in-app, p.ej. búsqueda de letras)
- Device or other IDs (si Play Services/SDK lo agrega; validar en build final)
- Audio metadata textual desde notificaciones (título/artista), tratado como datos funcionales

### ¿Se comparten datos con terceros?

- [ ] Sí, con proveedor de letras (consulta por red para obtener letras/metadatos).

### Finalidades (marcar según aplique)

- [ ] App functionality
- [ ] Analytics (solo si de verdad integras analytics)
- [ ] Fraud prevention/security (solo si aplica)

### Recolección

- [ ] Datos recolectados para funcionalidad principal.
- [ ] Usuario puede iniciar acciones de guardado/compartir de snapshot manualmente.

### Cifrado en tránsito

- [ ] Sí (HTTPS/TLS).

### Eliminación de datos

- [ ] Documentar cómo borrar datos locales (cache/app data/snapshots).

---

## 4) Texto sugerido — Prominent disclosure (ES)

Usa este texto antes de abrir la pantalla de acceso a notificaciones:

> SingSync necesita acceso a notificaciones para detectar la canción que se está reproduciendo y mostrar letras sincronizadas.  
> Solo leemos metadatos musicales (por ejemplo, título, artista y app origen) cuando hay reproducción.  
> No usamos este acceso para publicidad personalizada ni para vender datos.

Botones sugeridos:

- `Continuar y otorgar acceso`
- `Ahora no`

---

## 5) Texto sugerido — Privacy Policy (resumen mínimo)

Incluye al menos:

1. Qué datos se procesan (metadatos musicales, consultas de letras, snapshots si usuario guarda/comparte).
2. Para qué se usan (funcionalidad principal de la app).
3. Con quién se comparten (proveedor de letras/API, si aplica).
4. Retención (cache local, borrado por usuario).
5. Seguridad (cifrado en tránsito, controles de acceso).
6. Contacto del responsable.

---

## 6) Store listing y metadatos

- [ ] Descripción sin claims engañosos.
- [ ] Sin usar marcas de terceros como si fueran producto oficial.
- [ ] Capturas coherentes con funcionalidad real.
- [ ] Content rating correcto.

---

## 7) QA final antes de enviar

- [ ] App abre sin crash en instalación limpia.
- [ ] Flujo de permiso de notificaciones funciona y es comprensible.
- [ ] Sin pantallas vacías rotas en offline.
- [ ] Guardado/compartido de snapshots funciona en Android 13+.
- [ ] Data safety en consola coincide con comportamiento real.
- [ ] Privacy Policy enlazada en Play Console.

---

## 8) Riesgos principales de esta app (a vigilar)

1. **Propiedad intelectual de letras**: verificar derechos/licencia de distribución/visualización.
2. **Acceso a notificaciones**: disclosure claro + consistencia total entre UI, política y Data safety.

---

## 9) Referencias

- Google Play Policy Center: https://play.google/developer-content-policy/
- User Data policy: https://support.google.com/googleplay/android-developer/answer/9888076
- Permissions policy: https://support.google.com/googleplay/android-developer/answer/12579724
- Deceptive behavior: https://support.google.com/googleplay/android-developer/answer/9888077
- Intellectual property: https://support.google.com/googleplay/android-developer/answer/9888072
- LRCLIB API docs: https://lrclib.net/docs
- LRCLIB repository (MIT): https://github.com/tranxuanthang/lrclib
