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

  Future<({String? repartidorId, String? tenantId})> _ids() async {
    if (_repartidorId != null &&
        _repartidorId!.isNotEmpty &&
        _tenantId != null &&
        _tenantId!.isNotEmpty) {
      return (repartidorId: _repartidorId, tenantId: _tenantId);
    }
    final authId = _db.auth.currentUser?.id;
    if (authId == null) return (repartidorId: null, tenantId: null);
    final row = await _db
        .from('usuarios')
        .select('id, tenant_id')
        .eq('auth_id', authId)
        .maybeSingle();
    if (row == null) return (repartidorId: null, tenantId: null);
    _repartidorId = row['id']?.toString();
    _tenantId = row['tenant_id']?.toString();
    return (repartidorId: _repartidorId, tenantId: _tenantId);
  }

  /// Permiso + servicio de ubicación listos.
  Future<({bool ok, String? err})> asegurarPermisoGps() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        return (
          ok: false,
          err: 'Activa el GPS del teléfono para buscar viajes.',
        );
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (
          ok: false,
          err: 'Necesitas permitir la ubicación para recibir viajes.',
        );
      }
      return (ok: true, err: null);
    } catch (e) {
      return (ok: false, err: 'No se pudo verificar la ubicación.');
    }
  }

  /// Lee posición actual. Null si falla.
  Future<Position?> leerPosicion() async {
    try {
      final perm = await asegurarPermisoGps();
      if (!perm.ok) return null;
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
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
      });
      return true;
    } catch (e) {
      final err = e.toString();
      final sinRed = err.contains('Failed host lookup') ||
          err.contains('SocketException') ||
          err.contains('ClientException');
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
  Future<({bool ok, Position? pos, String? err})> publicarAhora() async {
    final perm = await asegurarPermisoGps();
    if (!perm.ok) return (ok: false, pos: null, err: perm.err);
    final pos = await leerPosicion();
    if (pos == null) {
      return (
        ok: false,
        pos: null,
        err: 'No se pudo obtener tu ubicación. Intenta de nuevo.',
      );
    }
    final pub = await publicarPosicion(pos);
    if (!pub) {
      return (
        ok: false,
        pos: pos,
        err: 'No se pudo enviar tu ubicación. Revisa la conexión.',
      );
    }
    return (ok: true, pos: pos, err: null);
  }
}
