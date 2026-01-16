import '../main.dart';

class ConfiguracionService {
  // Singleton
  static final ConfiguracionService _instance = ConfiguracionService._internal();
  factory ConfiguracionService() => _instance;
  ConfiguracionService._internal();

  // Cache de configuración (por tenant_id)
  Map<String, Map<String, dynamic>> _configCache = {};
  Map<String, DateTime> _lastFetchCache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Obtiene la configuración (usa cache si está disponible)
  /// CRÍTICO: Filtra por tenant_id para obtener la configuración correcta
  Future<Map<String, dynamic>> obtenerConfiguracion({bool forceRefresh = false, String? tenantId}) async {
    // Obtener tenant_id si no se proporciona
    String? finalTenantId = tenantId;
    if (finalTenantId == null || finalTenantId.isEmpty) {
      try {
        final user = supabase.auth.currentUser;
        if (user != null) {
          final userData = await supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .maybeSingle();
          finalTenantId = userData?['tenant_id']?.toString();
          print('🏢 Tenant ID obtenido del usuario: $finalTenantId');
        }
      } catch (e) {
        print('⚠️ Error obteniendo tenant_id del usuario: $e');
      }
    }
    
    // Usar 'default' como clave si no hay tenant_id
    final cacheKey = finalTenantId ?? 'default';
    
    // Si hay cache válido y no se fuerza refresh, retornar cache
    if (!forceRefresh && 
        _configCache.containsKey(cacheKey) && 
        _lastFetchCache.containsKey(cacheKey) &&
        DateTime.now().difference(_lastFetchCache[cacheKey]!) < _cacheDuration) {
      print('📦 Usando configuración en cache para tenant: $cacheKey');
      return _configCache[cacheKey]!;
    }

    try {
      print('🔄 Obteniendo configuración desde Supabase...');
      print('   - Tenant ID: $finalTenantId');
      
      // CRÍTICO: Filtrar por tenant_id si está disponible
      var query = supabase.from('configuracion_envios').select();
      
      if (finalTenantId != null && finalTenantId.isNotEmpty) {
        query = query.eq('tenant_id', finalTenantId);
        print('🔒 Filtrando configuración por tenant_id: $finalTenantId');
      } else {
        print('⚠️ No se pudo obtener tenant_id, obteniendo primera configuración disponible');
      }
      
      final response = await query.limit(1).maybeSingle();

      if (response == null) {
        print('⚠️ No se encontró configuración, usando valores por defecto');
        // Retornar configuración por defecto
        final defaultConfig = {
          'notificaciones_emisores': true,
          'notificaciones_repartidores': true,
        };
        _configCache[cacheKey] = defaultConfig;
        _lastFetchCache[cacheKey] = DateTime.now();
        return defaultConfig;
      }

      _configCache[cacheKey] = response;
      _lastFetchCache[cacheKey] = DateTime.now();
      
      print('✅ Configuración obtenida y cacheada para tenant: $cacheKey');
      print('   - notificaciones_emisores: ${response['notificaciones_emisores']}');
      print('   - notificaciones_repartidores: ${response['notificaciones_repartidores']}');
      return response;
    } catch (e) {
      print('❌ Error al obtener configuración: $e');
      // Si hay cache antiguo, retornarlo como fallback
      if (_configCache.containsKey(cacheKey)) {
        print('⚠️ Usando configuración en cache (antigua)');
        return _configCache[cacheKey]!;
      }
      // Retornar configuración por defecto si no hay cache
      return {
        'notificaciones_emisores': true,
        'notificaciones_repartidores': true,
      };
    }
  }

  /// Verifica si las órdenes urgentes tienen prioridad
  Future<bool> tienenPrioridadUrgentes() async {
    final config = await obtenerConfiguracion();
    return config['prioridad_urgentes'] ?? true;
  }

  /// Obtiene el tipo de impresión configurado
  Future<String> obtenerTipoImpresion() async {
    final config = await obtenerConfiguracion();
    return config['tipo_impresion'] ?? 'etiqueta_completa';
  }

  /// Verifica si se debe mostrar rastreo a usuarios
  Future<bool> mostrarRastreoUsuarios() async {
    final config = await obtenerConfiguracion();
    return config['mostrar_rastreo_usuarios'] ?? true;
  }

  /// Verifica si las notificaciones están habilitadas para un tipo de usuario
  /// CRÍTICO: Asegura que se obtiene la configuración del tenant correcto
  Future<bool> notificacionesHabilitadas(String tipo, {String? tenantId}) async {
    print('🔍 [CONFIGURACION] Verificando notificaciones para: $tipo');
    print('   - Tenant ID recibido: $tenantId');
    
    // Obtener configuración con tenant_id
    final config = await obtenerConfiguracion(tenantId: tenantId);
    
    print('📊 [CONFIGURACION] Configuración obtenida:');
    print('   - notificaciones_emisores: ${config['notificaciones_emisores']}');
    print('   - notificaciones_repartidores: ${config['notificaciones_repartidores']}');
    
    bool resultado = false;
    switch (tipo) {
      case 'emisores':
        resultado = config['notificaciones_emisores'] ?? true;
        break;
      case 'destinatarios':
        resultado = config['notificaciones_destinatarios'] ?? false;
        break;
      case 'repartidores':
        resultado = config['notificaciones_repartidores'] ?? true;
        break;
      default:
        resultado = false;
    }
    
    print('✅ [CONFIGURACION] Notificaciones para $tipo: $resultado');
    return resultado;
  }

  /// Verifica si las notificaciones por email están habilitadas
  Future<bool> notificacionesEmailHabilitadas() async {
    final config = await obtenerConfiguracion();
    return config['notificaciones_email'] ?? true;
  }

  /// Verifica si las notificaciones por SMS están habilitadas
  Future<bool> notificacionesSMSHabilitadas() async {
    final config = await obtenerConfiguracion();
    return config['notificaciones_sms'] ?? false;
  }

  /// Verifica si la foto de entrega es obligatoria
  Future<bool> esFotoEntregaObligatoria() async {
    final config = await obtenerConfiguracion();
    return config['foto_entrega_obligatoria'] ?? true;
  }

  /// Verifica si la confirmación de entrega es obligatoria
  Future<bool> esConfirmacionEntregaObligatoria() async {
    final config = await obtenerConfiguracion();
    return config['confirmacion_entrega'] ?? true;
  }

  /// Verifica si la firma digital es obligatoria
  Future<bool> esFirmaDigitalObligatoria() async {
    final config = await obtenerConfiguracion();
    return config['firma_digital'] ?? false;
  }

  /// Obtiene el radio de entrega en metros
  Future<double> obtenerRadioEntrega() async {
    final config = await obtenerConfiguracion();
    return (config['radio_entrega'] ?? 100.0).toDouble();
  }

  /// Verifica si la geolocalización es obligatoria
  Future<bool> esGeolocalizacionObligatoria() async {
    final config = await obtenerConfiguracion();
    return config['geolocalizacion_obligatoria'] ?? true;
  }

  /// Obtiene el intervalo de actualización del rastreo en segundos
  Future<int> obtenerIntervaloActualizacionRastreo() async {
    final config = await obtenerConfiguracion();
    return config['intervalo_actualizacion'] ?? 30;
  }

  /// Obtiene el tiempo de espera en entrega en minutos
  Future<int> obtenerTiempoEsperaEntrega() async {
    final config = await obtenerConfiguracion();
    return config['tiempo_espera_entrega'] ?? 15;
  }

  /// Limpia el cache de configuración
  void limpiarCache({String? tenantId}) {
    if (tenantId != null) {
      _configCache.remove(tenantId);
      _lastFetchCache.remove(tenantId);
      print('🗑️ Cache de configuración limpiado para tenant: $tenantId');
    } else {
      _configCache.clear();
      _lastFetchCache.clear();
      print('🗑️ Cache de configuración limpiado completamente');
    }
  }

  /// Obtiene las opciones de impresión según la configuración
  Future<Map<String, bool>> obtenerOpcionesImpresion() async {
    final config = await obtenerConfiguracion();
    return {
      'incluir_qr': config['incluir_qr'] ?? true,
      'incluir_datos_destinatario': config['incluir_datos_destinatario'] ?? true,
      'incluir_numero_orden': config['incluir_numero_orden'] ?? true,
    };
  }

  /// Obtiene el criterio de ordenamiento de órdenes
  Future<Map<String, bool>> obtenerCriteriosOrdenamiento() async {
    final config = await obtenerConfiguracion();
    return {
      'por_fecha': config['ordenar_por_fecha'] ?? false,
      'por_distancia': config['ordenar_por_distancia'] ?? true,
      'prioridad_urgentes': config['prioridad_urgentes'] ?? true,
    };
  }
}



