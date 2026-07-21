import 'package:supabase_flutter/supabase_flutter.dart';

import 'taxi_buscando_prefs.dart';

class TaxiTarifaChofer {
  const TaxiTarifaChofer({
    required this.configurado,
    required this.unidad,
    required this.precioPorUnidadUsd,
    required this.disponible,
  });

  final bool configurado;
  final String unidad; // km | mi
  final double precioPorUnidadUsd;
  final bool disponible;

  factory TaxiTarifaChofer.fromJson(Map<String, dynamic> m) {
    return TaxiTarifaChofer(
      configurado: m['configurado'] == true,
      unidad: (m['unidad']?.toString() ?? 'km').toLowerCase() == 'mi' ? 'mi' : 'km',
      precioPorUnidadUsd:
          (m['precio_por_unidad_usd'] as num?)?.toDouble() ?? 0,
      disponible: m['disponible'] == true,
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
  }) async {
    final res = await _db.rpc(
      'taxi_tarifa_chofer_upsert',
      params: {
        'p_unidad': unidad,
        'p_precio_por_unidad_usd': precioPorUnidadUsd,
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
  /// Así sigue recibiendo ofertas aunque no abra la pantalla Taxis tras reiniciar.
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
