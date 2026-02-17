# SingSync

App Flutter para detectar canción actual desde notificaciones y mostrar letra.

## Release signing (Android)

El proyecto ya está configurado para firma release con `android/key.properties`.

### Build firmado

- APK firmado: `flutter build apk --release`
- AAB firmado (recomendado para Play Internal Testing): `flutter build appbundle --release`

### Archivos sensibles

- `android/key.properties`
- `android/app/*.jks`

Estos archivos están ignorados en `.gitignore`.

> Recomendación: antes de publicar, cambia contraseñas y guarda una copia segura de la keystore.
