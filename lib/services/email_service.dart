import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../config/supabase_config.dart';
import '../models/orden.dart';

class EmailService {
  // URL de la Edge Function de Supabase
  static String get _edgeFunctionUrl {
    return '${SupabaseConfig.supabaseUrl}/functions/v1/send-order-email';
  }

  // Enviar email cuando se crea una orden (llama a Edge Function)
  static Future<bool> enviarEmailOrdenCreada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: 'orden_creada',
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden creada: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "EN TRÁNSITO"
  static Future<bool> enviarEmailOrdenEnTransito(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      print('📧 ===== ENVIAR EMAIL EN TRANSITO =====');
      print('📧 Estado de la orden recibida: ${orden.estado}');
      print('📧 Email destinatario: $emailEmisor');
      print('📧 Orden número: ${orden.numeroOrden}');
      
      if (orden.estado != 'EN TRANSITO') {
        print('⚠️ ⚠️ ⚠️ ADVERTENCIA: El estado de la orden NO es "EN TRANSITO" ⚠️ ⚠️ ⚠️');
        print('⚠️ Estado actual: "${orden.estado}"');
        print('⚠️ Esto causará que el Edge Function envíe el email incorrecto!');
      }
      
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden en tránsito: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "EN REPARTO"
  static Future<bool> enviarEmailOrdenEnReparto(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden en reparto: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "ENTREGADA"
  static Future<bool> enviarEmailOrdenEntregada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      // ✅ FIX: Si es una remesa, usar send-remesa-email en lugar de send-order-email
      if (orden.tieneRemesa == true) {
        print('📧 ===== DETECTADA REMESA - Usando send-remesa-email =====');
        return await enviarEmailRemesaEntregada(orden, emailEmisor, tenantId: tenantId);
      }
      
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden entregada: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "CANCELADA"
  static Future<bool> enviarEmailOrdenCancelada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden cancelada: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "LISTO PARA RECOGER"
  static Future<bool> enviarEmailOrdenListaParaRecoger(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      print('📧 ===== ENVIAR EMAIL ORDEN LISTA PARA RECOGER =====');
      print('📧 Estado de la orden recibida: ${orden.estado}');
      print('📧 Email destinatario: $emailEmisor');
      print('📧 Orden número: ${orden.numeroOrden}');
      print('📧 Recoger en sucursal: ${orden.recogerEnSucursal}');
      
      if (orden.estado != 'LISTO PARA RECOGER') {
        print('⚠️ ⚠️ ⚠️ ADVERTENCIA: El estado de la orden NO es "LISTO PARA RECOGER" ⚠️ ⚠️ ⚠️');
        print('⚠️ Estado actual: "${orden.estado}"');
        print('⚠️ Esto causará que el Edge Function envíe el email incorrecto!');
      }
      
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden lista para recoger: $e');
      return false;
    }
  }

  // Enviar email cuando la orden cambia a "ATRASADO"
  static Future<bool> enviarEmailOrdenAtrasada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      print('📧 ===== ENVIAR EMAIL ORDEN ATRASADA =====');
      print('📧 Estado de la orden recibida: ${orden.estado}');
      print('📧 Email destinatario: $emailEmisor');
      print('📧 Orden número: ${orden.numeroOrden}');
      
      return await _llamarEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: null, // El tipo se determina por el estado
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de orden atrasada: $e');
      return false;
    }
  }

  // Enviar email cuando se crea una remesa
  static Future<bool> enviarEmailRemesaCreada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      print('📧 ===== ENVIAR EMAIL REMESA CREADA =====');
      print('📧 Email destinatario: $emailEmisor');
      print('📧 Orden número: ${orden.numeroOrden}');
      
      return await _llamarRemesaEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: 'remesa_creada',
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de remesa creada: $e');
      return false;
    }
  }

  // Enviar email cuando se entrega una remesa
  static Future<bool> enviarEmailRemesaEntregada(Orden orden, String emailEmisor, {String? tenantId}) async {
    try {
      print('📧 ===== ENVIAR EMAIL REMESA ENTREGADA =====');
      print('📧 Email destinatario: $emailEmisor');
      print('📧 Orden número: ${orden.numeroOrden}');
      
      return await _llamarRemesaEdgeFunction(
        email: emailEmisor,
        orden: orden,
        tipo: 'remesa_entregada',
        tenantId: tenantId,
      );
    } catch (e) {
      print('❌ Error enviando email de remesa entregada: $e');
      return false;
    }
  }

  // Enviar email masivo personalizado a un emisor
  static Future<bool> enviarEmailMasivo({
    required String email,
    required String titulo,
    required String mensaje,
    String? tenantId,
    List<String>? imagenesUrls,
  }) async {
    try {
      print('📧 ===== ENVIAR EMAIL MASIVO =====');
      print('📧 Email destinatario: $email');
      print('📧 Título: $titulo');
      print('📧 Mensaje: ${mensaje.substring(0, mensaje.length > 100 ? 100 : mensaje.length)}...');

      if (email.isEmpty) {
        print('⚠️ No se puede enviar email: destinatario vacío.');
        return false;
      }

      // Obtener el token de sesión de Supabase
      final session = supabase.auth.currentSession;
      if (session == null) {
        print('⚠️ No hay sesión de Supabase activa');
        return false;
      }

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
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id del usuario: $e');
        }
      }

      if (finalTenantId == null || finalTenantId.isEmpty) {
        print('❌ ERROR: No se puede enviar email - tenant_id no disponible');
        return false;
      }

      // Usar la misma Edge Function pero con datos personalizados
      // Crear una orden dummy mínima para que la Edge Function la acepte
      // La Edge Function debe detectar el tipo 'email_masivo' y usar titulo/mensaje
      // Usamos un estado válido para que pase la validación inicial
      final url = Uri.parse(_edgeFunctionUrl);
      
      final ordenDummy = <String, dynamic>{
        'id': 'email-masivo-${DateTime.now().millisecondsSinceEpoch}',
        'numero_orden': 'EMAIL-MASIVO',
        'estado': 'POR ENVIAR', // Estado válido para pasar validación
        'emisor': 'Sistema',
        'receptor': 'Emisores',
        'tenant_id': finalTenantId,
      };
      
      final requestBody = <String, dynamic>{
        'email': email,
        'orden': ordenDummy,
        'titulo': titulo,
        'mensaje': mensaje,
        'tipo': 'email_masivo',
        'tenant_id': finalTenantId,
        'imagenes_urls': imagenesUrls ?? [],
      };

      final bodyJson = jsonEncode(requestBody);
      
      print('🌐 Enviando HTTP POST a: $_edgeFunctionUrl');
      print('   Body length: ${bodyJson.length} caracteres');
      print('   Body content (primeros 500 chars): ${bodyJson.substring(0, bodyJson.length > 500 ? 500 : bodyJson.length)}');

      try {
        final response = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': 'application/json',
            'apikey': SupabaseConfig.supabaseAnonKey,
          },
          body: bodyJson,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            print('❌ TIMEOUT: La Edge Function no respondió en 30 segundos');
            throw TimeoutException('La Edge Function no respondió');
          },
        );

        print('📥 Respuesta recibida:');
        print('   Status Code: ${response.statusCode}');
        print('   Body: ${response.body}');

        if (response.statusCode == 200) {
          print('✅ Email masivo enviado exitosamente a: $email');
          return true;
        } else {
          print('❌ Error enviando email masivo: ${response.statusCode} - ${response.body}');
          return false;
        }
      } catch (e, stackTrace) {
        print('❌ Excepción enviando email masivo: $e');
        print('❌ Stack trace: $stackTrace');
        if (e.toString().contains('Failed to fetch') || e.toString().contains('NetworkError')) {
          print('⚠️ Error de red: Verifica que la Edge Function esté desplegada y funcionando');
          print('⚠️ URL de la Edge Function: $_edgeFunctionUrl');
        }
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ Excepción general en enviarEmailMasivo: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  // Método privado para llamar a la Edge Function de Supabase
  static Future<bool> _llamarEdgeFunction({
    required String email,
    required Orden orden,
    String? tipo,
    String? tenantId,
  }) async {
    try {
      print('🚀 ===== INICIANDO ENVÍO DE EMAIL =====');
      print('📧 Email destinatario: $email');
      print('📦 Orden: ${orden.numeroOrden}');
      print('📊 Estado: ${orden.estado}');
      print('🏢 Tenant ID recibido: $tenantId');
      
      if (email.isEmpty) {
        print('⚠️ No se puede enviar email: destinatario vacío.');
        return false;
      }

      // Obtener el token de sesión de Supabase
      final session = supabase.auth.currentSession;
      if (session == null) {
        print('⚠️ No hay sesión de Supabase activa');
        return false;
      }

      // Obtener tenant_id: múltiples fuentes como fallback
      String? finalTenantId = tenantId ?? orden.tenantId;
      
      // Si aún no tenemos tenant_id, obtenerlo del usuario actual
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
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id del usuario: $e');
        }
      }
      
      // Último recurso: obtener tenant_id directamente de la orden en la base de datos
      if (finalTenantId == null || finalTenantId.isEmpty) {
        try {
          print('⚠️ Obteniendo tenant_id directamente de la base de datos...');
          final ordenData = await supabase
              .from('ordenes')
              .select('tenant_id')
              .eq('id', orden.id)
              .maybeSingle();
          finalTenantId = ordenData?['tenant_id']?.toString();
          print('   - tenant_id desde BD: $finalTenantId');
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id de la orden: $e');
        }
      }
      
      // Validación final
      if (finalTenantId == null || finalTenantId.isEmpty) {
        print('❌ ERROR CRÍTICO: No se puede enviar email - tenant_id no disponible');
        print('   - Orden ID: ${orden.id}');
        print('   - Orden número: ${orden.numeroOrden}');
        return false;
      }
      
      print('✅ Enviando email con tenant_id: $finalTenantId');
      print('   - Tipo de tenant_id: ${finalTenantId.runtimeType}');
      print('   - Longitud: ${finalTenantId.length}');

      // Obtener país de operación del tenant
      String paisDestino = 'Cuba'; // Por defecto
      try {
        final tenantData = await supabase
            .from('tenants')
            .select('pais_operacion')
            .eq('id', finalTenantId)
            .maybeSingle();
        
        if (tenantData != null && tenantData['pais_operacion'] != null) {
          paisDestino = tenantData['pais_operacion'] as String;
          print('🌍 País de operación obtenido del tenant: $paisDestino');
        } else {
          print('⚠️ No se encontró país de operación en el tenant, usando por defecto: $paisDestino');
        }
      } catch (e) {
        print('⚠️ Error obteniendo país de operación del tenant: $e');
        print('   Usando país por defecto: $paisDestino');
      }

      // Preparar datos de la orden para enviar
      final ordenData = <String, dynamic>{
        'id': orden.id,
        'numero_orden': orden.numeroOrden,
        'emisor': orden.emisor,
        'receptor': orden.receptor,
        'estado': orden.estado,
        'direccion_destino': orden.direccionDestino,
        'fecha_entrega': orden.fechaEntrega?.toIso8601String(),
        'fecha_estimada_entrega': orden.fechaEstimadaEntrega?.toIso8601String(),
        'provincia_destino': orden.provinciaDestino ?? 'la provincia de destino',
        'pais_destino': paisDestino, // País del tenant
        'repartidor': orden.repartidor,
        'repartidor_nombre': orden.repartidor,
        'entregado_por': orden.entregadoPor, // Repartidor que entregó (puede ser diferente del asignado)
        'destinatario_nombre': orden.receptor,
        'tenant_id': finalTenantId, // Incluir tenant_id en la orden también
        'recoger_en_sucursal': orden.recogerEnSucursal, // IMPORTANTE: Para diferenciar emails de reparto
      };
      
      // Incluir foto de entrega (tanto como foto_entrega_url como foto_entrega para compatibilidad)
      if (orden.fotoEntrega != null && orden.fotoEntrega!.isNotEmpty) {
        ordenData['foto_entrega_url'] = orden.fotoEntrega;
        ordenData['foto_entrega'] = orden.fotoEntrega;
      }
      
      // Incluir información de remesa
      if (orden.tieneRemesa) {
        ordenData['tiene_remesa'] = true;
        if (orden.cantidadRemesa != null) {
          ordenData['cantidad_remesa'] = orden.cantidadRemesa;
        }
        // El numero_remesa se obtendrá desde la BD en la Edge Function
      } else {
        ordenData['tiene_remesa'] = false;
      }
      
      // Incluir firma del cliente
      if (orden.firmaUrl != null && orden.firmaUrl!.isNotEmpty) {
        ordenData['firma_url'] = orden.firmaUrl;
        ordenData['requiere_firma'] = true;
        print('✍️ Firma del cliente incluida en ordenData: ${orden.firmaUrl}');
      } else if (orden.requiereFirma) {
        ordenData['requiere_firma'] = true;
        print('⚠️ Orden requiere firma pero firmaUrl está vacío');
      } else {
        print('ℹ️ Orden no requiere firma o firmaUrl no disponible');
      }
      
      // Log para verificar foto de entrega y firma
      if (orden.estado == 'ENTREGADO') {
        print('📸 Foto de entrega en ordenData: ${ordenData['foto_entrega'] ?? ordenData['foto_entrega_url'] ?? 'NO DISPONIBLE'}');
        print('✍️ Firma del cliente en ordenData: ${ordenData['firma_url'] ?? 'NO DISPONIBLE'}');
      }
      
      // Log para verificar recogida en sucursal (especialmente importante para estado EN REPARTO)
      if (orden.estado == 'EN REPARTO') {
        print('📬 Recogida en sucursal en ordenData: ${ordenData['recoger_en_sucursal']} (tipo: ${ordenData['recoger_en_sucursal'].runtimeType})');
        print('📬 Orden.recogerEnSucursal (original): ${orden.recogerEnSucursal}');
      }
      
      print('📤 Enviando datos a Edge Function:');
      print('   - Email: $email');
      print('   - Tenant ID: $finalTenantId');
      print('   - Tipo: $tipo');
      print('   - Orden ID: ${orden.id}');
      print('   - Estado: ${orden.estado}');
      print('   - Recoger en sucursal: ${ordenData['recoger_en_sucursal']}');

      final url = Uri.parse(_edgeFunctionUrl);
      
      // Construir el body del request
      // IMPORTANTE: tenant_id DEBE estar presente (ya validado arriba)
      final requestBody = <String, dynamic>{
        'email': email,
        'orden': ordenData,
        'tenant_id': finalTenantId, // Ya validado arriba
      };
      
      if (tipo != null) {
        requestBody['tipo'] = tipo;
      }
      
      print('🔍 DEBUG requestBody antes de jsonEncode:');
      print('   - requestBody.keys: ${requestBody.keys.toList()}');
      print('   - requestBody.tenant_id: ${requestBody['tenant_id']}');
      print('   - requestBody.tenant_id tipo: ${requestBody['tenant_id'].runtimeType}');
      
      // Verificar ANTES de jsonEncode que tenant_id está presente
      if (!requestBody.containsKey('tenant_id') || requestBody['tenant_id'] == null) {
        print('❌ ERROR CRÍTICO: tenant_id NO está en requestBody antes de jsonEncode!');
        print('   - requestBody keys: ${requestBody.keys.toList()}');
        print('   - requestBody.tenant_id: ${requestBody['tenant_id']}');
        return false;
      }
      
      final bodyJson = jsonEncode(requestBody);
      print('📦 Body JSON COMPLETO a enviar:');
      print('   Length: ${bodyJson.length} caracteres');
      print('   Email: $email');
      print('   Tipo: $tipo');
      print('   Tenant ID en body (nivel raíz): ${requestBody['tenant_id']}');
      print('   Tenant ID en ordenData: ${ordenData['tenant_id']}');
      
      // Verificar que tenant_id está en el JSON string
      if (!bodyJson.contains('tenant_id')) {
        print('❌ ERROR CRÍTICO: tenant_id NO está en el JSON string!');
        print('   - Body JSON (primeros 1000 caracteres):');
        print(bodyJson.substring(0, bodyJson.length > 1000 ? 1000 : bodyJson.length));
        return false;
      }
      
      print('   Body completo (primeros 1000 caracteres):');
      print(bodyJson.substring(0, bodyJson.length > 1000 ? 1000 : bodyJson.length));
      print('   ...');
      
      // Verificar que tenant_id está en el JSON parseado
      final bodyParsed = jsonDecode(bodyJson);
      print('   ✅ Verificación - tenant_id en JSON parseado:');
      print('      - requestBody.tenant_id: ${requestBody['tenant_id']}');
      print('      - bodyParsed.tenant_id: ${bodyParsed['tenant_id']}');
      print('      - bodyParsed.orden.tenant_id: ${bodyParsed['orden']?['tenant_id']}');
      
      if (bodyParsed['tenant_id'] == null) {
        print('❌ ERROR CRÍTICO: tenant_id es null después de parsear JSON!');
        return false;
      }
      
      print('🌐 Enviando HTTP POST a: $_edgeFunctionUrl');
      print('   Headers: Authorization, Content-Type, apikey');
      print('   Body length: ${bodyJson.length} caracteres');
      print('   Body (primeros 200 caracteres): ${bodyJson.substring(0, bodyJson.length > 200 ? 200 : bodyJson.length)}');
      
      // Validación final antes de enviar
      if (bodyJson.isEmpty) {
        print('❌ ERROR CRÍTICO: bodyJson está VACÍO antes de enviar!');
        return false;
      }
      
      // Verificar que el JSON es válido
      try {
        final testParse = jsonDecode(bodyJson);
        if (testParse['email'] == null || testParse['orden'] == null) {
          print('❌ ERROR CRÍTICO: bodyJson no tiene email u orden!');
          print('   - testParse.keys: ${testParse.keys.toList()}');
          return false;
        }
      } catch (e) {
        print('❌ ERROR CRÍTICO: bodyJson no es un JSON válido: $e');
        return false;
      }
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.supabaseAnonKey,
        },
        body: bodyJson,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('❌ TIMEOUT: La Edge Function no respondió en 30 segundos');
          throw TimeoutException('La Edge Function no respondió');
        },
      );

      print('📥 Respuesta recibida:');
      print('   Status Code: ${response.statusCode}');
      print('   Body: ${response.body}');
      print('   Headers: ${response.headers}');

      if (response.statusCode == 200) {
        print('✅ Email enviado exitosamente al emisor: $email');
        return true;
      } else {
        print('❌ Error enviando email: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Excepción enviando email: $e');
      return false;
    }
  }

  // Método privado para llamar a la Edge Function de remesas
  static Future<bool> _llamarRemesaEdgeFunction({
    required String email,
    required Orden orden,
    required String tipo,
    String? tenantId,
  }) async {
    try {
      print('🚀 ===== INICIANDO ENVÍO DE EMAIL DE REMESA =====');
      print('📧 Email destinatario: $email');
      print('📦 Orden: ${orden.numeroOrden}');
      print('📊 Estado: ${orden.estado}');
      print('🏢 Tenant ID recibido: $tenantId');
      
      if (email.isEmpty) {
        print('⚠️ No se puede enviar email: destinatario vacío.');
        return false;
      }

      // Obtener el token de sesión de Supabase
      final session = supabase.auth.currentSession;
      if (session == null) {
        print('⚠️ No hay sesión de Supabase activa');
        return false;
      }

      // Obtener tenant_id: múltiples fuentes como fallback
      String? finalTenantId = tenantId ?? orden.tenantId;
      
      // Si aún no tenemos tenant_id, obtenerlo del usuario actual
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
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id del usuario: $e');
        }
      }
      
      // Último recurso: obtener tenant_id directamente de la orden en la base de datos
      if (finalTenantId == null || finalTenantId.isEmpty) {
        try {
          print('⚠️ Obteniendo tenant_id directamente de la base de datos...');
          final ordenData = await supabase
              .from('ordenes')
              .select('tenant_id')
              .eq('id', orden.id)
              .maybeSingle();
          finalTenantId = ordenData?['tenant_id']?.toString();
          print('   - tenant_id desde BD: $finalTenantId');
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id de la orden: $e');
        }
      }
      
      // Validación final
      if (finalTenantId == null || finalTenantId.isEmpty) {
        print('❌ ERROR CRÍTICO: No se puede enviar email - tenant_id no disponible');
        print('   - Orden ID: ${orden.id}');
        print('   - Orden número: ${orden.numeroOrden}');
        return false;
      }
      
      print('✅ Enviando email de remesa con tenant_id: $finalTenantId');

      // Preparar datos de la orden para enviar
      final ordenData = <String, dynamic>{
        'id': orden.id,
        'numero_orden': orden.numeroOrden,
        'emisor': orden.emisor,
        'receptor': orden.receptor,
        'estado': orden.estado,
        'direccion_destino': orden.direccionDestino,
        'fecha_entrega': orden.fechaEntrega?.toIso8601String(),
        'tenant_id': finalTenantId,
      };
      
      // Incluir información de remesa
      if (orden.tieneRemesa) {
        ordenData['tiene_remesa'] = true;
        if (orden.cantidadRemesa != null) {
          ordenData['cantidad_remesa'] = orden.cantidadRemesa;
        }
      }
      
      // Incluir foto de entrega y firma para remesa entregada
      if (tipo == 'remesa_entregada') {
        if (orden.fotoEntrega != null && orden.fotoEntrega!.isNotEmpty) {
          ordenData['foto_entrega_url'] = orden.fotoEntrega;
          ordenData['foto_entrega'] = orden.fotoEntrega;
        }
        if (orden.firmaUrl != null && orden.firmaUrl!.isNotEmpty) {
          ordenData['firma_url'] = orden.firmaUrl;
        }
      }

      final url = Uri.parse('${SupabaseConfig.supabaseUrl}/functions/v1/send-remesa-email');
      
      final requestBody = <String, dynamic>{
        'email': email,
        'orden': ordenData,
        'tipo': tipo,
        'tenant_id': finalTenantId,
      };
      
      final bodyJson = jsonEncode(requestBody);
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.supabaseAnonKey,
        },
        body: bodyJson,
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('✅ Email de remesa enviado exitosamente: ${responseData['id']}');
        return true;
      } else {
        print('❌ Error enviando email de remesa: ${response.statusCode}');
        print('❌ Respuesta: ${response.body}');
        return false;
      }
    } catch (e, stackTrace) {
      print('❌ Excepción enviando email de remesa: $e');
      print('❌ Stack trace: $stackTrace');
      return false;
    }
  }
}

