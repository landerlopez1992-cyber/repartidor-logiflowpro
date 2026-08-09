import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/repartidor_connectivity.dart';
import '../utils/repartidor_requires_online.dart';
import 'sync_service.dart';
import 'taxi_buscando_prefs.dart';
import 'taxi_vehiculo_catalog.dart';

class TaxiTarifaChofer {
  const TaxiTarifaChofer({
    required this.configurado,
    required this.unidad,
    required this.precioPorUnidadUsd,
    required this.disponible,
    this.capacidadPasajeros = 4,
    this.pasajerosIncluidos = 2,
    this.recargoPorPasajeroUsd = 0,
    this.radioTrabajoM = 150000,
    this.distanciaMaxViajeM,
    this.vehiculoMarca = '',
    this.vehiculoModelo = '',
    this.vehiculoAnio,
    this.vehiculoColor = '',
    this.vehiculoAvatarKey = 'moderno',
    this.vehiculoPlaca = '',
    this.destinoPreferidoTexto = '',
    this.destinoPreferidoLat,
    this.destinoPreferidoLng,
    this.destinoPreferidoRadioM = 25000,
    this.soloHaciaDestinoPreferido = false,
  });

  final bool configurado;
  final String unidad;
  final double precioPorUnidadUsd;
  final bool disponible;
  final int capacidadPasajeros;
  final int pasajerosIncluidos;
  final double recargoPorPasajeroUsd;
  /// Radio máximo desde tu ubicación hasta el origen del pasajero.
  final int radioTrabajoM;
  /// Tope A→B en metros; null = sin límite.
  final int? distanciaMaxViajeM;
  final String vehiculoMarca;
  final String vehiculoModelo;
  final int? vehiculoAnio;
  final String vehiculoColor;
  final String vehiculoAvatarKey;
  final String vehiculoPlaca;
  final String destinoPreferidoTexto;
  final double? destinoPreferidoLat;
  final double? destinoPreferidoLng;
  final int destinoPreferidoRadioM;
  final bool soloHaciaDestinoPreferido;

  static const vacia = TaxiTarifaChofer(
    configurado: false,
    unidad: 'km',
    precioPorUnidadUsd: 0,
    disponible: false,
  );

  factory TaxiTarifaChofer.fromJson(Map<String, dynamic> m) {
    return TaxiTarifaChofer(
      configurado: m['configurado'] == true,
      unidad: (m['unidad']?.toString() ?? 'km').toLowerCase() == 'mi' ? 'mi' : 'km',
      precioPorUnidadUsd:
          (m['precio_por_unidad_usd'] as num?)?.toDouble() ?? 0,
      disponible: m['disponible'] == true,
      capacidadPasajeros: (m['capacidad_pasajeros'] as num?)?.toInt() ?? 4,
      pasajerosIncluidos: (m['pasajeros_incluidos'] as num?)?.toInt() ?? 2,
      recargoPorPasajeroUsd:
          (m['recargo_por_pasajero_usd'] as num?)?.toDouble() ?? 0,
      radioTrabajoM: (m['radio_trabajo_m'] as num?)?.toInt() ?? 150000,
      distanciaMaxViajeM: (m['distancia_max_viaje_m'] as num?)?.toInt(),
      vehiculoMarca: m['vehiculo_marca']?.toString() ?? '',
      vehiculoModelo: m['vehiculo_modelo']?.toString() ?? '',
      vehiculoAnio: (m['vehiculo_anio'] as num?)?.toInt(),
      vehiculoColor: m['vehiculo_color']?.toString() ?? '',
      vehiculoAvatarKey: m['vehiculo_avatar_key']?.toString() ??
          TaxiVehiculoCatalog.resolveAvatarKey(
            marca: m['vehiculo_marca']?.toString() ?? '',
            anio: (m['vehiculo_anio'] as num?)?.toInt(),
            capacidad: (m['capacidad_pasajeros'] as num?)?.toInt() ?? 4,
          ),
      vehiculoPlaca: m['vehiculo_placa']?.toString() ?? '',
      destinoPreferidoTexto: m['destino_preferido_texto']?.toString() ?? '',
      destinoPreferidoLat: (m['destino_preferido_lat'] as num?)?.toDouble(),
      destinoPreferidoLng: (m['destino_preferido_lng'] as num?)?.toDouble(),
      destinoPreferidoRadioM:
          (m['destino_preferido_radio_m'] as num?)?.toInt() ?? 25000,
      soloHaciaDestinoPreferido: m['solo_hacia_destino_preferido'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'configurado': configurado,
        'unidad': unidad,
        'precio_por_unidad_usd': precioPorUnidadUsd,
        'disponible': disponible,
        'capacidad_pasajeros': capacidadPasajeros,
        'pasajeros_incluidos': pasajerosIncluidos,
        'recargo_por_pasajero_usd': recargoPorPasajeroUsd,
        'radio_trabajo_m': radioTrabajoM,
        'distancia_max_viaje_m': distanciaMaxViajeM,
        'vehiculo_marca': vehiculoMarca,
        'vehiculo_modelo': vehiculoModelo,
        'vehiculo_anio': vehiculoAnio,
        'vehiculo_color': vehiculoColor,
        'vehiculo_avatar_key': vehiculoAvatarKey,
        'vehiculo_placa': vehiculoPlaca,
        'destino_preferido_texto': destinoPreferidoTexto,
        'destino_preferido_lat': destinoPreferidoLat,
        'destino_preferido_lng': destinoPreferidoLng,
        'destino_preferido_radio_m': destinoPreferidoRadioM,
        'solo_hacia_destino_preferido': soloHaciaDestinoPreferido,
      };
}

class TaxiTarifasChoferService {
  TaxiTarifasChoferService._();
  static final TaxiTarifasChoferService instance = TaxiTarifasChoferService._();

  static const _cachePrefix = 'cache_taxi_tarifa_chofer_';

  SupabaseClient get _db => Supabase.instance.client;

  String? get _uid => _db.auth.currentUser?.id;

  Future<TaxiTarifaChofer?> loadCached() async {
    try {
      final uid = _uid;
      if (uid == null) return null;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_cachePrefix$uid');
      if (raw == null || raw.isEmpty) return null;
      return TaxiTarifaChofer.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCached(TaxiTarifaChofer t) async {
    try {
      final uid = _uid;
      if (uid == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_cachePrefix$uid', jsonEncode(t.toJson()));
    } catch (e) {
      print('⚠️ saveCached tarifa: $e');
    }
  }

  /// Offline-first: caché al instante; red con timeout corto (nunca cuelga).
  Future<TaxiTarifaChofer> get({bool forceNetwork = false}) async {
    final cached = await loadCached();
    if (!forceNetwork && repartidorSinInternet()) {
      return cached ?? TaxiTarifaChofer.vacia;
    }
    try {
      final res = await _db
          .rpc('taxi_tarifa_chofer_get')
          .timeout(const Duration(seconds: 5));
      if (res is! Map) {
        return cached ?? TaxiTarifaChofer.vacia;
      }
      final t = TaxiTarifaChofer.fromJson(Map<String, dynamic>.from(res));
      await saveCached(t);
      return t;
    } catch (e) {
      print('⚠️ taxi_tarifa get → caché: $e');
      return cached ?? TaxiTarifaChofer.vacia;
    }
  }

  /// Prefetch al boot (con internet).
  Future<void> prefetchAlAbrirApp() async {
    if (repartidorSinInternet()) return;
    try {
      await get(forceNetwork: true);
    } catch (_) {}
  }

  Future<({bool ok, String? err})> guardar({
    required String unidad,
    required double precioPorUnidadUsd,
    int capacidadPasajeros = 4,
    int pasajerosIncluidos = 2,
    double recargoPorPasajeroUsd = 0,
    int radioTrabajoM = 150000,
    int? distanciaMaxViajeM,
    String? vehiculoMarca,
    String? vehiculoModelo,
    int? vehiculoAnio,
    String? vehiculoColor,
    String? vehiculoPlaca,
  }) async {
    if (repartidorSinInternet()) {
      return (
        ok: false,
        err: 'Sin internet: no se puede guardar la tarifa ahora.',
      );
    }
    try {
      final res = await _db
          .rpc(
            'taxi_tarifa_chofer_upsert',
            params: {
              'p_unidad': unidad,
              'p_precio_por_unidad_usd': precioPorUnidadUsd,
              'p_capacidad_pasajeros': capacidadPasajeros.clamp(1, 20),
              'p_pasajeros_incluidos': pasajerosIncluidos.clamp(1, 20),
              'p_recargo_por_pasajero_usd': recargoPorPasajeroUsd.clamp(0, 500),
              'p_radio_trabajo_m': radioTrabajoM.clamp(5000, 500000),
              'p_distancia_max_viaje_m': distanciaMaxViajeM,
              'p_vehiculo_marca': vehiculoMarca,
              'p_vehiculo_modelo': vehiculoModelo,
              'p_vehiculo_anio': vehiculoAnio,
              'p_vehiculo_color': vehiculoColor,
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res is Map && res['ok'] == true) {
        try {
          await _db.rpc(
            'taxi_tarifa_chofer_set_placa',
            params: {'p_placa': (vehiculoPlaca ?? '').trim()},
          );
        } catch (_) {}
        final refreshed = await get(forceNetwork: true);
        await saveCached(refreshed);
        return (ok: true, err: null);
      }
      final err = res is Map
          ? (res['error']?.toString() ?? 'No se pudo guardar')
          : 'No se pudo guardar';
      return (ok: false, err: err);
    } catch (e) {
      return (ok: false, err: 'Sin conexión al guardar: $e');
    }
  }

  /// Destino preferido / filtro «solo hacia esa zona».
  Future<({bool ok, String? err})> setDestinoPreferido({
    String? texto,
    double? lat,
    double? lng,
    int radioM = 25000,
    bool solo = false,
  }) async {
    if (repartidorSinInternet()) {
      return (ok: false, err: 'Sin internet: no se puede guardar el destino.');
    }
    try {
      final res = await _db
          .rpc(
            'taxi_tarifa_chofer_set_destino_preferido',
            params: {
              'p_texto': texto,
              'p_lat': lat,
              'p_lng': lng,
              'p_radio_m': radioM.clamp(5000, 200000),
              'p_solo': solo,
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res is Map && res['ok'] == true) {
        final refreshed = await get(forceNetwork: true);
        await saveCached(refreshed);
        return (ok: true, err: null);
      }
      final err = res is Map
          ? (res['error']?.toString() ?? 'No se pudo guardar el destino')
          : 'No se pudo guardar el destino';
      return (ok: false, err: err);
    } catch (e) {
      return (ok: false, err: 'Sin conexión al guardar destino: $e');
    }
  }

  /// Actualiza disponibilidad en BD. Sin red: encola y devuelve ok (caché local manda).
  Future<({bool ok, String? err, bool queued})> setDisponible(bool value) async {
    try {
      if (RepartidorConnectivity.online.value == false ||
          !SyncService().isOnline) {
        await TaxiBuscandoPrefs.marcarPendienteSyncDisponible(value);
        return (ok: true, err: null, queued: true);
      }
      final res = await _db
          .rpc(
            'taxi_chofer_set_disponible',
            params: {'p_disponible': value},
          )
          .timeout(const Duration(seconds: 4));
      if (res is Map && res['ok'] == true) {
        await TaxiBuscandoPrefs.limpiarPendienteSyncDisponible();
        final cached = await loadCached();
        if (cached != null) {
          await saveCached(
            TaxiTarifaChofer(
              configurado: cached.configurado,
              unidad: cached.unidad,
              precioPorUnidadUsd: cached.precioPorUnidadUsd,
              disponible: value,
              capacidadPasajeros: cached.capacidadPasajeros,
              pasajerosIncluidos: cached.pasajerosIncluidos,
              recargoPorPasajeroUsd: cached.recargoPorPasajeroUsd,
              radioTrabajoM: cached.radioTrabajoM,
              distanciaMaxViajeM: cached.distanciaMaxViajeM,
              vehiculoMarca: cached.vehiculoMarca,
              vehiculoModelo: cached.vehiculoModelo,
              vehiculoAnio: cached.vehiculoAnio,
              vehiculoColor: cached.vehiculoColor,
              vehiculoAvatarKey: cached.vehiculoAvatarKey,
              vehiculoPlaca: cached.vehiculoPlaca,
              destinoPreferidoTexto: cached.destinoPreferidoTexto,
              destinoPreferidoLat: cached.destinoPreferidoLat,
              destinoPreferidoLng: cached.destinoPreferidoLng,
              destinoPreferidoRadioM: cached.destinoPreferidoRadioM,
              soloHaciaDestinoPreferido: cached.soloHaciaDestinoPreferido,
            ),
          );
        }
        // Red de seguridad: si el GPS acaba de publicarse tras activar,
        // un segundo aviso cubre carreras que ya estaban buscando.
        if (value) {
          unawaited(avisarSolicitudesPendientes());
        }
        return (ok: true, err: null, queued: false);
      }
      final msg = res is Map
          ? (res['mensaje']?.toString() ??
              res['error']?.toString() ??
              'No se pudo actualizar')
          : 'No se pudo actualizar';
      final lower = msg.toLowerCase();
      final esNegocio = lower.contains('tarifa') ||
          lower.contains('fianza') ||
          lower.contains('configur') ||
          lower.contains('suspend');
      if (esNegocio) {
        return (ok: false, err: msg, queued: false);
      }
      await TaxiBuscandoPrefs.marcarPendienteSyncDisponible(value);
      return (ok: true, err: null, queued: true);
    } catch (e) {
      print('⚠️ setDisponible offline/timeout → cola: $e');
      await TaxiBuscandoPrefs.marcarPendienteSyncDisponible(value);
      return (ok: true, err: null, queued: true);
    }
  }

  /// Empuja ofertas de viajes que siguen en buscando_chofer (mismo tenant).
  /// Útil tras publicar GPS si el chofer ya estaba disponible.
  Future<void> avisarSolicitudesPendientes() async {
    try {
      if (RepartidorConnectivity.online.value == false ||
          !SyncService().isOnline) {
        return;
      }
      await _db
          .rpc(
            'taxi_chofer_avisar_solicitudes_pendientes',
            params: {'p_chofer_usuario_id': null},
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      print('⚠️ avisarSolicitudesPendientes: $e');
    }
  }

  Future<void> flushPendienteDisponibleSiHay() async {
    try {
      final pendiente = await TaxiBuscandoPrefs.pendienteSyncDisponible();
      if (pendiente == null) return;
      final res = await setDisponible(pendiente);
      if (res.ok && !res.queued) {
        print('✅ disponible sincronizado tras offline: $pendiente');
      }
    } catch (e) {
      print('⚠️ flushPendienteDisponibleSiHay: $e');
    }
  }

  Future<void> reafirmarDisponibleSiActivoLocal() async {
    try {
      await flushPendienteDisponibleSiHay();
      final local = await TaxiBuscandoPrefs.esActivo();
      if (!local) return;
      final tarifa = await get();
      if (!tarifa.configurado) return;
      if (!tarifa.disponible) {
        await setDisponible(true);
      }
    } catch (_) {}
  }
}
