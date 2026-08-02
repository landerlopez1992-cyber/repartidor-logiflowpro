import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/repartidor_connectivity.dart';
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
    );
  }
}

class TaxiTarifasChoferService {
  TaxiTarifasChoferService._();
  static final TaxiTarifasChoferService instance = TaxiTarifasChoferService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<TaxiTarifaChofer> get() async {
    final res = await _db.rpc('taxi_tarifa_chofer_get');
    if (res is! Map) {
      return const TaxiTarifaChofer(
        configurado: false,
        unidad: 'km',
        precioPorUnidadUsd: 0,
        disponible: false,
      );
    }
    return TaxiTarifaChofer.fromJson(Map<String, dynamic>.from(res));
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
  }) async {
    final res = await _db.rpc(
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
    );
    if (res is Map && res['ok'] == true) return (ok: true, err: null);
    final err = res is Map
        ? (res['error']?.toString() ?? 'No se pudo guardar')
        : 'No se pudo guardar';
    return (ok: false, err: err);
  }

  /// Actualiza disponibilidad en BD. Sin red: encola y devuelve ok (caché local manda).
  Future<({bool ok, String? err, bool queued})> setDisponible(bool value) async {
    try {
      if (RepartidorConnectivity.online.value == false) {
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
        return (ok: true, err: null, queued: false);
      }
      final msg = res is Map
          ? (res['mensaje']?.toString() ??
              res['error']?.toString() ??
              'No se pudo actualizar')
          : 'No se pudo actualizar';
      // Error de negocio (tarifa, fianza…): no encolar como si fuera éxito.
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

  /// Empuja a BD el estado local / pendiente cuando vuelve internet.
  Future<void> flushPendienteDisponibleSiHay() async {
    try {
      final pendiente = await TaxiBuscandoPrefs.pendienteSyncDisponible();
      final local = await TaxiBuscandoPrefs.esActivo();
      final desired = pendiente ?? local;
      // Si no hay pendiente y local coincide con lo esperado, igual reafirmamos
      // solo cuando hay flag pendiente.
      if (pendiente == null) return;
      final res = await setDisponible(desired);
      if (res.ok && !res.queued) {
        print('✅ disponible sincronizado tras offline: $desired');
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
