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
    return RepartidorJornadaInfo(
      activa: m['activa'] == true,
      requiereJornada: m['requiere_jornada'] == true,
      metodoPago: m['metodo_pago']?.toString() ?? 'por_orden',
      jornadaId: m['jornada_id']?.toString(),
      inicioAt: inicio,
      kmGpsAcumulado: _d(m['km_gps_acumulado']),
      origenValido: m['origen_valido'] == true,
      anclaFuente: m['ancla_fuente']?.toString(),
    );
  }

  /// true si puede marcar entregado/recogido.
  static Future<({bool permitido, String? mensaje})> gateEntrega(
    String repartidorId,
  ) async {
    try {
      final raw = await supabase.rpc(
        'repartidor_gate_entrega_jornada',
        params: {'p_repartidor_id': repartidorId},
      );
      final m = _map(raw);
      if (!_ok(m['ok'])) {
        return (permitido: false, mensaje: 'No se pudo verificar la jornada');
      }
      final requiere = m['requiere_jornada'] == true;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setBool('rep_requiere_jornada_$repartidorId', requiere);
      } catch (_) {}

      if (m['permitido'] == true) {
        if (requiere) {
          try {
            final p = await SharedPreferences.getInstance();
            await p.setString(
              'rep_jornada_abierta_$repartidorId',
              m['jornada_id']?.toString() ?? '1',
            );
          } catch (_) {}
        }
        return (permitido: true, mensaje: null);
      }
      try {
        final p = await SharedPreferences.getInstance();
        await p.remove('rep_jornada_abierta_$repartidorId');
      } catch (_) {}
      return (
        permitido: false,
        mensaje: m['mensaje']?.toString() ?? 'Inicia tu jornada para continuar',
      );
    } catch (_) {
      // Offline: solo bloquear si sabemos que el método exige jornada.
      try {
        final p = await SharedPreferences.getInstance();
        final requiere = p.getBool('rep_requiere_jornada_$repartidorId') ?? false;
        if (!requiere) {
          return (permitido: true, mensaje: null);
        }
        final local = await tieneJornadaLocal(repartidorId);
        if (local) return (permitido: true, mensaje: null);
      } catch (_) {}
      return (
        permitido: false,
        mensaje: 'Inicia tu jornada para continuar',
      );
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
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('rep_jornada_abierta_$repartidorId', map['jornada_id']?.toString() ?? '1');
      } catch (_) {}
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
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('rep_jornada_abierta_$repartidorId');
    } catch (_) {}
    return map;
  }

  /// Gate offline: si el método es por_distancia y no hay marca local de jornada.
  static Future<bool> tieneJornadaLocal(String repartidorId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString('rep_jornada_abierta_$repartidorId');
      return v != null && v.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> sincronizarKmGps({
    required String jornadaId,
    required double kmGps,
  }) async {
    await supabase.rpc(
      'repartidor_actualizar_km_gps_jornada',
      params: {
        'p_jornada_id': jornadaId,
        'p_km_gps': kmGps,
      },
    );
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
