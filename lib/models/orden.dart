class Orden {
  final String id;
  final String numeroOrden; // Nuevo campo para el número de orden
  final String emisor;
  final String receptor;
  final String descripcion;
  final String direccionDestino;
  final String? telefonoDestinatario;
  final String? ciudadDestino;
  final String? provinciaDestino;
  final String? municipioDestino;
  final String? consejoPopularBatey;
  final double? peso;
  final double? largo;
  final double? ancho;
  final double? alto;
  String estado;
  final DateTime fechaCreacion;
  DateTime? fechaEntrega;
  final DateTime? fechaEstimadaEntrega;
  final String? notas;
  final String? repartidor;
  String? entregadoPor; // Repartidor que entregó la orden (puede ser diferente del asignado) - mutable
  final bool esUrgente;
  final String? fotoEntrega;
  
  // Usuario que creó la orden
  final String? creadoPorNombre;
  final String? creadoPorEmail;
  
  // Cantidad de bultos
  final int cantidadBultos;
  
  // Campos de pago
  final bool requierePago;
  final double montoCobrar; // Dinero contra entrega (si requierePago = true) o precio total (si requierePago = false)
  final String moneda; // 'USD' o 'CUP'
  final double? precioTotalEnvio; // Precio total cobrado al cliente (emisor) - OBLIGATORIO
  final String? monedaPrecioTotalEnvio; // Moneda del precio total del envío
  bool pagado;
  final DateTime? fechaPago;
  final String? notasPago;
  
  // Campo para indicar si la orden fue pagada al repartidor
  final bool pagada; // Si es true, se oculta de la vista del repartidor
  
  // Campos de remesa
  final bool tieneRemesa;
  final double? cantidadRemesa;
  final String? numeroRemesa; // Número único de remesa (RMSA + 5 dígitos)
  
  // Campos de firma
  final bool requiereFirma;
  final String? firmaUrl;
  
  // Items adicionales con precios personalizados
  final List<Map<String, dynamic>>? itemsAdicionales;
  
  // Tenant ID de la empresa
  final String? tenantId;
  
  // Tipo de orden: 'ENVIO' o 'RECOGIDA'
  final String? tipoOrden;
  
  // Campos para recogida en sucursal
  final bool recogerEnSucursal;
  final String? sucursalId;
  
  // Campos para ruta optimizada
  final int? ordenRuta; // Orden de entrega en la ruta optimizada (1, 2, 3, ...)
  final double? latitudEntrega; // Latitud de la dirección de entrega (geocodificada)
  final double? longitudEntrega; // Longitud de la dirección de entrega (geocodificada)
  final double? distanciaDesdeAnterior; // Distancia desde la orden anterior (km)
  final int? tiempoEstimadoDesdeAnterior; // Tiempo estimado desde la orden anterior (minutos)
  
  // Campos para integración con GoodBarber
  final int? goodbarberOrderId; // ID de la orden en GoodBarber
  final int? goodbarberAppId; // App ID de GoodBarber

  // Campo CUBATRANS: CI y/o Pasaporte del destinatario
  // Requerido por el Reglamento de Mensajería Internacional de Cuba (punto 6.7.3)
  final String? ciPasaporteDestinatario;

  /// CUBATRANS: `MARITIMO` (HBL) o `AEREO` (HAWB); null si no aplica.
  final String? cubatransModoTransporte;

  /// Pedido tienda: el colaborador entrega al cliente (no asignar repartidor / no cambiar estado desde logística).
  final bool entregaPorVendedor;

  /// Contacto del colaborador para que el repartidor coordine recogida (entrega empresa).
  final String? vendedorContactoNombre;
  final String? vendedorContactoTelefono;
  final String? vendedorContactoEmail;

  /// Avisos «mi parte lista para recogida» por colaborador (no cambian el estado de la orden).
  final List<Map<String, dynamic>>? avisosRecogidaVendedor;

  /// Declaración OFAC del cliente final (web / checkout).
  final bool? ofacDeclaracionAceptada;

  Orden({
    required this.id,
    required this.numeroOrden,
    required this.emisor,
    required this.receptor,
    required this.descripcion,
    required this.direccionDestino,
    this.telefonoDestinatario,
    this.ciudadDestino,
    this.provinciaDestino,
    this.municipioDestino,
    this.consejoPopularBatey,
    this.peso,
    this.largo,
    this.ancho,
    this.alto,
    required this.estado,
    required this.fechaCreacion,
    this.fechaEntrega,
    this.fechaEstimadaEntrega,
    this.notas,
    this.repartidor,
    this.entregadoPor,
    this.esUrgente = false,
    this.fotoEntrega,
    this.creadoPorNombre,
    this.creadoPorEmail,
    this.cantidadBultos = 1,
    this.requierePago = false,
    this.montoCobrar = 0.0,
    this.moneda = 'USD',
    this.precioTotalEnvio,
    this.monedaPrecioTotalEnvio,
    this.pagado = false,
    this.fechaPago,
    this.notasPago,
    this.pagada = false,
    this.tieneRemesa = false,
    this.cantidadRemesa,
    this.numeroRemesa,
    this.requiereFirma = false,
    this.firmaUrl,
    this.itemsAdicionales,
    this.tenantId,
    this.tipoOrden,
    this.recogerEnSucursal = false,
    this.sucursalId,
    this.ordenRuta,
    this.latitudEntrega,
    this.longitudEntrega,
    this.distanciaDesdeAnterior,
    this.tiempoEstimadoDesdeAnterior,
    this.goodbarberOrderId,
    this.goodbarberAppId,
    this.ciPasaporteDestinatario,
    this.cubatransModoTransporte,
    this.entregaPorVendedor = false,
    this.vendedorContactoNombre,
    this.vendedorContactoTelefono,
    this.vendedorContactoEmail,
    this.avisosRecogidaVendedor,
    this.ofacDeclaracionAceptada,
  });

  /// Pedido de tienda web: `pagada` en BD a veces significa cobro del cliente, no pago al repartidor.
  bool get esOrdenTiendaOnline {
    final d = descripcion.toLowerCase();
    final n = (notas ?? '').toLowerCase();
    final np = (notasPago ?? '').toLowerCase();
    return d.contains('tienda') ||
        n.contains('tienda') ||
        np.contains('tienda') ||
        np.contains('zelle') ||
        np.contains('wallet') ||
        np.contains('billetera');
  }

  bool get visibleParaRepartidorLista =>
      !entregaPorVendedor && (!pagada || esOrdenTiendaOnline);

  /// Lista tras cargar desde BD: master ve todo el tenant (salvo excepciones operativas).
  bool incluirEnListaCargada({
    required bool esMaster,
    required bool recogerEnSucursalSoloMaster,
  }) {
    if (entregaPorVendedor) return false;
    if (!esMaster) return visibleParaRepartidorLista;
    if (tipoOrden == 'RECOGIDA') return false;
    if (recogerEnSucursal && !recogerEnSucursalSoloMaster) return false;
    return true;
  }

  static String _txtBusqueda(String? v) => (v ?? '').trim();

  static String _numBusqueda(num? n) {
    if (n == null) return '';
    final s = n.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _fechaBusqueda(DateTime? d) {
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy $dd-$mm-$yyyy $yyyy-$mm-$dd $mm/$yyyy';
  }

  /// Texto agregado con todos los datos útiles para el buscador de la pantalla principal.
  String buildTextoBusqueda({String? textoSucursalExtra}) {
    final partes = <String>[
      id,
      numeroOrden,
      _txtBusqueda(numeroRemesa),
      emisor,
      receptor,
      descripcion,
      direccionDestino,
      _txtBusqueda(telefonoDestinatario),
      _txtBusqueda(ciudadDestino),
      _txtBusqueda(provinciaDestino),
      _txtBusqueda(municipioDestino),
      _txtBusqueda(consejoPopularBatey),
      estado,
      _txtBusqueda(repartidor),
      _txtBusqueda(entregadoPor),
      _txtBusqueda(notas),
      _txtBusqueda(notasPago),
      _txtBusqueda(creadoPorNombre),
      _txtBusqueda(creadoPorEmail),
      _txtBusqueda(vendedorContactoNombre),
      _txtBusqueda(vendedorContactoTelefono),
      _txtBusqueda(vendedorContactoEmail),
      _txtBusqueda(ciPasaporteDestinatario),
      _txtBusqueda(cubatransModoTransporte),
      _txtBusqueda(tipoOrden),
      _txtBusqueda(tenantId),
      _txtBusqueda(sucursalId),
      moneda,
      _txtBusqueda(monedaPrecioTotalEnvio),
      _numBusqueda(montoCobrar),
      _numBusqueda(precioTotalEnvio),
      _numBusqueda(cantidadRemesa),
      _numBusqueda(peso),
      _numBusqueda(largo),
      _numBusqueda(ancho),
      _numBusqueda(alto),
      cantidadBultos.toString(),
      _fechaBusqueda(fechaCreacion),
      _fechaBusqueda(fechaEntrega),
      _fechaBusqueda(fechaEstimadaEntrega),
      _fechaBusqueda(fechaPago),
      if (goodbarberOrderId != null) goodbarberOrderId.toString(),
      if (ordenRuta != null) ordenRuta.toString(),
      if (textoSucursalExtra != null && textoSucursalExtra.isNotEmpty)
        textoSucursalExtra,
      pagado ? 'pagado' : '',
      pagada ? 'pagada' : '',
      requierePago ? 'requiere pago contra entrega' : '',
      tieneRemesa ? 'remesa' : '',
      recogerEnSucursal ? 'recoger sucursal' : '',
      esUrgente ? 'urgente' : '',
    ];

    final items = itemsAdicionales;
    if (items != null) {
      for (final item in items) {
        if (item is Map) {
          for (final value in item.values) {
            if (value != null) partes.add(value.toString());
          }
        }
      }
    }

    final avisos = avisosRecogidaVendedor;
    if (avisos != null) {
      for (final aviso in avisos) {
        if (aviso is Map) {
          for (final value in aviso.values) {
            if (value != null) partes.add(value.toString());
          }
        }
      }
    }

    return partes.where((p) => p.isNotEmpty).join(' ');
  }

  /// Búsqueda flexible: texto, números parciales (teléfono, orden, precio) y fechas.
  bool coincideConBusqueda(String queryRaw, {String? textoSucursalExtra}) {
    final query = queryRaw.trim().toLowerCase();
    if (query.isEmpty) return true;

    final haystack = buildTextoBusqueda(textoSucursalExtra: textoSucursalExtra)
        .toLowerCase();
    if (haystack.contains(query)) return true;

    final qNum = query.replaceAll(RegExp(r'[^0-9]'), '');
    if (qNum.length >= 2) {
      final hayNum = haystack.replaceAll(RegExp(r'[^0-9]'), '');
      if (hayNum.contains(qNum)) return true;
    }

    return false;
  }

  // Función auxiliar para parsear valores booleanos desde diferentes tipos
  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    if (value is int) return value != 0;
    return null;
  }

  // Convertir de JSON a Orden (útil para bases de datos Supabase)
  factory Orden.fromJson(Map<String, dynamic> json) {
    // Manejar relación con destinatarios (puede venir como objeto o null)
    final destinatarios = json['destinatarios'];
    String? nombreDestinatario;
    String? telefonoDestinatario;
    String? municipioDestinatario;
    String? provinciaDestinatario;
    String? consejoDestinatario;
    
    if (destinatarios != null) {
      // Si es un objeto (relación 1:1)
      if (destinatarios is Map<String, dynamic>) {
        nombreDestinatario = destinatarios['nombre'];
        telefonoDestinatario = destinatarios['telefono'];
        municipioDestinatario = destinatarios['municipio'];
        provinciaDestinatario = destinatarios['provincia'];
        consejoDestinatario = destinatarios['consejo_popular_batey'];
      }
      // Si es una lista (relación 1:N, tomar el primero)
      else if (destinatarios is List && destinatarios.isNotEmpty) {
        final firstDest = destinatarios[0] as Map<String, dynamic>;
        nombreDestinatario = firstDest['nombre'];
        telefonoDestinatario = firstDest['telefono'];
        municipioDestinatario = firstDest['municipio'];
        provinciaDestinatario = firstDest['provincia'];
        consejoDestinatario = firstDest['consejo_popular_batey'];
      }
    }
    
    // Determinar valores finales
    // NOTA: No existe ciudad_destino en la tabla ordenes, solo municipio_destino
    // Para órdenes de GoodBarber, priorizar datos directos de la orden sobre destinatarios vinculados
    // porque los datos de GoodBarber son los correctos (cliente de GoodBarber)
    final esOrdenGoodBarber = json['goodbarber_order_id'] != null;
    
    // Si es orden de GoodBarber, usar datos directos de la orden (destinatario_nombre)
    // Si no es orden de GoodBarber, usar datos de destinatarios vinculados si existen
    final nombreDestinatarioFinal = esOrdenGoodBarber 
        ? (json['destinatario_nombre'] ?? 'Sin destinatario')
        : (json['destinatario_nombre'] ?? nombreDestinatario ?? 'Sin destinatario');
    
    final municipioFinal = esOrdenGoodBarber 
        ? json['municipio_destino'] 
        : (municipioDestinatario ?? json['municipio_destino']);
    final provinciaFinal = esOrdenGoodBarber 
        ? json['provincia_destino'] 
        : (provinciaDestinatario ?? json['provincia_destino']);
    
    return Orden(
      id: json['id'].toString(),
      // ✅ FIX CRÍTICO OFFLINE: Soportar ambos formatos (snake_case y camelCase)
      numeroOrden: json['numero_orden'] ?? json['numeroOrden'] ?? 'N/A',
      emisor: json['emisor_nombre'] ?? json['emisor'] ?? 'Sin emisor',
      receptor: nombreDestinatarioFinal,
      descripcion: json['descripcion'] ?? '',
      direccionDestino: json['direccion_destino'] ?? json['direccionDestino'] ?? '',
      telefonoDestinatario: json['telefono_destinatario'] ?? json['telefonoDestinatario'] ?? telefonoDestinatario,
      ciudadDestino: provinciaFinal, // Ciudad = Provincia en la UI
      provinciaDestino: provinciaFinal,
      municipioDestino: municipioFinal,
      consejoPopularBatey: json['consejo_popular_batey'] ?? consejoDestinatario,
      peso: json['peso']?.toDouble(),
      largo: json['largo']?.toDouble(),
      ancho: json['ancho']?.toDouble(),
      alto: json['alto']?.toDouble(),
      estado: (json['estado'] ?? 'POR ENVIAR').toString().trim(),
      fechaCreacion: json['fecha_creacion'] != null 
          ? DateTime.parse(json['fecha_creacion'])
          : DateTime.now(),
      fechaEntrega: json['fecha_entrega'] != null 
          ? DateTime.parse(json['fecha_entrega'])
          : null,
      fechaEstimadaEntrega: json['fecha_estimada_entrega'] != null 
          ? DateTime.parse(json['fecha_estimada_entrega'])
          : null,
      notas: json['notas'] != null && json['notas'].toString().trim().isNotEmpty 
          ? json['notas'].toString().trim() 
          : null,
      repartidor: json['repartidor_nombre'],
      entregadoPor: json['entregado_por'],
      esUrgente: json['es_urgente'] ?? false,
      fotoEntrega: json['foto_entrega'],
      creadoPorNombre: json['creado_por_nombre'] ?? json['creado_por']?['nombre'],
      creadoPorEmail: json['creado_por_email'] ?? json['creado_por']?['email'],
      cantidadBultos: json['cantidad_bultos'] ?? 1,
      requierePago: json['requiere_pago'] ?? false,
      montoCobrar: (json['monto_cobrar'] ?? 0.0).toDouble(),
      moneda: json['moneda'] ?? 'USD',
      precioTotalEnvio: json['precio_total_envio']?.toDouble(),
      monedaPrecioTotalEnvio: json['moneda_precio_total_envio'] ?? json['moneda'] ?? 'USD',
      pagado: json['pagado'] ?? false,
      fechaPago: json['fecha_pago'] != null 
          ? DateTime.parse(json['fecha_pago'])
          : null,
      notasPago: json['notas_pago'],
      pagada: json['pagada'] ?? false,
      tieneRemesa: json['tiene_remesa'] ?? false,
      cantidadRemesa: json['cantidad_remesa']?.toDouble(),
      numeroRemesa: json['numero_remesa'],
      requiereFirma: json['requiere_firma'] ?? false,
      firmaUrl: json['firma_url'],
      itemsAdicionales: json['items_adicionales'] != null
          ? List<Map<String, dynamic>>.from(json['items_adicionales'])
          : null,
      tenantId: json['tenant_id']?.toString(),
      tipoOrden: json['tipo_orden']?.toString(),
      recogerEnSucursal: _parseBool(json['recoger_en_sucursal']) ?? false,
      sucursalId: json['sucursal_id']?.toString(),
      ordenRuta: json['orden_ruta'] != null ? (json['orden_ruta'] is int ? json['orden_ruta'] : int.tryParse(json['orden_ruta'].toString())) : null,
      latitudEntrega: json['latitud_entrega']?.toDouble(),
      longitudEntrega: json['longitud_entrega']?.toDouble(),
      distanciaDesdeAnterior: json['distancia_desde_anterior']?.toDouble(),
      tiempoEstimadoDesdeAnterior: json['tiempo_estimado_desde_anterior'] != null ? (json['tiempo_estimado_desde_anterior'] is int ? json['tiempo_estimado_desde_anterior'] : int.tryParse(json['tiempo_estimado_desde_anterior'].toString())) : null,
      goodbarberOrderId: json['goodbarber_order_id'] != null ? (json['goodbarber_order_id'] is int ? json['goodbarber_order_id'] : int.tryParse(json['goodbarber_order_id'].toString())) : null,
      goodbarberAppId: json['goodbarber_app_id'] != null ? (json['goodbarber_app_id'] is int ? json['goodbarber_app_id'] : int.tryParse(json['goodbarber_app_id'].toString())) : null,
      ciPasaporteDestinatario: json['ci_pasaporte_destinatario']?.toString(),
      cubatransModoTransporte: json['cubatrans_modo_transporte']?.toString(),
      entregaPorVendedor: _parseBool(json['entrega_por_vendedor']) ?? false,
      vendedorContactoNombre: json['vendedor_contacto_nombre']?.toString(),
      vendedorContactoTelefono: json['vendedor_contacto_telefono']?.toString(),
      vendedorContactoEmail: json['vendedor_contacto_email']?.toString(),
      avisosRecogidaVendedor: _parseAvisosRecogida(json['avisos_recogida_vendedor']),
      ofacDeclaracionAceptada: _parseBool(json['ofac_declaracion_aceptada']),
    );
  }

  static List<Map<String, dynamic>>? _parseAvisosRecogida(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          out.add(e);
        } else if (e is Map) {
          out.add(Map<String, dynamic>.from(e));
        }
      }
      return out.isEmpty ? null : out;
    }
    return null;
  }

  // Convertir de Orden a JSON (útil para guardar en bases de datos)
  // ✅ FIX CRÍTICO OFFLINE: Guardar TODOS los campos para que funcione sin internet
  Map<String, dynamic> toJson() {
    return {
      // Campos básicos
      'id': id,
      'numero_orden': numeroOrden, // ✅ snake_case para caché
      'emisor_nombre': emisor,
      'destinatario_nombre': receptor,
      'descripcion': descripcion,
      'direccion_destino': direccionDestino,
      'telefono_destinatario': telefonoDestinatario,
      'ciudad_destino': ciudadDestino,
      'provincia_destino': provinciaDestino,
      'municipio_destino': municipioDestino,
      'consejo_popular_batey': consejoPopularBatey,
      
      // Dimensiones
      'peso': peso,
      'largo': largo,
      'ancho': ancho,
      'alto': alto,
      
      // Estado y fechas
      'estado': estado,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_entrega': fechaEntrega?.toIso8601String(),
      'fecha_estimada_entrega': fechaEstimadaEntrega?.toIso8601String(),
      
      // Información adicional
      'notas': notas,
      'repartidor_nombre': repartidor,
      'entregado_por': entregadoPor, // ✅ Faltaba
      'es_urgente': esUrgente,
      'foto_entrega': fotoEntrega,
      
      // Usuario creador
      'creado_por_nombre': creadoPorNombre, // ✅ Faltaba
      'creado_por_email': creadoPorEmail, // ✅ Faltaba
      
      // Paquete
      'cantidad_bultos': cantidadBultos,
      
      // Pago
      'requiere_pago': requierePago,
      'monto_cobrar': montoCobrar,
      'moneda': moneda,
      'precio_total_envio': precioTotalEnvio,
      'moneda_precio_total_envio': monedaPrecioTotalEnvio,
      'pagado': pagado,
      'fecha_pago': fechaPago?.toIso8601String(),
      'notas_pago': notasPago,
      'pagada': pagada, // ✅ Faltaba
      
      // Remesa
      'tiene_remesa': tieneRemesa,
      'cantidad_remesa': cantidadRemesa,
      'numero_remesa': numeroRemesa,
      
      // Firma
      'requiere_firma': requiereFirma,
      'firma_url': firmaUrl,
      
      // Items adicionales
      'items_adicionales': itemsAdicionales,
      
      // Tenant y tipo
      'tenant_id': tenantId, // ✅ CRÍTICO - Faltaba
      'tipo_orden': tipoOrden,
      
      // Recogida en sucursal
      'recoger_en_sucursal': recogerEnSucursal,
      'sucursal_id': sucursalId,
      
      // Ruta optimizada
      'orden_ruta': ordenRuta,
      'latitud_entrega': latitudEntrega,
      'longitud_entrega': longitudEntrega,
      'distancia_desde_anterior': distanciaDesdeAnterior,
      'tiempo_estimado_desde_anterior': tiempoEstimadoDesdeAnterior,
      
      // GoodBarber
      'goodbarber_order_id': goodbarberOrderId, // ✅ CRÍTICO - Faltaba
      'goodbarber_app_id': goodbarberAppId, // ✅ Faltaba

      // CUBATRANS
      'ci_pasaporte_destinatario': ciPasaporteDestinatario,
      'cubatrans_modo_transporte': cubatransModoTransporte,

      'entrega_por_vendedor': entregaPorVendedor,
      'vendedor_contacto_nombre': vendedorContactoNombre,
      'vendedor_contacto_telefono': vendedorContactoTelefono,
      'vendedor_contacto_email': vendedorContactoEmail,
      'avisos_recogida_vendedor': avisosRecogidaVendedor,
      'ofac_declaracion_aceptada': ofacDeclaracionAceptada,
    };
  }
}

