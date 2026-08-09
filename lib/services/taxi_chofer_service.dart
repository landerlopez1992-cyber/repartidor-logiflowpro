import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Parada / punto del itinerario (recogida, parada intermedia, destino).
class TaxiItinerarioStop {
  const TaxiItinerarioStop({
    required this.tipo,
    required this.orden,
    required this.etiqueta,
    required this.texto,
    this.lat,
    this.lng,
    this.pasajero,
    this.solicitudId,
  });

  final String tipo; // recogida | recogida_companero | parada | destino | destino_companero
  final int orden;
  final String etiqueta;
  final String texto;
  final double? lat;
  final double? lng;
  final String? pasajero;
  final String? solicitudId;

  bool get esParada => tipo == 'parada';
  bool get esRecogida => tipo.startsWith('recogida');
  bool get esDestino => tipo.startsWith('destino');

  LatLng? get latLng {
    if (lat == null || lng == null) return null;
    if (lat == 0 && lng == 0) return null;
    return LatLng(lat!, lng!);
  }

  factory TaxiItinerarioStop.fromJson(Map<String, dynamic> m) {
    return TaxiItinerarioStop(
      tipo: m['tipo']?.toString() ?? 'parada',
      orden: (m['orden'] as num?)?.toInt() ?? 0,
      etiqueta: m['etiqueta']?.toString() ?? '',
      texto: m['texto']?.toString() ?? '',
      lat: (m['lat'] as num?)?.toDouble(),
      lng: (m['lng'] as num?)?.toDouble(),
      pasajero: m['pasajero']?.toString(),
      solicitudId: m['solicitud_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tipo': tipo,
        'orden': orden,
        'etiqueta': etiqueta,
        'texto': texto,
        'lat': lat,
        'lng': lng,
        'pasajero': pasajero,
        'solicitud_id': solicitudId,
      };
}

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
    this.esPool = false,
    this.poolEsLead = false,
    this.paradasCount = 0,
    this.itinerario = const [],
    this.poolPrecioTotalUsd,
    this.itinerarioIndice = 0,
    this.itinerarioEsperando = false,
    this.itinerarioPersistido = false,
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
  final bool esPool;
  final bool poolEsLead;
  final int paradasCount;
  final List<TaxiItinerarioStop> itinerario;
  final double? poolPrecioTotalUsd;
  final int itinerarioIndice;
  final bool itinerarioEsperando;
  final bool itinerarioPersistido;

  bool get esReserva =>
      estado.startsWith('reserva_') || rutaFase.trim().toLowerCase() == 'reserva';

  /// Viaje pool (trayecto compartido entre pasajeros).
  bool get esCompartido =>
      esPool || ofertaTipo.toLowerCase() == 'compartido';

  bool get tieneParadas =>
      paradasCount > 0 || itinerario.any((e) => e.esParada);

  /// Desglose cash coherente: cobrar = precio; empresa = comisión;
  /// te quedas = cobrar − empresa (nunca igual al bruto si hay comisión).
  ({double cobrarClienteUsd, double quedaChoferUsd, double empresaUsd})
      get montosCash {
    final cobrar = (precioUsd ?? gananciaUsd).clamp(0.0, double.infinity);
    var empresa = comisionViajeUsd > 0.009
        ? comisionViajeUsd
        : (comisionPct > 0 && cobrar > 0
            ? cobrar * comisionPct / 100.0
            : (cobrar - gananciaUsd));
    empresa = empresa.clamp(0.0, cobrar);
    final neto = (cobrar - empresa).clamp(0.0, cobrar);
    // ganancia_chofer_usd a veces viene = precio (bruto). No usarla como "te quedas".
    final gananciaPareceBruto = (gananciaUsd - cobrar).abs() < 0.02;
    final gananciaYaNeta =
        !gananciaPareceBruto && (gananciaUsd + empresa - cobrar).abs() < 0.05;
    final queda =
        gananciaYaNeta ? gananciaUsd.clamp(0.0, cobrar) : neto;
    return (
      cobrarClienteUsd: cobrar,
      quedaChoferUsd: queda,
      empresaUsd: empresa,
    );
  }

  /// Paradas intermedias con coordenadas (mapa).
  List<LatLng> get paradasLatLng => itinerario
      .where((e) => e.esParada)
      .map((e) => e.latLng)
      .whereType<LatLng>()
      .toList();

  /// Tramos de navegación estilo Uber Share:
  /// recogidas → paradas → destinos (destinos ordenados por cercanía si [desde]).
  List<TaxiItinerarioStop> legsNavegacion({LatLng? desdeParaDestinos}) {
    final pickups = itinerario.where((e) => e.esRecogida).toList();
    final paradas = itinerario.where((e) => e.esParada).toList();
    var destinos = itinerario.where((e) => e.esDestino).toList();
    if (desdeParaDestinos != null && destinos.length > 1) {
      destinos = List<TaxiItinerarioStop>.of(destinos)
        ..sort((a, b) {
          final da = _distM(desdeParaDestinos, a);
          final db = _distM(desdeParaDestinos, b);
          return da.compareTo(db);
        });
      // Renumerar etiquetas para el chofer: Destino 1 / Destino 2
      destinos = [
        for (var i = 0; i < destinos.length; i++)
          TaxiItinerarioStop(
            tipo: destinos[i].tipo,
            orden: destinos[i].orden,
            etiqueta: destinos.length > 1
                ? 'Destino ${i + 1}${destinos[i].pasajero != null && destinos[i].pasajero!.isNotEmpty ? ' · ${destinos[i].pasajero}' : ''}'
                : destinos[i].etiqueta,
            texto: destinos[i].texto,
            lat: destinos[i].lat,
            lng: destinos[i].lng,
            pasajero: destinos[i].pasajero,
            solicitudId: destinos[i].solicitudId,
          ),
      ];
    }
    return [...pickups, ...paradas, ...destinos];
  }

  static double _distM(LatLng from, TaxiItinerarioStop stop) {
    final ll = stop.latLng;
    if (ll == null) return 1e12;
    const d = Distance();
    return d.as(LengthUnit.Meter, from, ll);
  }

  List<LatLng> get todosPuntosMapa {
    final out = <LatLng>[];
    for (final s in itinerario) {
      final ll = s.latLng;
      if (ll != null) out.add(ll);
    }
    if (out.isEmpty) {
      if (origenLat != 0 || origenLng != 0) {
        out.add(LatLng(origenLat, origenLng));
      }
      if (destinoLat != 0 || destinoLng != 0) {
        out.add(LatLng(destinoLat, destinoLng));
      }
    }
    return out;
  }

  TaxiOfertaChofer copyWith({
    double? pasajeroRating,
    int? pasajeroReviews,
    String? estado,
    String? rutaFase,
    String? pasajeroFotoUrl,
    String? pasajeroNombre,
    List<TaxiItinerarioStop>? itinerario,
    int? itinerarioIndice,
    bool? itinerarioEsperando,
    bool? itinerarioPersistido,
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
      esPool: esPool,
      poolEsLead: poolEsLead,
      paradasCount: paradasCount,
      itinerario: itinerario ?? this.itinerario,
      poolPrecioTotalUsd: poolPrecioTotalUsd,
      itinerarioIndice: itinerarioIndice ?? this.itinerarioIndice,
      itinerarioEsperando:
          itinerarioEsperando ?? this.itinerarioEsperando,
      itinerarioPersistido:
          itinerarioPersistido ?? this.itinerarioPersistido,
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
      case 'compartido':
        return 'Compartido';
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
    final itin = <TaxiItinerarioStop>[];
    final rawPersistido = m['itinerario_chofer_orden'];
    final rawItin = rawPersistido is List && rawPersistido.isNotEmpty
        ? rawPersistido
        : m['itinerario'];
    if (rawItin is List) {
      for (final e in rawItin) {
        if (e is Map) {
          itin.add(TaxiItinerarioStop.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    // Fallback si el RPC aún no trae itinerario: A → waypoints → B
    if (itin.isEmpty) {
      itin.add(
        TaxiItinerarioStop(
          tipo: 'recogida',
          orden: 1,
          etiqueta: 'Recogida',
          texto: m['origen_texto']?.toString() ?? '',
          lat: (m['origen_lat'] as num?)?.toDouble(),
          lng: (m['origen_lng'] as num?)?.toDouble(),
          pasajero: m['pasajero_nombre']?.toString(),
        ),
      );
      final wps = m['waypoints'];
      if (wps is List) {
        var i = 0;
        for (final w in wps) {
          if (w is! Map) continue;
          i++;
          final wm = Map<String, dynamic>.from(w);
          itin.add(
            TaxiItinerarioStop(
              tipo: 'parada',
              orden: 1 + i,
              etiqueta: 'Parada $i',
              texto: wm['texto']?.toString() ??
                  wm['formatted_address']?.toString() ??
                  'Parada',
              lat: (wm['lat'] as num?)?.toDouble(),
              lng: (wm['lng'] as num?)?.toDouble(),
            ),
          );
        }
      }
      itin.add(
        TaxiItinerarioStop(
          tipo: 'destino',
          orden: itin.length + 1,
          etiqueta: 'Destino',
          texto: m['destino_texto']?.toString() ?? '',
          lat: (m['destino_lat'] as num?)?.toDouble(),
          lng: (m['destino_lng'] as num?)?.toDouble(),
          pasajero: m['pasajero_nombre']?.toString(),
        ),
      );
    }
    final esPool = m['es_pool'] == true ||
        (m['oferta_tipo']?.toString() ?? '').toLowerCase() == 'compartido';
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
      esPool: esPool,
      poolEsLead: m['pool_es_lead'] == true,
      paradasCount: (m['paradas_count'] as num?)?.toInt() ??
          itin.where((e) => e.esParada).length,
      itinerario: itin,
      poolPrecioTotalUsd: (m['pool_precio_total_usd'] as num?)?.toDouble(),
      itinerarioIndice:
          (m['itinerario_chofer_indice'] as num?)?.toInt() ?? 0,
      itinerarioEsperando: m['itinerario_chofer_esperando'] == true,
      itinerarioPersistido:
          rawPersistido is List && rawPersistido.isNotEmpty,
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
    if (low.contains('capacidad_insuficiente')) {
      return 'Tu vehículo no tiene plazas suficientes para este viaje.';
    }
    if (low.contains('tarifa_alta')) {
      return 'Tu tarifa no encaja con el precio de este viaje.';
    }
    if (low.contains('comision_pendiente')) {
      return 'Tienes comisión en efectivo pendiente. Regúlala para aceptar viajes.';
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
      final id = res['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        final detalle = await detalleOferta(id);
        if (detalle != null) return detalle;
      }
      return TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res));
    } catch (_) {
      return null;
    }
  }

  /// Reservas confirmadas pendientes del día (tarjeta en Viajes).
  Future<({List<TaxiReservaChoferItem> items, String? error})>
      listarReservasConfirmadas() async {
    try {
      final res = await _db.rpc('taxi_listar_reservas_chofer');
      if (res is! Map || res['ok'] != true) {
        return (
          items: const <TaxiReservaChoferItem>[],
          error: res is Map
              ? (res['error']?.toString() ?? 'No se pudieron cargar')
              : 'No se pudieron cargar',
        );
      }
      final raw = res['reservas'];
      if (raw is! List) {
        return (items: const <TaxiReservaChoferItem>[], error: null);
      }
      return (
        items: raw
            .whereType<Map>()
            .map((e) => TaxiReservaChoferItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        error: null,
      );
    } catch (e) {
      return (items: const <TaxiReservaChoferItem>[], error: e.toString());
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
      // La aceptación ya quedó confirmada por el RPC. Un fallo de red en este
      // segundo fetch no debe convertirla en un falso rechazo en pantalla.
      TaxiOfertaChofer? det;
      try {
        det = await detalleOferta(solicitudId);
      } catch (_) {
        det = null;
      }
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

  Future<({bool ok, String? err})> guardarProgresoItinerario({
    required String solicitudId,
    required List<TaxiItinerarioStop> orden,
    required int indice,
    required bool esperando,
  }) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_itinerario_progreso',
        params: {
          'p_solicitud_id': solicitudId,
          'p_indice': indice,
          'p_esperando': esperando,
          'p_orden': orden.map((e) => e.toJson()).toList(),
        },
      );
      if (res is Map && res['ok'] == true) {
        return (ok: true, err: null);
      }
      return (
        ok: false,
        err: res is Map
            ? (res['mensaje']?.toString() ?? res['error']?.toString())
            : 'No se pudo guardar el progreso',
      );
    } catch (e) {
      return (ok: false, err: e.toString());
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

/// Reserva confirmada pendiente del día (listado chofer).
class TaxiReservaChoferItem {
  const TaxiReservaChoferItem({
    required this.id,
    required this.estado,
    required this.programadoEn,
    required this.origenTexto,
    required this.destinoTexto,
    this.pasajeroNombre = '',
    this.precioUsd = 0,
  });

  final String id;
  final String estado;
  final DateTime? programadoEn;
  final String origenTexto;
  final String destinoTexto;
  final String pasajeroNombre;
  final double precioUsd;

  factory TaxiReservaChoferItem.fromJson(Map<String, dynamic> m) {
    return TaxiReservaChoferItem(
      id: m['id']?.toString() ?? '',
      estado: m['estado']?.toString() ?? '',
      programadoEn: DateTime.tryParse(m['programado_en']?.toString() ?? ''),
      origenTexto: m['origen_texto']?.toString() ?? '',
      destinoTexto: m['destino_texto']?.toString() ?? '',
      pasajeroNombre: (m['pasajero_nombre_snap'] ?? m['pasajero_nombre'])
              ?.toString() ??
          '',
      precioUsd: (m['precio_usd'] as num?)?.toDouble() ?? 0,
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
