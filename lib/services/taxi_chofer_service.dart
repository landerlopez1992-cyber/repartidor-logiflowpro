import 'package:supabase_flutter/supabase_flutter.dart';

/// Oferta / viaje taxi para el socio (app Repartidor).
class TaxiOfertaChofer {
  const TaxiOfertaChofer({
    required this.id,
    required this.estado,
    required this.origenLat,
    required this.origenLng,
    required this.destinoLat,
    required this.destinoLng,
    required this.origenTexto,
    required this.destinoTexto,
    required this.distanciaKm,
    required this.distanciaMi,
    required this.gananciaUsd,
    required this.pasajeroNombre,
    this.pasajeroFotoUrl,
    this.pasajeroTelefono = '',
    this.solicitanteNombre = '',
    this.solicitanteTelefono = '',
    this.paraMi = true,
    this.ofertaTipo = '',
    this.origenProvincia = '',
    this.origenMunicipio = '',
    this.precioUsd,
    this.distanciaAlOrigenKm,
    this.createdAt,
    this.rutaFase = 'hacia_pasajero',
    this.pasajeros = 1,
    this.capacidadChofer = 4,
  });

  final String id;
  final String estado;
  final double origenLat;
  final double origenLng;
  final double destinoLat;
  final double destinoLng;
  final String origenTexto;
  final String destinoTexto;
  final double distanciaKm;
  final double distanciaMi;
  final double gananciaUsd;
  final String pasajeroNombre;
  final String? pasajeroFotoUrl;
  final String pasajeroTelefono;
  final String solicitanteNombre;
  final String solicitanteTelefono;
  final bool paraMi;
  final String ofertaTipo;
  final String origenProvincia;
  final String origenMunicipio;
  final double? precioUsd;
  final double? distanciaAlOrigenKm;
  final DateTime? createdAt;
  final String rutaFase;
  final int pasajeros;
  final int capacidadChofer;

  /// Fase 1: yendo al punto A (recogida).
  bool get haciaPasajero =>
      estado == 'aceptado' ||
      (rutaFase == 'hacia_pasajero' && estado != 'en_camino' && estado != 'en_viaje');

  /// Fase 2: ya llegó a A, esperando que el pasajero aborde.
  bool get esperandoPasajero =>
      estado == 'en_camino' || rutaFase == 'esperando_pasajero';

  /// Fase 3: trayecto A → B.
  bool get haciaDestino =>
      estado == 'en_viaje' || rutaFase == 'hacia_destino';

  String get ofertaTipoEtiqueta {
    switch (ofertaTipo.toLowerCase().trim()) {
      case 'economico':
      case 'económico':
        return 'Económico';
      case 'estandar':
      case 'estándar':
      case 'standard':
        return 'Estándar';
      case 'confort':
      case 'comfort':
        return 'Confort';
      case 'premium':
        return 'Premium';
      case '':
        return '—';
      default:
        return ofertaTipo;
    }
  }

  String get zonaOrigen {
    final parts = <String>[
      if (origenMunicipio.trim().isNotEmpty) origenMunicipio.trim(),
      if (origenProvincia.trim().isNotEmpty) origenProvincia.trim(),
    ];
    return parts.join(', ');
  }

  factory TaxiOfertaChofer.fromJson(Map<String, dynamic> m) {
    DateTime? created;
    final rawCreated = m['created_at']?.toString();
    if (rawCreated != null && rawCreated.isNotEmpty) {
      created = DateTime.tryParse(rawCreated)?.toLocal();
    }
    return TaxiOfertaChofer(
      id: m['id']?.toString() ?? '',
      estado: m['estado']?.toString() ?? '',
      origenLat: (m['origen_lat'] as num?)?.toDouble() ?? 0,
      origenLng: (m['origen_lng'] as num?)?.toDouble() ?? 0,
      destinoLat: (m['destino_lat'] as num?)?.toDouble() ?? 0,
      destinoLng: (m['destino_lng'] as num?)?.toDouble() ?? 0,
      origenTexto: m['origen_texto']?.toString() ?? '',
      destinoTexto: m['destino_texto']?.toString() ?? '',
      distanciaKm: (m['distancia_km'] as num?)?.toDouble() ?? 0,
      distanciaMi: (m['distancia_mi'] as num?)?.toDouble() ?? 0,
      gananciaUsd: (m['ganancia_usd'] as num?)?.toDouble() ??
          (m['precio_usd'] as num?)?.toDouble() ??
          0,
      pasajeroNombre: m['pasajero_nombre']?.toString() ?? 'Pasajero',
      pasajeroFotoUrl: m['pasajero_foto_url']?.toString(),
      pasajeroTelefono: m['pasajero_telefono']?.toString() ?? '',
      solicitanteNombre: m['solicitante_nombre']?.toString() ?? '',
      solicitanteTelefono: m['solicitante_telefono']?.toString() ?? '',
      paraMi: m['para_mi'] != false,
      ofertaTipo: m['oferta_tipo']?.toString() ?? '',
      origenProvincia: m['origen_provincia']?.toString() ?? '',
      origenMunicipio: m['origen_municipio']?.toString() ?? '',
      precioUsd: (m['precio_usd'] as num?)?.toDouble(),
      distanciaAlOrigenKm: (m['distancia_al_origen_km'] as num?)?.toDouble(),
      createdAt: created,
      rutaFase: m['ruta_fase']?.toString() ?? 'hacia_pasajero',
      pasajeros: (m['pasajeros'] as num?)?.toInt() ?? 1,
      capacidadChofer: (m['capacidad_chofer'] as num?)?.toInt() ?? 4,
    );
  }
}

class TaxiChoferService {
  TaxiChoferService._();
  static final TaxiChoferService instance = TaxiChoferService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<TaxiOfertaChofer?> detalleOferta(String solicitudId) async {
    final res = await _db.rpc(
      'taxi_oferta_detalle_chofer',
      params: {'p_solicitud_id': solicitudId},
    );
    if (res is! Map || res['ok'] != true) return null;
    return TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res));
  }

  /// Viaje aceptado / en curso del chofer autenticado (para reabrir el mapa).
  Future<TaxiOfertaChofer?> viajeActivo() async {
    try {
      final res = await _db.rpc('taxi_chofer_viaje_activo');
      if (res is! Map || res['ok'] != true) return null;
      if (res['activo'] != true) return null;
      return TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  Future<({bool ok, String? err, TaxiOfertaChofer? oferta})> aceptar(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_aceptar_viaje_chofer',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map) {
        return (ok: false, err: 'Respuesta inválida', oferta: null);
      }
      final map = Map<String, dynamic>.from(res);
      if (map['ok'] != true) {
        return (
          ok: false,
          err: map['mensaje']?.toString() ??
              map['error']?.toString() ??
              'No se pudo aceptar',
          oferta: null,
        );
      }
      // Siempre pedir detalle completo (incluye pasajero_foto_url del perfil web).
      final det = await detalleOferta(solicitudId);
      if (det != null) {
        return (ok: true, err: null, oferta: det);
      }
      return (
        ok: true,
        err: null,
        oferta: TaxiOfertaChofer.fromJson(map),
      );
    } catch (e) {
      final s = e.toString();
      if (s.contains('uuid') && s.contains('text')) {
        return (
          ok: false,
          err: 'Error de sistema al aceptar. Actualiza e intenta de nuevo.',
          oferta: null,
        );
      }
      return (ok: false, err: s, oferta: null);
    }
  }

  Future<({bool ok, String? err})> rechazar(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_rechazar_viaje_chofer',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is Map && res['ok'] == true) {
        return (ok: true, err: null);
      }
      if (res is Map) {
        return (
          ok: false,
          err: res['mensaje']?.toString() ??
              res['error']?.toString() ??
              'No se pudo rechazar',
        );
      }
      return (ok: false, err: 'No se pudo rechazar');
    } catch (e) {
      final s = e.toString();
      if (s.contains('uuid') && s.contains('text')) {
        return (ok: false, err: 'Error de sistema al rechazar. Intenta de nuevo.');
      }
      return (ok: false, err: s);
    }
  }

  Future<({bool ok, String? err, TaxiOfertaChofer? oferta})> lleguePasajero(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_llegue_pasajero',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map || res['ok'] != true) {
        return (
          ok: false,
          err: res is Map
              ? (res['mensaje']?.toString() ?? res['error']?.toString())
              : 'Error',
          oferta: null,
        );
      }
      return (
        ok: true,
        err: null,
        oferta: TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res)),
      );
    } catch (e) {
      return (ok: false, err: e.toString(), oferta: null);
    }
  }

  /// Tras llegada al punto A: inicia navegación A → B.
  Future<({bool ok, String? err, TaxiOfertaChofer? oferta})> iniciarViaje(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_iniciar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map || res['ok'] != true) {
        return (
          ok: false,
          err: res is Map
              ? (res['mensaje']?.toString() ?? res['error']?.toString())
              : 'Error',
          oferta: null,
        );
      }
      return (
        ok: true,
        err: null,
        oferta: TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res)),
      );
    } catch (e) {
      return (ok: false, err: e.toString(), oferta: null);
    }
  }

  Future<({bool ok, String? err, double? gananciaUsd})> completar(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_completar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is Map && res['ok'] == true) {
        final g = (res['ganancia_usd'] as num?)?.toDouble();
        return (ok: true, err: null, gananciaUsd: g);
      }
      final msg = res is Map
          ? (res['mensaje']?.toString() ?? res['error']?.toString())
          : null;
      return (
        ok: false,
        err: msg ?? 'No se pudo completar',
        gananciaUsd: null,
      );
    } catch (e) {
      return (ok: false, err: e.toString(), gananciaUsd: null);
    }
  }

  /// Cancela viaje aceptado/en curso: reembolsa 100% al pasajero; el socio pierde la carrera.
  Future<({bool ok, String? err, double? amountUsd})> cancelarViajeChofer(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_cancelar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map) {
        return (ok: false, err: 'No se pudo cancelar el viaje.', amountUsd: null);
      }
      if (res['ok'] == true) {
        return (
          ok: true,
          err: null,
          amountUsd: (res['amount_usd'] as num?)?.toDouble(),
        );
      }
      return (
        ok: false,
        err: res['mensaje']?.toString() ??
            res['error']?.toString() ??
            'No se pudo cancelar el viaje.',
        amountUsd: null,
      );
    } catch (e) {
      return (ok: false, err: e.toString(), amountUsd: null);
    }
  }

  Future<void> actualizarUbicacion({
    required String solicitudId,
    required double lat,
    required double lng,
  }) async {
    try {
      await _db.rpc(
        'taxi_chofer_actualizar_ubicacion',
        params: {
          'p_solicitud_id': solicitudId,
          'p_lat': lat,
          'p_lng': lng,
        },
      );
    } catch (_) {}
  }

  Future<List<TaxiViajeChatMsg>> listarMensajes(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_viaje_mensajes_listar',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map || res['ok'] != true) return const [];
      final raw = res['mensajes'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => TaxiViajeChatMsg.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<TaxiViajeChatMsg?> enviarMensaje({
    required String solicitudId,
    required String cuerpo,
  }) async {
    try {
      final res = await _db.rpc(
        'taxi_viaje_mensaje_enviar',
        params: {
          'p_solicitud_id': solicitudId,
          'p_cuerpo': cuerpo.trim(),
        },
      );
      if (res is! Map || res['ok'] != true) return null;
      final m = res['mensaje'];
      if (m is! Map) return null;
      return TaxiViajeChatMsg.fromJson(Map<String, dynamic>.from(m));
    } catch (_) {
      return null;
    }
  }

  /// Marca push/notificaciones de chat de este viaje como leídas.
  Future<void> marcarChatTaxiLeido(String solicitudId) async {
    if (solicitudId.isEmpty) return;
    try {
      await _db
          .from('notificaciones_repartidores')
          .update({'leida': true})
          .eq('tipo', 'taxi_chat')
          .eq('numero_orden', solicitudId)
          .eq('leida', false);
    } catch (_) {}
  }
}

class TaxiViajeChatMsg {
  const TaxiViajeChatMsg({
    required this.id,
    required this.autorRol,
    required this.cuerpo,
  });

  final String id;
  final String autorRol;
  final String cuerpo;

  factory TaxiViajeChatMsg.fromJson(Map<String, dynamic> m) {
    return TaxiViajeChatMsg(
      id: m['id']?.toString() ?? '',
      autorRol: m['autor_rol']?.toString() ?? '',
      cuerpo: m['cuerpo']?.toString() ?? '',
    );
  }
}
