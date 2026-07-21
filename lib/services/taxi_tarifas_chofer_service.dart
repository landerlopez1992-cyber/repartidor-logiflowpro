import 'package:supabase_flutter/supabase_flutter.dart';

import 'taxi_buscando_prefs.dart';

class TaxiTarifaChofer {
  const TaxiTarifaChofer({
    required this.configurado,
    required this.unidad,
    required this.precioPorUnidadUsd,
    required this.disponible,
    this.capacidadPasajeros = 4,
    this.pasajerosIncluidos = 2,
    this.recargoPorPasajeroUsd = 0,
  });

  final bool configurado;
  final String unidad; // km | mi
  final double precioPorUnidadUsd;
  final bool disponible;
  final int capacidadPasajeros;
  final int pasajerosIncluidos;
  final double recargoPorPasajeroUsd;

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
        capacidadPasajeros: 4,
        pasajerosIncluidos: 2,
        recargoPorPasajeroUsd: 0,
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
  }) async {
    final res = await _db.rpc(
      'taxi_tarifa_chofer_upsert',
      params: {
        'p_unidad': unidad,
        'p_precio_por_unidad_usd': precioPorUnidadUsd,
        'p_capacidad_pasajeros': capacidadPasajeros.clamp(1, 20),
        'p_pasajeros_incluidos': pasajerosIncluidos.clamp(1, 20),
        'p_recargo_por_pasajero_usd': recargoPorPasajeroUsd.clamp(0, 500),
      },
    );
    if (res is Map && res['ok'] == true) return (ok: true, err: null);
    final err = res is Map
        ? (res['error']?.toString() ?? 'No se pudo guardar')
        : 'No se pudo guardar';
    return (ok: false, err: err);
  }

  Future<({bool ok, String? err})> setDisponible(bool value) async {
    final res = await _db.rpc(
      'taxi_chofer_set_disponible',
      params: {'p_disponible': value},
    );
    if (res is Map && res['ok'] == true) return (ok: true, err: null);
    final msg = res is Map
        ? (res['mensaje']?.toString() ??
            res['error']?.toString() ??
            'No se pudo actualizar')
        : 'No se pudo actualizar';
    return (ok: false, err: msg);
  }

  /// Reafirma disponibilidad en servidor si el modo activo quedó en el dispositivo.
  Future<void> reafirmarDisponibleSiActivoLocal() async {
    try {
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
