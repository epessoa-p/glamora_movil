# Glamora móvil

App Flutter del equipo del salón: **mi agenda, nueva cita, clientes, asistencia y mis comisiones**.
Usa la API `api/v1` de Glamora web (`salon-stetica/routes/api.php`).

Estado y pendientes: [CHECKLIST-APP.md](CHECKLIST-APP.md).

## Ejecutar

```bash
flutter pub get

# Contra producción (por defecto: https://glamora.sczsoft.net/api/v1)
flutter run

# Contra el servidor local (php artisan serve --host=0.0.0.0 --port=8000)
#   emulador Android → 10.0.2.2 es la PC
flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1
#   celular por Wi-Fi → IP de la PC en la red
flutter run --dart-define=API_URL=http://192.168.1.50:8000/api/v1
```

`http://` solo funciona en debug; la versión release exige `https://`.

## Compilar

```bash
flutter doctor --android-licenses     # una sola vez
flutter build apk --release           # build/app/outputs/flutter-apk/app-release.apk
flutter build appbundle --release     # para Google Play
```

Antes de publicar, configura la firma de release (ver la sección 2 del checklist).

## Pruebas

```bash
flutter analyze
flutter test

# Opcional: contra un servidor real de desarrollo (crea una cita y un cliente de prueba)
GLAMORA_LIVE_API=http://127.0.0.1:8000/api/v1 GLAMORA_LIVE_USER=correo GLAMORA_LIVE_PASS=clave \
  flutter test test/live_api_test.dart
```

## Estructura

```
lib/
  main.dart              arranque, tema, idioma y pantalla según la sesión
  config.dart            URL de la API (--dart-define=API_URL)
  session.dart           token, salón activo y perfil (/me)
  api/api_client.dart    HTTP + ApiException (code, message, errores por campo)
  models.dart            modelos de la API
  theme.dart             colores de marca
  util/format.dart       fechas, horas, dinero
  widgets/common.dart    vistas de error/vacío, píldoras, diálogos
  screens/               login, salón, inicio (pestañas), agenda, nueva cita,
                         clientes, asistencia, comisiones, perfil
```

Las reglas de negocio (choques de horario, permisos, comisiones) viven en el
servidor; la app solo muestra lo que responde la API.

Íconos: `dart run flutter_launcher_icons` (configuración en `pubspec.yaml`).
