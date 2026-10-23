# Glamora móvil — Checklist

App Flutter para el **equipo del salón** (estilistas, recepción, gerencia).
Consume la API `api/v1` de Glamora web con tokens de Sanctum.

Leyenda: ✅ hecho · 🟡 parcial / pendiente de verificar · ⬜ por hacer

---

## 1. Servidor (Laravel · `salon-stetica`)

| Estado | Tarea |
|---|---|
| ✅ | Laravel Sanctum instalado (`composer.json`) y `HasApiTokens` en `User` |
| ✅ | Tabla `personal_access_tokens` → `database/actualizar_api_movil.sql` (seguro de reejecutar) |
| ✅ | Middleware `api.company`: salón activo por header `X-Company-Id`, suscripción y modo solo lectura |
| ✅ | Errores JSON con `code` estable en `api/*` |
| ✅ | Reglas de agendar compartidas web + app (`AppointmentService`) |
| ✅ | Hora con zona (`…T14:00Z`) se convierte a la hora del salón |
| ✅ | Endpoints: login, logout, salones, `/me`, agenda, opciones, disponibilidad, crear cita, cambiar estado, clientes (buscar/crear), asistencia (ver/marcar), comisiones |
| ✅ | Límite de 6 intentos de login por minuto |
| ✅ | Tokens con vencimiento de 90 días; cerrar sesión revoca solo ese dispositivo |
| ⬜ | **Producción:** ejecutar `actualizar_api_movil.sql`, `composer install --no-dev`, `php artisan config:clear` y `route:cache` |
| ⬜ | **Producción:** revisar `APP_URL` en `.env` (debe ser `https://glamora.sczsoft.net`; los logos de los salones se arman con esa URL) |
| ⬜ | **Producción:** confirmar que el servidor responde `https://glamora.sczsoft.net/api/v1/auth/login` (la app release no acepta `http://`) |

## 2. Proyecto Flutter

| Estado | Tarea |
|---|---|
| ✅ | Nombre visible **Glamora** (Android e iOS) |
| ✅ | Identificador `net.sczsoft.glamora` (Android `applicationId`/`namespace`, iOS bundle id) |
| ✅ | Permiso `INTERNET` en el manifiesto principal |
| ✅ | `http://` permitido **solo en debug** (para probar contra `php artisan serve`) |
| ✅ | Ícono de la app (Android adaptativo + iOS) desde el isotipo de la marca |
| ✅ | Tema con los colores de Glamora, claro y oscuro |
| ✅ | Español: calendario, selector de hora y fechas (`flutter_localizations` + `intl`) |
| ✅ | URL de la API configurable: `--dart-define=API_URL=…` |
| ✅ | Token guardado cifrado (`flutter_secure_storage`: Keystore / Keychain) |
| ⬜ | Firma de release Android (keystore propio + `key.properties`); hoy firma con la clave de debug |
| ⬜ | Pantalla de arranque nativa con colores de marca (`flutter_native_splash`) |
| ⬜ | Cuenta de desarrollador: Google Play (pago único) / Apple Developer (anual) |

## 3. Funciones de la versión 1

### Sesión
| Estado | Tarea |
|---|---|
| ✅ | Ingreso con correo **o** nombre de usuario (igual que la web) |
| ✅ | Mensajes de error del servidor en español (credenciales, usuario inactivo, sin salón, demasiados intentos, sin conexión) |
| ✅ | Selector de salón si el usuario trabaja en más de uno; cambiar de salón desde Perfil |
| ✅ | Salón con suscripción suspendida → vuelve al selector con el motivo |
| ✅ | Sesión vencida o revocada → vuelve al login con aviso |
| ✅ | Cerrar sesión (revoca el token en el servidor; sin red igual sale) |
| ✅ | Pestañas según permisos del plan y del rol (`abilities` de `/me`) |
| ✅ | Usuario sin ficha de personal: explicación en Perfil |

### Mi agenda
| Estado | Tarea |
|---|---|
| ✅ | Citas del día con hora, cliente, servicio, estado (color) y aviso "fuera de horario" |
| ✅ | Navegar días (flechas, calendario, "Hoy") y deslizar para actualizar |
| ✅ | "Mis citas / Todo el equipo" (solo con permiso de ver la agenda general) |
| ✅ | Detalle de la cita y cambio de estado (propias, o todas con permiso de editar) |
| ✅ | La hora mostrada es la del salón, no la del celular |

### Nueva cita y clientes
| Estado | Tarea |
|---|---|
| ✅ | Formulario: cliente, servicio, profesional, fecha, hora, duración, notas |
| ✅ | La duración se toma del servicio; muestra hora de fin |
| ✅ | Muestra el horario del profesional y sus citas ocupadas de ese día |
| ✅ | Choque con otra cita → error explicado por el servidor |
| ✅ | Fuera de horario → confirmación "Agendar de todos modos" |
| ✅ | Buscar clientes (nombre, teléfono, CI) |
| ✅ | Alta rápida de cliente (nombre + teléfono), también desde el formulario de cita |

### Asistencia
| Estado | Tarea |
|---|---|
| ✅ | Botón grande Marcar entrada / salida con confirmación |
| ✅ | "En turno desde… · llevas…" y horario de hoy |
| ✅ | Resumen del mes: días trabajados, horas, tardanzas, faltas |
| ✅ | Lista de días con estado y marcas |

### Mis comisiones
| Estado | Tarea |
|---|---|
| ✅ | Ganado en el mes, por cobrar, liquidado y propinas |
| ✅ | Detalle por venta (concepto, base × tasa, monto, estado) |
| ✅ | Cambiar de mes |

## 4. Pruebas

| Estado | Tarea |
|---|---|
| ✅ | `flutter analyze` sin observaciones |
| ✅ | `flutter test`: 18 pruebas (cliente HTTP, sesión, modelos, pantallas de login, agenda, nueva cita fuera de horario, asistencia, comisiones) |
| ✅ | Prueba contra servidor real (`test/live_api_test.dart`): login, cliente, cita, choque, agenda, estado, asistencia, comisiones, logout |
| ✅ | API probada con curl: 26/26 |
| ✅ | Compilar APK de debug (`build/app/outputs/flutter-apk/app-debug.apk`) |
| ⬜ | Aceptar licencias del SDK (`flutter doctor --android-licenses`) antes de compilar release |
| ⬜ | Probar en un celular Android real (instalar el APK) |
| ⬜ | Probar en iPhone (requiere una Mac con Xcode) |

## 5. Próximas versiones (ideas)

| Estado | Tarea |
|---|---|
| ⬜ | Notificaciones push (cita nueva, recordatorio, cambio de estado) con Firebase |
| ⬜ | Llamar / WhatsApp al cliente desde la cita (`url_launcher`) |
| ⬜ | Reprogramar cita (arrastrar o editar fecha/hora) |
| ⬜ | Vista semanal de la agenda |
| ⬜ | Ficha del cliente: historial, membresía y puntos |
| ⬜ | Marcar asistencia con ubicación (solo dentro del salón) |
| ⬜ | Modo sin conexión (ver la agenda del día ya cargada) |
| ⬜ | App para clientes del salón (reservar en línea) — producto aparte |
