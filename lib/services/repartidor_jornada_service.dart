import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

/// Jornada activa / gate para método por_distancia.
class RepartidorJornadaInfo {
  RepartidorJornadaInfo({
    required this.activa,
    required this.requiereJornada,
    this.metodoPago = 'por_orden',
    this.jornadaId,
    this.inicioAt,
    this.kmGpsAcumulado = 0,
    this.origenValido = false,
    this.anclaFuente,
  });

  final bool activa;
  final bool requiereJornada;
  final String metodoPago;
  final String? jornadaId;
  final DateTime? inicioAt;
  final double kmGpsAcumulado;
  final bool origenValido;
  final String? anclaFuente;

  bool get esPorDistancia => metodoPago == 'por_distancia';
}

class RepartidorKmTrayectoria {
  RepartidorKmTrayectoria({
    required this.kmRuta,
    required this.kmGps,
    required this.unidad,
    this.tramos = 0,
    this.ordenes = 0,
    this.jornadaIds = const [],
  });

  final double kmRuta;
  final double kmGps;
  final String unidad;
  final int tramos;
  final int ordenes;
  final List<dynamic> jornadaIds;

  bool get unidadEsMilla => unidad == 'milla';
  String get etiquetaUnidad => unidadEsMilla ? 'millas' : 'km';
}

class RepartidorJornadaService {
  RepartidorJornadaService._();

  static const _prefsJornada = 'rep_jornada_abierta_';
  static const _prefsRequiere = 'rep_requiere_jornada_';

  static bool _ok(dynamic v) => v == true || v == 'true' || v == 1;

  static double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static Future<void> _setRequiere(String repartidorId, bool requiere) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('$_prefsRequiere$repartidorId', requiere);
    } catch (_) {}
  }

  static Future<void> _setJornadaLocal(String repartidorId, String? jornadaId) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (jornadaId == null || jornadaId.isEmpty) {
        await p.remove('$_prefsJornada$repartidorId');
      } else {
        await p.setString('$_prefsJornada$repartidorId', jornadaId);
      }
    } catch (_) {}
  }

  static Future<RepartidorJornadaInfo> jornadaActiva(String repartidorId) async {
    final raw = await supabase.rpc(
      'repartidor_jornada_activa',
      params: {'p_repartidor_id': repartidorId},
    );
    final m = _map(raw);
    if (!_ok(m['ok'])) {
      return RepartidorJornadaInfo(activa: false, requiereJornada: false);
    }
    DateTime? inicio;
    final s = m['inicio_at']?.toString();
    if (s != null && s.isNotEmpty) inicio = DateTime.tryParse(s);
    final info = RepartidorJornadaInfo(
      activa: m['activa'] == true,
      requiereJornada: m['requiere_jornada'] == true,
      metodoPago: m['metodo_pago']?.toString() ?? 'por_orden',
      jornadaId: m['jornada_id']?.toString(),
      inicioAt: inicio,
      kmGpsAcumulado: _d(m['km_gps_acumulado']),
      origenValido: m['origen_valido'] == true,
      anclaFuente: m['ancla_fuente']?.toString(),
    );
    await _setRequiere(repartidorId, info.requiereJornada || info.esPorDistancia);
    if (info.activa && info.jornadaId != null) {
      await _setJornadaLocal(repartidorId, info.jornadaId);
    }
    return info;
  }

  /// Gate de jornada para entregar/recoger.
  ///
  /// **Offline (`offline: true`): NUNCA bloquea** — preserva el flujo offline-first.
  /// Online + `por_distancia`: exige jornada abierta.
  static Future<({bool permitido, String? mensaje})> gateEntrega(
    String repartidorId, {
    bool offline = false,
  }) async {
    // Offline-first: no cortar entregas / recogidas existentes.
    if (offline) {
      return (permitido: true, mensaje: null);
    }

    try {
      final raw = await supabase
          .rpc(
            'repartidor_gate_entrega_jornada',
            params: {'p_repartidor_id': repartidorId},
          )
          .timeout(const Duration(seconds: 4));
      final m = _map(raw);

      // Respuesta inválida / error blando → no tumbar el flujo (puede ser red inestable).
      if (!_ok(m['ok'])) {
        return (permitido: true, mensaje: null);
      }

      final requiere = m['requiere_jornada'] == true;
      await _setRequiere(repartidorId, requiere);

      if (m['permitido'] == true) {
        if (requiere) {
          await _setJornadaLocal(
            repartidorId,
            m['jornada_id']?.toString() ?? '1',
          );
        }
        return (permitido: true, mensaje: null);
      }

      // Solo bloquear en firme cuando el servidor confirma que falta jornada.
      if (requiere) {
        await _setJornadaLocal(repartidorId, null);
        return (
          permitido: false,
          mensaje: m['mensaje']?.toString() ?? 'Inicia tu jornada para continuar',
        );
      }
      return (permitido: true, mensaje: null);
    } on TimeoutException {
      // Red lenta: no bloquear entregas.
      return (permitido: true, mensaje: null);
    } catch (_) {
      // Sin RPC: no bloquear (offline-first / fallo de red).
      return (permitido: true, mensaje: null);
    }
  }

  static Future<Map<String, dynamic>> iniciar({
    required String repartidorId,
    required String tenantId,
    required double lat,
    required double lng,
  }) async {
    final raw = await supabase.rpc(
      'repartidor_iniciar_jornada',
      params: {
        'p_repartidor_id': repartidorId,
        'p_tenant_id': tenantId,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    final map = _map(raw);
    if (_ok(map['ok'])) {
      await _setRequiere(repartidorId, true);
      await _setJornadaLocal(repartidorId, map['jornada_id']?.toString() ?? '1');
    }
    return map;
  }

  static Future<Map<String, dynamic>> cerrar({
    required String repartidorId,
    double? kmGps,
  }) async {
    final raw = await supabase.rpc(
      'repartidor_cerrar_jornada',
      params: {
        'p_repartidor_id': repartidorId,
        'p_km_gps_acumulado': kmGps,
      },
    );
    final map = _map(raw);
    await _setJornadaLocal(repartidorId, null);
    return map;
  }

  static Future<bool> tieneJornadaLocal(String repartidorId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString('$_prefsJornada$repartidorId');
      return v != null && v.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> sincronizarKmGps({
    required String jornadaId,
    required double kmGps,
  }) async {
    try {
      await supabase
          .rpc(
            'repartidor_actualizar_km_gps_jornada',
            params: {
              'p_jornada_id': jornadaId,
              'p_km_gps': kmGps,
            },
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Offline / fallo: el odómetro local sigue; se reintentará después.
    }
  }

  static Future<RepartidorKmTrayectoria?> calcularKm(String repartidorId) async {
    final raw = await supabase.rpc(
      'repartidor_calcular_km_trayectoria',
      params: {'p_repartidor_id': repartidorId},
    );
    final m = _map(raw);
    if (!_ok(m['ok'])) return null;
    final ids = m['jornada_ids'];
    return RepartidorKmTrayectoria(
      kmRuta: _d(m['km_ruta']),
      kmGps: _d(m['km_gps']),
      unidad: m['unidad']?.toString() ?? 'km',
      tramos: m['tramos'] is int ? m['tramos'] as int : int.tryParse('${m['tramos']}') ?? 0,
      ordenes: m['ordenes'] is int ? m['ordenes'] as int : int.tryParse('${m['ordenes']}') ?? 0,
      jornadaIds: ids is List ? List<dynamic>.from(ids) : const [],
    );
  }
}
