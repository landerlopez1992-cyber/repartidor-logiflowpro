import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ubicacion_offline_service.dart';

/// Publica GPS del socio en `ubicaciones_repartidores` para el matching de taxis.
class TaxiUbicacionMatchingService {
  TaxiUbicacionMatchingService._();
  static final TaxiUbicacionMatchingService instance =
      TaxiUbicacionMatchingService._();

  SupabaseClient get _db => Supabase.instance.client;

  String? _repartidorId;
  String? _tenantId;

  bool get _esEscritorio {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  Future<({String? repartidorId, String? tenantId})> _ids() async {
    if (_repartidorId != null &&
        _repartidorId!.isNotEmpty &&
        _tenantId != null &&
        _tenantId!.isNotEmpty) {
      return (repartidorId: _repartidorId, tenantId: _tenantId);
    }
    final authId = _db.auth.currentUser?.id;
    if (authId == null) return (repartidorId: null, tenantId: null);
    try {
      final row = await _db
          .from('usuarios')
          .select('id, tenant_id')
          .eq('auth_id', authId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return (repartidorId: null, tenantId: null);
      _repartidorId = row['id']?.toString();
      _tenantId = row['tenant_id']?.toString();
      return (repartidorId: _repartidorId, tenantId: _tenantId);
    } catch (_) {
      return (repartidorId: null, tenantId: null);
    }
  }

  /// [accionAjustes]: `location_service` | `app_settings` | null (sin botón útil).
  Future<({bool ok, String? err, String? accionAjustes})> asegurarPermisoGps()
      async {
    try {
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (!enabled) {
          if (_esEscritorio) {
            return (
              ok: false,
              err:
                  'La ubicación no está disponible en este equipo. Activa viajes desde un teléfono Android o iPhone.',
              accionAjustes: null,
            );
          }
          return (
            ok: false,
            err:
                'El GPS está apagado. Activa la ubicación del teléfono y vuelve a intentar.',
            accionAjustes: 'location_service',
          );
        }
      } catch (_) {
        // En algunos equipos (p. ej. macOS) esta API lanza; seguimos al permiso.
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        if (_esEscritorio) {
          return (
            ok: false,
            err:
                'En este Mac/PC no hay GPS de chofer. Prueba «Buscar viajes» en un teléfono.',
            accionAjustes: null,
          );
        }
        return (
          ok: false,
          err:
              'Necesitas permitir la ubicación para recibir viajes. Ábrela en Ajustes y vuelve a tocar.',
          accionAjustes: 'app_settings',
        );
      }
      if (perm == LocationPermission.deniedForever) {
        if (_esEscritorio) {
          return (
            ok: false,
            err:
                'En este Mac/PC no hay GPS de chofer. Prueba «Buscar viajes» en un teléfono.',
            accionAjustes: null,
          );
        }
        return (
          ok: false,
          err:
              'El permiso de ubicación está bloqueado. Actívalo en Ajustes de la app y vuelve a tocar «Buscar viajes».',
          accionAjustes: 'app_settings',
        );
      }
      return (ok: true, err: null, accionAjustes: null);
    } catch (e) {
      if (_esEscritorio) {
        return (
          ok: false,
          err:
              'La ubicación no está disponible en este equipo. Activa viajes desde un teléfono Android o iPhone.',
          accionAjustes: null,
        );
      }
      return (
        ok: false,
        err:
            'No se pudo verificar la ubicación. Revisa el GPS y los permisos en Ajustes.',
        accionAjustes: 'app_settings',
      );
    }
  }

  /// Abre ajustes del sistema (iOS/Android). Devuelve true si se pudo lanzar.
  static Future<bool> abrirAjustesUbicacion(String? accion) async {
    try {
      if (accion == 'location_service') {
        return await Geolocator.openLocationSettings();
      }
      if (accion == 'app_settings') {
        return await Geolocator.openAppSettings();
      }
      // Por defecto: permisos de la app (más útil en iOS/Android).
      return await Geolocator.openAppSettings();
    } catch (_) {
      try {
        return await Geolocator.openLocationSettings();
      } catch (_) {
        return false;
      }
    }
  }

  /// Lee posición actual. Null si falla.
  /// [skipPermiso] = true si ya se llamó [asegurarPermisoGps].
  Future<Position?> leerPosicion({bool skipPermiso = false}) async {
    try {
      if (!skipPermiso) {
        final perm = await asegurarPermisoGps();
        if (!perm.ok) return null;
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } catch (_) {
        // Timeout / sin fix fresco → última conocida.
        try {
          return await Geolocator.getLastKnownPosition();
        } catch (_) {
          return null;
        }
      }
    } catch (_) {
      return null;
    }
  }

  /// Inserta en `ubicaciones_repartidores` (matching + mapa flota).
  Future<bool> publicarPosicion(Position pos) async {
    final ids = await _ids();
    final rid = ids.repartidorId;
    final tid = ids.tenantId;
    if (rid == null || tid == null) return false;
    try {
      await _db.from('ubicaciones_repartidores').insert({
        'repartidor_id': rid,
        'tenant_id': tid,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'heading': pos.heading,
        'speed': pos.speed,
      }).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      final err = e.toString();
      final sinRed = err.contains('Failed host lookup') ||
          err.contains('SocketException') ||
          err.contains('ClientException') ||
          err.contains('TimeoutException') ||
          err.contains('timed out');
      if (sinRed) {
        await UbicacionOfflineService.encolar(
          repartidorId: rid,
          tenantId: tid,
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          heading: pos.heading,
          speed: pos.speed,
        );
        return true;
      }
      return false;
    }
  }

  /// Permiso + posición + publicación. Obligatoria al activar «Buscando viajes».
  Future<({bool ok, Position? pos, String? err, String? accionAjustes})>
      publicarAhora() async {
    final perm = await asegurarPermisoGps();
    if (!perm.ok) {
      return (
        ok: false,
        pos: null,
        err: perm.err,
        accionAjustes: perm.accionAjustes,
      );
    }

    final pos = await leerPosicion(skipPermiso: true);
    if (pos == null) {
      if (_esEscritorio) {
        return (
          ok: false,
          pos: null,
          err:
              'No hay GPS en este equipo. Para recibir viajes usa la app en un teléfono.',
          accionAjustes: null,
        );
      }
      // Sin fix: a menudo GPS apagado o sin señal; ofrecer ambos caminos.
      var accion = 'location_service';
      try {
        final enabled = await Geolocator.isLocationServiceEnabled();
        if (enabled) accion = 'app_settings';
      } catch (_) {}
      return (
        ok: false,
        pos: null,
        err:
            'No se pudo obtener tu ubicación. Activa el GPS, sal al exterior un momento y vuelve a intentar.',
        accionAjustes: accion,
      );
    }

    final pub = await publicarPosicion(pos);
    if (!pub) {
      // Con posición local válida: permitir activar; matching se sincroniza luego.
      // (ids nulos o RLS) — el chofer igual puede quedar «buscando» en dispositivo.
      final ids = await _ids();
      if (ids.repartidorId == null || ids.tenantId == null) {
        return (
          ok: false,
          pos: pos,
          err:
              'No se pudo identificar tu cuenta para publicar ubicación. Cierra sesión e inicia de nuevo.',
          accionAjustes: null,
        );
      }
      return (
        ok: false,
        pos: pos,
        err:
            'No se pudo enviar tu ubicación. Revisa la conexión e intenta de nuevo.',
        accionAjustes: null,
      );
    }
    return (ok: true, pos: pos, err: null, accionAjustes: null);
  }
}
