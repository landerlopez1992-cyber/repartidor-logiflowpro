# Repartidor VolonexPro+

App exclusiva para repartidores de VolonexPro+. Esta aplicación está diseñada solo para dispositivos móviles (Android e iOS) y se conecta a la misma base de datos Supabase que la aplicación principal.

## Características

- ✅ Autenticación exclusiva para repartidores
- ✅ Gestión de órdenes de entrega
- ✅ Rastreo de ubicación en tiempo real
- ✅ Notificaciones push
- ✅ Ruta optimizada para entregas
- ✅ Escaneo de QR para confirmación de entrega
- ✅ Firma digital de recibos
- ✅ Modo offline con sincronización
- ✅ Chat con soporte

## Estructura del Proyecto

```
lib/
├── config/
│   ├── supabase_config.dart      # Configuración de Supabase
│   └── app_colors.dart           # Colores de la aplicación
├── models/
│   └── orden.dart                # Modelo de datos de órdenes
├── screens/
│   ├── login_repartidor_screen.dart
│   ├── repartidor_mobile_screen.dart
│   ├── repartidor_perfil_screen.dart
│   ├── chat_repartidor_lista_screen.dart
│   ├── detalle_orden_screen.dart
│   ├── notificaciones_repartidor_screen.dart
│   ├── qr_scanner_fullscreen.dart
│   ├── aviso_ubicacion_destacado_screen.dart
│   ├── aviso_ubicacion_segundo_plano_screen.dart
│   └── ruta_optimizada_repartidor_screen.dart
├── services/
│   ├── configuracion_service.dart
│   ├── email_service.dart
│   ├── sync_service.dart
│   ├── orden_cache_service.dart
│   ├── shorebird_service.dart
│   ├── goodbarber_sync_service.dart
│   ├── paises_service.dart
│   └── repartidor_perfil_cache_service.dart
└── main.dart
```

## Configuración

### Supabase

La aplicación utiliza la misma base de datos Supabase que la aplicación principal. Las credenciales están configuradas en `lib/config/supabase_config.dart`.

### Plataformas Soportadas

- ✅ Android
- ✅ iOS
- ❌ Web (no soportado)
- ❌ Windows (no soportado)

## Requisitos

- Flutter SDK 3.9.0 o superior
- Dart SDK 3.9.0 o superior
- Cuenta de Supabase configurada
- Dispositivo Android o iOS para pruebas

## Instalación

1. Clonar o descargar el proyecto
2. Ejecutar `flutter pub get` para instalar dependencias
3. Configurar las credenciales de Supabase en `lib/config/supabase_config.dart`
4. Ejecutar `flutter run` para iniciar la aplicación

## Build

### Android
```bash
flutter build apk --release
# o
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

## Notas Importantes

- Esta aplicación es exclusiva para repartidores. Solo usuarios con rol "REPARTIDOR" pueden acceder.
- La aplicación requiere permisos de ubicación para funcionar correctamente.
- Se debe mostrar el aviso de ubicación destacado antes de solicitar permisos (requisito de Google Play).

## Licencia

Propietario - VolonexPro+

