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
    this.metodoPago = 'wallet',
    this.esPagoCash = false,
    this.cashHabilitado = false,
    this.comisionPct = 0,
    this.comisionViajeUsd = 0,
    this.topeDeudaUsd = 100,
    this.pasajeroRating = 5.0,
    this.pasajeroReviews = 0,
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
  final String metodoPago;
  final bool esPagoCash;
  final bool cashHabilitado;
  final double comisionPct;
  final double comisionViajeUsd;
  final double topeDeudaUsd;
  /// Promedio 1–5 del pasajero (reseñas de otros choferes).
  final double pasajeroRating;
  final int pasajeroReviews;

  bool get esReserva =>
      estado.startsWith('reserva_') || rutaFase.trim().toLowerCase() == 'reserva';

  /// Viaje pool (trayecto compartido entre pasajeros).
  bool get esCompartido => ofertaTipo.toLowerCase() == 'compartido';

  TaxiOfertaChofer copyWith({
    double? pasajeroRating,
    int? pasajeroReviews,
    String? estado,
    String? rutaFase,
    String? pasajeroFotoUrl,
    String? pasajeroNombre,
  }) {
    return TaxiOfertaChofer(
      id: id,
      estado: estado ?? this.estado,
      origenLat: origenLat,
      origenLng: origenLng,
      destinoLat: destinoLat,
      destinoLng: destinoLng,
      origenTexto: origenTexto,
      destinoTexto: destinoTexto,
      distanciaKm: distanciaKm,
      distanciaMi: distanciaMi,
      gananciaUsd: gananciaUsd,
      pasajeroNombre: pasajeroNombre ?? this.pasajeroNombre,
      pasajeroFotoUrl: pasajeroFotoUrl ?? this.pasajeroFotoUrl,
      pasajeroTelefono: pasajeroTelefono,
      solicitanteNombre: solicitanteNombre,
      solicitanteTelefono: solicitanteTelefono,
      paraMi: paraMi,
      ofertaTipo: ofertaTipo,
      origenProvincia: origenProvincia,
      origenMunicipio: origenMunicipio,
      precioUsd: precioUsd,
      distanciaAlOrigenKm: distanciaAlOrigenKm,
      createdAt: createdAt,
      rutaFase: rutaFase ?? this.rutaFase,
      pasajeros: pasajeros,
      capacidadChofer: capacidadChofer,
      metodoPago: metodoPago,
      esPagoCash: esPagoCash,
      cashHabilitado: cashHabilitado,
      comisionPct: comisionPct,
      comisionViajeUsd: comisionViajeUsd,
      topeDeudaUsd: topeDeudaUsd,
      pasajeroRating: pasajeroRating ?? this.pasajeroRating,
      pasajeroReviews: pasajeroReviews ?? this.pasajeroReviews,
    );
  }

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
      metodoPago: (m['metodo_pago']?.toString() ?? 'wallet').toLowerCase(),
      esPagoCash: m['es_pago_cash'] == true,
      cashHabilitado: m['cash_habilitado'] == true,
      comisionPct: (m['comision_pct'] as num?)?.toDouble() ?? 0,
      comisionViajeUsd: (m['comision_viaje_usd'] as num?)?.toDouble() ??
          (m['comision_empresa_usd'] as num?)?.toDouble() ??
          0,
      topeDeudaUsd: (m['tope_deuda_usd'] as num?)?.toDouble() ?? 100,
      pasajeroRating: (m['pasajero_rating'] as num?)?.toDouble() ?? 5.0,
      pasajeroReviews: (m['pasajero_reviews'] as num?)?.toInt() ?? 0,
    );
  }
}

class TaxiChoferService {
  TaxiChoferService._();
  static final TaxiChoferService instance = TaxiChoferService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Mensajes claros al chofer (sin códigos internos ni dumps técnicos).
  static String mensajeErrorUsuario(String? raw) {
    final s = (raw ?? '').trim();
    final low = s.toLowerCase();
    if (low.contains('ya_tomado') ||
        low.contains('otro socio ya') ||
        low.contains('ya aceptó')) {
      return 'Otro socio ya tomó este viaje.';
    }
    if (low.contains('ya_rechazado') || low.contains('ya rechazaste')) {
      return 'Ya rechazaste este viaje.';
    }
    if (low.contains('no está disponible') || low.contains('no_disponible')) {
      return 'Este viaje ya no está disponible.';
    }
    if (low.contains('tarifa') || low.contains('precio')) {
      return s.length > 8 && !low.contains('exception')
          ? s
          : 'Revisa tu tarifa en Ajustes de taxis e inténtalo de nuevo.';
    }
    if (s.isEmpty ||
        low.contains('exception') ||
        low.contains('postgrest') ||
        low.contains('socket')) {
      return 'No se pudo completar la acción. Inténtalo de nuevo.';
    }
    return s;
  }

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

  Future<({bool ok, String? err, double? gananciaUsd, double? comisionUsd, bool esCash})>
      completar(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_completar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is Map && res['ok'] == true) {
        final g = (res['ganancia_usd'] as num?)?.toDouble();
        final c = (res['comision_empresa_usd'] as num?)?.toDouble();
        final cash = (res['metodo_pago']?.toString() ?? '').toLowerCase() == 'cash';
        return (
          ok: true,
          err: null,
          gananciaUsd: g,
          comisionUsd: c,
          esCash: cash,
        );
      }
      final msg = res is Map
          ? (res['mensaje']?.toString() ?? res['error']?.toString())
          : null;
      return (
        ok: false,
        err: msg ?? 'No se pudo completar',
        gananciaUsd: null,
        comisionUsd: null,
        esCash: false,
      );
    } catch (e) {
      return (
        ok: false,
        err: e.toString(),
        gananciaUsd: null,
        comisionUsd: null,
        esCash: false,
      );
    }
  }

  /// Cancela viaje aceptado/en curso.
  /// Si es reserva confirmada, el backend reasigna (libera) sin reembolso total.
  Future<({bool ok, String? err, double? amountUsd, bool? reasignada})>
      cancelarViajeChofer(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_cancelar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map) {
        return (
          ok: false,
          err: 'No se pudo cancelar el viaje.',
          amountUsd: null,
          reasignada: null,
        );
      }
      if (res['ok'] == true) {
        final reasig = res['estado']?.toString() == 'reserva_reasignando' ||
            res['estado']?.toString() == 'reserva_pendiente_chofer';
        if (res['needs_pasarela_refund'] == true) {
          final gate =
              (res['pasarela']?.toString() ?? '').toLowerCase().trim();
          final pagoId = (res['pago_id']?.toString() ?? '').trim();
          final tenantId = (res['tenant_id']?.toString() ?? '').trim();
          final preferSquare = gate == 'square' ||
              (pagoId.isNotEmpty && !pagoId.startsWith('pi_'));
          final fn =
              preferSquare ? 'web-wallet-square' : 'web-wallet-stripe';
          if (tenantId.isNotEmpty) {
            try {
              await _db.functions.invoke(
                fn,
                body: {
                  'action': 'refund_taxi_solicitud',
                  'tenant_id': tenantId,
                  'solicitud_id': solicitudId,
                },
              );
            } catch (_) {}
          }
        }
        return (
          ok: true,
          err: null,
          amountUsd: (res['amount_usd'] as num?)?.toDouble(),
          reasignada: reasig,
        );
      }
      // Fallback explícito si el backend aún no redirige reservas.
      final err = res['error']?.toString();
      if (err == 'estado_invalido') {
        final libera = await _db.rpc(
          'taxi_chofer_libera_reserva',
          params: {'p_solicitud_id': solicitudId},
        );
        if (libera is Map && libera['ok'] == true) {
          return (ok: true, err: null, amountUsd: null, reasignada: true);
        }
      }
      return (
        ok: false,
        err: res['mensaje']?.toString() ??
            res['error']?.toString() ??
            'No se pudo cancelar el viaje.',
        amountUsd: null,
        reasignada: null,
      );
    } catch (e) {
      return (ok: false, err: e.toString(), amountUsd: null, reasignada: null);
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

  Future<TaxiGananciasResumen?> gananciasResumen() async {
    try {
      final res = await _db.rpc('taxi_chofer_ganancias_resumen');
      if (res is! Map || res['ok'] != true) return null;
      return TaxiGananciasResumen.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  Future<TaxiDemandaSugerencia?> demandaSugerencia() async {
    try {
      final res = await _db.rpc('taxi_chofer_demanda_sugerencia');
      if (res is! Map || res['ok'] != true) return null;
      return TaxiDemandaSugerencia.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  /// Rating del pasajero (promedio de reseñas de choferes).
  Future<({double rating, int reviews})> pasajeroRatingPorSolicitud(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_pasajero_rating_por_solicitud',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map || res['ok'] != true) {
        return (rating: 5.0, reviews: 0);
      }
      return (
        rating: (res['pasajero_rating'] as num?)?.toDouble() ?? 5.0,
        reviews: (res['pasajero_reviews'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return (rating: 5.0, reviews: 0);
    }
  }

  Future<({bool ok, String? err})> guardarReviewPasajero({
    required String solicitudId,
    required int estrellas,
    String? comentario,
  }) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_guardar_review_pasajero',
        params: {
          'p_solicitud_id': solicitudId,
          'p_estrellas': estrellas,
          'p_comentario': comentario,
        },
      );
      if (res is Map && res['ok'] == true) {
        return (ok: true, err: null);
      }
      return (
        ok: false,
        err: res is Map
            ? (res['mensaje']?.toString() ?? res['error']?.toString())
            : 'No se pudo guardar la valoración',
      );
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }
}

class TaxiGananciasResumen {
  const TaxiGananciasResumen({
    required this.gananciaHoy,
    required this.gananciaSemana,
    required this.viajesHoy,
    required this.viajesSemana,
    required this.comisionPendiente,
    required this.fianza,
    required this.propinasSemana,
  });

  final double gananciaHoy;
  final double gananciaSemana;
  final int viajesHoy;
  final int viajesSemana;
  final double comisionPendiente;
  final double fianza;
  final double propinasSemana;

  factory TaxiGananciasResumen.fromJson(Map<String, dynamic> m) {
    return TaxiGananciasResumen(
      gananciaHoy: (m['ganancia_hoy_usd'] as num?)?.toDouble() ?? 0,
      gananciaSemana: (m['ganancia_semana_usd'] as num?)?.toDouble() ?? 0,
      viajesHoy: (m['viajes_hoy'] as num?)?.toInt() ?? 0,
      viajesSemana: (m['viajes_semana'] as num?)?.toInt() ?? 0,
      comisionPendiente: (m['comision_pendiente_usd'] as num?)?.toDouble() ?? 0,
      fianza: (m['fianza_usd'] as num?)?.toDouble() ?? 0,
      propinasSemana: (m['propinas_semana_usd'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TaxiDemandaSugerencia {
  const TaxiDemandaSugerencia({
    required this.altaDemanda,
    required this.pedidosPendientes,
    required this.sociosOnline,
    required this.mensaje,
  });

  final bool altaDemanda;
  final int pedidosPendientes;
  final int sociosOnline;
  final String mensaje;

  factory TaxiDemandaSugerencia.fromJson(Map<String, dynamic> m) {
    return TaxiDemandaSugerencia(
      altaDemanda: m['alta_demanda'] == true,
      pedidosPendientes: (m['pedidos_pendientes'] as num?)?.toInt() ?? 0,
      sociosOnline: (m['socios_online'] as num?)?.toInt() ?? 0,
      mensaje: m['mensaje']?.toString() ?? '',
    );
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
