import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../utils/mensaje_error_operacion.dart';

class GoodBarberService {
  // Base URL de la API de GoodBarber Commerce
  static const String baseUrl = 'https://commerce.goodbarber.dev/publicapi/v2';
  
  // ✅ MÉTODO DE AUTENTICACIÓN QUE FUNCIONA CON GOODBARBER:
  // GoodBarber requiere el header 'token' (sin 'Bearer')
  // Ejemplo: headers['token'] = apiKey

  /// Decodifica un JWT y extrae el App ID
  /// El JWT de GoodBarber tiene el formato: header.payload.signature
  /// El payload contiene el App ID en el campo 'id'
  static Map<String, dynamic>? decodificarJWT(String token) {
    try {
      // Limpiar el token (eliminar espacios, saltos de línea, etc.)
      final cleanToken = token.trim().replaceAll(RegExp(r'\s+'), '');
      
      print('🔍 Decodificando JWT...');
      print('📏 Longitud del token: ${cleanToken.length}');
      print('📋 Primeros 50 caracteres: ${cleanToken.substring(0, cleanToken.length > 50 ? 50 : cleanToken.length)}...');
      
      // Dividir el JWT en sus partes
      final parts = cleanToken.split('.');
      // Aceptar JWT con 2 o 3 partes (algunos tokens de GoodBarber pueden tener solo 2 partes)
      // NOTA: Si solo hay 2 partes y la segunda está incompleta, el JWT está truncado
      if (parts.length < 2) {
        print('❌ JWT inválido: debe tener al menos 2 partes separadas por puntos');
        print('   Partes encontradas: ${parts.length}');
        print('   Token recibido: ${cleanToken.substring(0, cleanToken.length > 100 ? 100 : cleanToken.length)}...');
        return null;
      }

      // Decodificar el payload (segunda parte)
      // Si tiene 2 partes: header.payload (sin signature - formato no estándar)
      // Si tiene 3 partes: header.payload.signature (formato JWT estándar)
      String payload = parts[1];
      
      // Si el payload termina abruptamente o es muy corto, advertir
      if (payload.isEmpty || payload.length < 20) {
        print('⚠️ Payload del JWT muy corto o vacío: ${payload.length} caracteres');
        print('   Esto indica que el JWT está probablemente truncado');
      }
      print('📦 Payload (sin decodificar): ${payload.substring(0, payload.length > 50 ? 50 : payload.length)}...');
      
      // Intentar decodificar base64url (JWT usa base64url, no base64 estándar)
      // base64Url.decode maneja automáticamente el padding
      try {
        final decodedBytes = base64Url.decode(payload);
        final decodedString = utf8.decode(decodedBytes);
        final payloadData = json.decode(decodedString) as Map<String, dynamic>;

        print('✅ JWT decodificado exitosamente');
        print('📋 Payload decodificado: $payloadData');

        return payloadData;
      } catch (e) {
        print('❌ Error decodificando base64url: $e');
        // Intentar con padding manual si falla
        String normalizedPayload = payload;
        switch (payload.length % 4) {
          case 1:
            normalizedPayload += '===';
            break;
          case 2:
            normalizedPayload += '==';
            break;
          case 3:
            normalizedPayload += '=';
            break;
        }
        
        try {
          final decodedBytes = base64Url.decode(normalizedPayload);
          final decodedString = utf8.decode(decodedBytes);
          final payloadData = json.decode(decodedString) as Map<String, dynamic>;
          
          print('✅ JWT decodificado exitosamente (con padding manual)');
          print('📋 Payload decodificado: $payloadData');
          
          return payloadData;
        } catch (e2) {
          print('❌ Error decodificando con padding manual: $e2');
          return null;
        }
      }
    } catch (e) {
      print('❌ Error general decodificando JWT: $e');
      print('   Stack trace: ${StackTrace.current}');
      return null;
    }
  }

  /// Extrae el App ID del token JWT
  static int? extraerAppId(String apiKey) {
    final payload = decodificarJWT(apiKey);
    if (payload == null) return null;

    // El App ID está en el campo 'id' del payload
    final appId = payload['id'];
    if (appId == null) {
      print('❌ No se encontró el campo "id" en el JWT');
      return null;
    }

    // Convertir a int
    if (appId is int) {
      return appId;
    } else if (appId is String) {
      return int.tryParse(appId);
    }

    print('❌ El App ID no es un número válido: $appId');
    return null;
  }

  /// Valida la conexión con GoodBarber haciendo una petición de prueba
  /// Retorna true si la conexión es válida, false en caso contrario
  /// Requiere el webzine_id (App ID) para construir las URLs correctamente
  static Future<Map<String, dynamic>> validarConexion(String apiKey, {int? webzineId}) async {
    try {
      // Limpiar la API Key más agresivamente
      // Eliminar todos los espacios, saltos de línea, tabs, y caracteres no imprimibles
      String cleanApiKey = apiKey.trim();
      // Eliminar espacios en blanco de cualquier tipo
      cleanApiKey = cleanApiKey.replaceAll(RegExp(r'\s+'), '');
      // Eliminar caracteres de control y no imprimibles
      cleanApiKey = cleanApiKey.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
      
      print('🔍 Validando conexión con GoodBarber...');
      print('📏 Longitud de API Key original: ${apiKey.length}');
      print('📏 Longitud de API Key limpia: ${cleanApiKey.length}');
      print('📋 Primeros 50 caracteres: ${cleanApiKey.substring(0, cleanApiKey.length > 50 ? 50 : cleanApiKey.length)}...');
      print('📋 Últimos 20 caracteres: ${cleanApiKey.length > 20 ? cleanApiKey.substring(cleanApiKey.length - 20) : cleanApiKey}');
      
      // Verificar si hay caracteres sospechosos
      if (cleanApiKey.contains(RegExp(r'\d{3,}'))) {
        print('⚠️ ADVERTENCIA: La API Key contiene números largos, puede estar incompleta');
      }
      
      // Validación básica: la API Key no debe estar vacía
      if (cleanApiKey.isEmpty) {
        print('❌ API Key vacía');
        return {
          'valido': false,
          'mensaje': 'API Key no puede estar vacía. Por favor, pega tu API Key de GoodBarber.',
          'error': 'API Key vacía',
        };
      }
      
      // Validación mínima: debe tener al menos algunos caracteres
      if (cleanApiKey.length < 10) {
        print('⚠️ API Key muy corta (${cleanApiKey.length} caracteres). Intentando validar con la API...');
        // No rechazar aquí, dejar que la API decida si es válida
      }
      
      // NO validar formato JWT estricto aquí
      // Las API keys de GoodBarber pueden tener diferentes formatos
      // La validación real se hace probando la conexión con la API
      
      // Si no se proporciona webzineId, intentar extraerlo del JWT
      int? appId = webzineId;
      if (appId == null) {
        print('🔍 Intentando extraer App ID del JWT...');
        appId = extraerAppId(cleanApiKey);
        if (appId != null) {
          print('✅ App ID extraído del JWT: $appId');
        } else {
          print('⚠️ No se pudo extraer App ID del JWT');
          // Intentar decodificar el JWT para ver qué contiene
          final jwtData = decodificarJWT(cleanApiKey);
          if (jwtData != null) {
            print('📋 Contenido del JWT decodificado: $jwtData');
            print('   Campos disponibles: ${jwtData.keys.join(", ")}');
          } else {
            print('❌ No se pudo decodificar el JWT');
            print('   Esto puede indicar que la API Key está incompleta o tiene un formato diferente');
          }
        }
      }
      
      // Construir endpoints según la documentación de GoodBarber
      // La estructura correcta es: /publicapi/v2/general/orders/{webzine_id}/
      List<String> endpoints = [];
      
      if (appId != null) {
        // URLs correctas según documentación: incluyen webzine_id en la ruta
        endpoints = [
          '$baseUrl/general/orders/$appId/?limit=1', // Estructura correcta según documentación
          '$baseUrl/general/order/$appId/?limit=1', // Singular (por si acaso)
          'https://commerce.goodbarber.com/publicapi/v2/general/orders/$appId/?limit=1', // .com
        ];
      } else {
        // Si no tenemos App ID, intentar endpoints genéricos (pueden fallar)
        print('⚠️ Sin App ID, intentando endpoints genéricos...');
        endpoints = [
          '$baseUrl/general/orders/?limit=1',
          '$baseUrl/general/order/?limit=1',
        ];
      }
      
      http.Response? lastResponse;
      String? lastUrl;
      
      for (final endpointUrl in endpoints) {
        try {
          final url = Uri.parse(endpointUrl);
          print('🌐 Intentando URL: $url');
          print('🔑 Usando API Key (primeros 50 chars): ${cleanApiKey.substring(0, cleanApiKey.length > 50 ? 50 : cleanApiKey.length)}...');
          
          // Intentar diferentes formatos de autenticación
          // GoodBarber puede usar diferentes formatos según la documentación
          // Probar múltiples métodos de autenticación
          // ✅ MÉTODO QUE FUNCIONA: header 'token' (sin Bearer)
          
          // Método 1-6: Headers de autenticación
          // IMPORTANTE: El método 'token' es el que funciona según pruebas
          List<Map<String, String>> authMethods = [
            {'token': cleanApiKey}, // ✅ Método que funciona: header 'token'
            {'Authorization': 'Bearer $cleanApiKey'}, // Método 2: Bearer token (estándar)
            {'Authorization': cleanApiKey}, // Método 3: Token directo sin Bearer
            {'X-API-Key': cleanApiKey}, // Método 4: Header X-API-Key
            {'api_key': cleanApiKey}, // Método 5: Header api_key
            {'X-Auth-Token': cleanApiKey}, // Método 6: Header X-Auth-Token
          ];
          
          http.Response? methodResponse;
          String? methodUsed;
          
          // Probar primero con headers
          for (final authMethod in authMethods) {
            final headers = {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              ...authMethod,
            };
            
            final headerName = authMethod.keys.first;
            print('🔐 Probando autenticación (header): $headerName');
            print('   Valor: ${authMethod[headerName]!.substring(0, authMethod[headerName]!.length > 30 ? 30 : authMethod[headerName]!.length)}...');
            
            try {
              methodResponse = await http.get(
                url,
                headers: headers,
              ).timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  throw Exception('Timeout: La conexión con GoodBarber tardó demasiado');
                },
              );
              
              print('   Status Code: ${methodResponse.statusCode}');
              
              // Si obtenemos 200 o 201, éxito
              if (methodResponse.statusCode == 200 || methodResponse.statusCode == 201) {
                print('✅ ✅ ✅ AUTENTICACIÓN EXITOSA con método: $headerName ✅ ✅ ✅');
                lastResponse = methodResponse;
                lastUrl = endpointUrl;
                methodUsed = headerName;
                break; // Salir del loop de métodos de autenticación
              }
              
              // Si es 401, probar siguiente método
              if (methodResponse.statusCode == 401) {
                print('   ❌ 401 con método $headerName, probando siguiente...');
                continue;
              }
              
              // Si es 400, puede ser que la API existe pero hay otro problema
              if (methodResponse.statusCode == 400) {
                print('   ⚠️ 400 con método $headerName (API existe pero hay otro problema)');
                lastResponse = methodResponse;
                lastUrl = endpointUrl;
                methodUsed = headerName;
                break;
              }
              
              // Si es 404, continuar con siguiente método
              if (methodResponse.statusCode == 404) {
                print('   ⚠️ 404 con método $headerName, probando siguiente...');
                continue;
              }
            } catch (e) {
              print('   ⚠️ Error con método $headerName: $e');
              continue;
            }
          }
          
          // Si ningún header funcionó, probar con query parameters
          if (methodResponse == null || methodResponse.statusCode == 401 || methodResponse.statusCode == 404) {
            print('🔐 Probando autenticación con query parameters...');
            
            // Métodos con query parameters
            List<Map<String, String>> queryParams = [
              {'api_key': cleanApiKey},
              {'token': cleanApiKey},
              {'auth_token': cleanApiKey},
              {'access_token': cleanApiKey},
            ];
            
            for (final param in queryParams) {
              final paramName = param.keys.first;
              final paramValue = param[paramName]!;
              
              // Construir URL con query parameter
              final uriWithParam = Uri.parse(endpointUrl).replace(
                queryParameters: {
                  ...Uri.parse(endpointUrl).queryParameters,
                  paramName: paramValue,
                },
              );
              
              print('🔐 Probando autenticación (query param): $paramName');
              print('   URL: ${uriWithParam.toString().substring(0, uriWithParam.toString().length > 100 ? 100 : uriWithParam.toString().length)}...');
              
              try {
                final queryResponse = await http.get(
                  uriWithParam,
                  headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                ).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () {
                    throw Exception('Timeout');
                  },
                );
                
                print('   Status Code: ${queryResponse.statusCode}');
                
                if (queryResponse.statusCode == 200 || queryResponse.statusCode == 201) {
                  print('✅ ✅ ✅ AUTENTICACIÓN EXITOSA con query param: $paramName ✅ ✅ ✅');
                  methodResponse = queryResponse;
                  methodUsed = 'query_$paramName';
                  break;
                }
                
                if (queryResponse.statusCode == 401) {
                  print('   ❌ 401 con query param $paramName, probando siguiente...');
                  continue;
                }
              } catch (e) {
                print('   ⚠️ Error con query param $paramName: $e');
                continue;
              }
            }
          }
          
          // Si encontramos un método que funciona, salir del loop de endpoints
          if (methodResponse != null && (methodResponse.statusCode == 200 || methodResponse.statusCode == 201 || methodResponse.statusCode == 400)) {
            lastResponse = methodResponse;
            lastUrl = endpointUrl;
            print('✅ Método de autenticación exitoso: $methodUsed');
            break; // Salir del loop de endpoints
          }
          
          // Si todos los métodos dieron 401 o 404, continuar con siguiente endpoint
          if (methodResponse == null || methodResponse.statusCode == 404) {
            print('⚠️ Ningún método de autenticación funcionó para este endpoint');
            continue;
          }
          
          // Si llegamos aquí, guardar la última respuesta
          lastResponse = methodResponse;
          lastUrl = endpointUrl;
        } catch (e) {
          print('⚠️ Error con endpoint $endpointUrl: $e');
          continue; // Intentar siguiente endpoint
        }
      }
      
      if (lastResponse == null) {
        return {
          'valido': false,
          'mensaje': 'No se pudo conectar con GoodBarber. Verifica que:\n1. La API Key sea correcta y esté completa\n2. Tu aplicación esté publicada en GoodBarber\n3. La API Key tenga permisos de "Leer y Escribir" en el módulo Order',
          'error': 'Sin respuesta',
        };
      }
      
      // Si todos los endpoints devolvieron 404, puede ser que la URL base sea incorrecta
      if (lastResponse.statusCode == 404 && lastUrl != null && lastUrl.contains('/orders')) {
        print('⚠️ Todos los endpoints de orders devolvieron 404');
        print('   Esto puede indicar que:');
        print('   1. La URL base de la API es incorrecta');
        print('   2. La aplicación no está publicada');
        print('   3. El módulo Order no está habilitado');
        print('   4. La API Key no tiene los permisos correctos');
        
        // Intentar validar al menos que el JWT sea válido
        final jwtValido = decodificarJWT(cleanApiKey);
        if (jwtValido != null) {
          print('✅ El JWT es válido y se puede decodificar');
          print('   Esto significa que la API Key tiene el formato correcto');
          print('   El problema puede ser la URL o los permisos');
          
          return {
            'valido': false,
            'mensaje': 'La API Key tiene el formato correcto, pero no se pudo conectar con GoodBarber.\n\nPosibles causas:\n• La URL de la API es incorrecta para tu cuenta\n• Tu aplicación no está publicada\n• El módulo Order no está habilitado\n• La API Key no tiene permisos suficientes\n\nSugerencia: Verifica en tu panel de GoodBarber la URL correcta de la API y los permisos de la clave.',
            'error': '404 - Endpoint no encontrado',
            'jwt_valido': true,
          };
        }
      }
      
      final response = lastResponse;

      print('📡 Respuesta de GoodBarber:');
      print('   URL usada: $lastUrl');
      print('   Status Code: ${response.statusCode}');
      print('   Headers: ${response.headers}');
      print('   Body (primeros 200 chars): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // La API Key es válida
        try {
          final data = json.decode(response.body);
          print('✅ Conexión validada exitosamente');
          print('📊 Datos recibidos: ${data.toString().substring(0, data.toString().length > 200 ? 200 : data.toString().length)}...');
          
          return {
            'valido': true,
            'mensaje': 'Conexión exitosa con GoodBarber',
            'datos': data,
          };
        } catch (e) {
          // Aunque el status es 200, puede haber un error en el JSON
          print('⚠️ Status 200 pero error parseando JSON: $e');
          return {
            'valido': true,
            'mensaje': 'Conexión exitosa con GoodBarber (respuesta no JSON)',
            'datos': null,
          };
        }
      } else if (response.statusCode == 401) {
        // API Key inválida
        print('❌ Error 401: API Key inválida o no autorizada');
        print('   Response body: ${response.body}');
        
        // Intentar decodificar el JWT para diagnosticar
        final jwtData = decodificarJWT(cleanApiKey);
        String mensajeDetallado = 'API Key inválida o no autorizada.\n\n';
        
        if (jwtData != null) {
          print('✅ El JWT se puede decodificar, pero la autenticación falla');
          print('   Contenido del JWT: $jwtData');
          mensajeDetallado += 'El formato de la API Key es correcto, pero GoodBarber rechaza la autenticación.\n\n';
          mensajeDetallado += 'Posibles causas:\n';
          mensajeDetallado += '• La API Key está incompleta (falta parte del token)\n';
          mensajeDetallado += '• La API Key no tiene permisos "Leer y Escribir" para Order\n';
          mensajeDetallado += '• La API Key expiró o fue revocada\n';
          mensajeDetallado += '• El App ID no coincide con la API Key\n\n';
          mensajeDetallado += 'Sugerencia: Verifica en GoodBarber que:\n';
          mensajeDetallado += '1. La API Key tenga permisos "Leer y Escribir" para Order\n';
          mensajeDetallado += '2. Hayas copiado la API Key COMPLETA (debe ser un texto largo)\n';
          mensajeDetallado += '3. El App ID coincida con el de la API Key';
        } else {
          print('❌ El JWT no se puede decodificar');
          mensajeDetallado += '🚨 PROBLEMA CRÍTICO: La API Key está INCOMPLETA.\n\n';
          mensajeDetallado += 'Tu API Key tiene solo ${cleanApiKey.length} caracteres y termina abruptamente.\n';
          mensajeDetallado += 'Un JWT completo debe tener 200-500+ caracteres y 3 partes separadas por puntos.\n\n';
          mensajeDetallado += '📋 Tu API Key actual:\n';
          mensajeDetallado += '• Longitud: ${cleanApiKey.length} caracteres (debería ser 200-500+)\n';
          mensajeDetallado += '• Partes: ${cleanApiKey.split('.').length} (debería ser 3)\n';
          mensajeDetallado += '• Termina en: ${cleanApiKey.length > 20 ? cleanApiKey.substring(cleanApiKey.length - 20) : cleanApiKey}\n\n';
          mensajeDetallado += '🔧 SOLUCIONES:\n\n';
          mensajeDetallado += '1. En GoodBarber, busca un botón "Ver clave completa" o "Expandir"\n';
          mensajeDetallado += '2. Intenta hacer scroll horizontal en el campo de la API Key\n';
          mensajeDetallado += '3. Regenera la API Key: Revoca la actual y crea una nueva\n';
          mensajeDetallado += '4. Contacta al soporte de GoodBarber:\n';
          mensajeDetallado += '   - Diles que la API Key se copia incompleta (${cleanApiKey.length} caracteres)\n';
          mensajeDetallado += '   - Pide que verifiquen si hay un bug en su plataforma\n';
          mensajeDetallado += '   - Solicita una API Key completa de 200-500+ caracteres\n\n';
          mensajeDetallado += '⚠️ Sin una API Key completa, la integración NO funcionará.';
        }
        
        return {
          'valido': false,
          'mensaje': mensajeDetallado,
          'error': 'Unauthorized',
          'detalles': response.body,
          'jwt_decodificable': jwtData != null,
        };
      } else if (response.statusCode == 403) {
        // Sin permisos
        print('❌ Error 403: Sin permisos');
        print('   Response body: ${response.body}');
        return {
          'valido': false,
          'mensaje': 'La API Key no tiene permisos suficientes. Asegúrate de que tenga permisos de "Leer y Escribir" en el módulo Order.',
          'error': 'Forbidden',
          'detalles': response.body,
        };
      } else {
        // Otro error
        print('❌ Error ${response.statusCode}: ${response.body}');
        return {
          'valido': false,
          'mensaje': 'Error al conectar con GoodBarber: ${response.statusCode}. ${response.body.length > 100 ? response.body.substring(0, 100) : response.body}',
          'error': 'HTTP ${response.statusCode}',
          'detalles': response.body,
        };
      }
    } catch (e, stackTrace) {
      print('❌ Error validando conexión: $e');
      print('   Stack trace: $stackTrace');
      return {
        'valido': false,
        'mensaje': mensajeErrorOperacion(e, contexto: 'integracion'),
        'error': e.toString(),
      };
    }
  }

  /// Obtiene información básica de la cuenta de GoodBarber
  static Future<Map<String, dynamic>?> obtenerInfoCuenta(String apiKey) async {
    try {
      // Intentar obtener información de la cuenta
      // Esto puede variar según la API de GoodBarber
      // Intentar extraer el App ID del JWT para construir las URLs correctamente
      final appId = extraerAppId(apiKey);
      final resultado = await validarConexion(apiKey, webzineId: appId);
      if (resultado['valido'] == true) {
        return {
          'app_id': extraerAppId(apiKey),
          'conexion_valida': true,
        };
      }
      return null;
    } catch (e) {
      print('❌ Error obteniendo información: $e');
      return null;
    }
  }

  // ============================================
  // FUNCIONES DE SINCRONIZACIÓN BIDIRECCIONAL
  // ============================================

  /// Mapea estados de GoodBarber a VolonexPro+
  /// GoodBarber puede enviar: PENDING, PROCESSED, FULFILLED, DELIVERED, CANCELLED
  /// En la interfaz de GoodBarber se muestran como: Pendiente, Procesado, Terminado, Cancelado
  static String mapearEstadoGoodBarberALogiFlow(String estadoGoodBarber) {
    final estado = estadoGoodBarber.trim();
    final estadoLower = estado.toLowerCase();
    
    print('🔍 Mapeando estado de GoodBarber a VolonexPro+: "$estadoGoodBarber" (normalizado: "$estadoLower")');
    
    switch (estadoLower) {
      case 'pending':
      case 'pendiente':
      case 'p': // Abreviación posible
        print('   → Mapeado a: POR ENVIAR (Pendiente en GoodBarber)');
        return 'POR ENVIAR';
      case 'processed':
      case 'procesado':
      case 'processing':
      case 'procesando': // Variante en español
      case 'fulfilled': // FULFILLED se muestra como "Procesado" en la interfaz de GoodBarber
        print('   → Mapeado a: EN TRANSITO (Procesado en GoodBarber)');
        return 'EN TRANSITO';
      case 'completed':
      case 'terminado':
      case 'finished':
      case 'delivered': // DELIVERED se muestra como "Terminado" en la interfaz de GoodBarber
      case 'entregado':
        print('   → Mapeado a: ENTREGADO (Terminado en GoodBarber)');
        return 'ENTREGADO';
      case 'cancelled':
      case 'cancelado':
      case 'canceled':
        print('   → Mapeado a: CANCELADA (Cancelado en GoodBarber)');
        return 'CANCELADA';
      default:
        print('⚠️ Estado desconocido de GoodBarber: "$estadoGoodBarber", usando POR ENVIAR');
        return 'POR ENVIAR';
    }
  }

  /// Mapea estados de VolonexPro+ a GoodBarber
  /// IMPORTANTE: GoodBarber permite actualizar a FULFILLED, DELIVERED o CANCELLED vía API
  /// PENDING no se puede actualizar (error 3999), pero intentaremos mapear POR ENVIAR a FULFILLED
  /// FULFILLED se muestra como "Procesado" en la interfaz de GoodBarber
  /// DELIVERED se muestra como "Terminado" en la interfaz de GoodBarber
  /// CANCELLED se muestra como "Cancelado" en la interfaz de GoodBarber
  static String? mapearEstadoLogiFlowAGoodBarber(String estadoLogiFlow) {
    final estado = estadoLogiFlow.trim().toUpperCase();
    print('🔍 Mapeando estado de VolonexPro+ a GoodBarber: "$estadoLogiFlow" (normalizado: "$estado")');
    
    switch (estado) {
      case 'POR ENVIAR':
        // GoodBarber NO permite actualizar a PENDING vía API (error 3999)
        // PERO intentaremos actualizar a FULFILLED para que al menos esté en "Procesado"
        // Si GoodBarber lo rechaza, se manejará el error de forma no crítica
        print('   → Intentando mapear a FULFILLED (GoodBarber no permite PENDING, pero intentaremos avanzar)');
        return 'FULFILLED';
      case 'EN TRANSITO':
        // Mapear a FULFILLED (se muestra como "Procesado" en GoodBarber)
        print('   → Mapeado a: FULFILLED (se muestra como "Procesado" en GoodBarber)');
        return 'FULFILLED';
      case 'EN REPARTO':
        // Mapear a FULFILLED (se muestra como "Procesado" en GoodBarber)
        // EN REPARTO es un estado intermedio de VolonexPro+ que no existe en GoodBarber
        print('   → Mapeado a: FULFILLED (se muestra como "Procesado" en GoodBarber)');
        return 'FULFILLED';
      case 'ENTREGADO':
        // Mapear a DELIVERED (se muestra como "Terminado" en GoodBarber)
        print('   → Mapeado a: DELIVERED (se muestra como "Terminado" en GoodBarber)');
        return 'DELIVERED';
      case 'CANCELADA':
        // Intentar mapear a CANCELLED (GoodBarber puede aceptarlo dependiendo del estado actual)
        // Si GoodBarber lo rechaza, se manejará el error de forma no crítica
        print('   → Mapeado a: CANCELLED (se muestra como "Cancelado" en GoodBarber)');
        return 'CANCELLED';
      case 'ATRASADO':
        // ATRASADO no se sincroniza con GoodBarber (no existe en GoodBarber)
        print('   → No se sincroniza (ATRASADO no existe en GoodBarber)');
        return null;
      case 'ENTREGA_PARCIAL':
        // Parcial: orden sigue activa; no marcar DELIVERED en GoodBarber.
        print('   → No se sincroniza (ENTREGA_PARCIAL; pedido aún activo)');
        return null;
      default:
        print('⚠️ Estado desconocido de VolonexPro+: $estadoLogiFlow');
        return null;
    }
  }

  /// Obtiene órdenes de GoodBarber
  /// [apiKey] API Key de GoodBarber
  /// [appId] App ID de GoodBarber
  /// [limit] Límite de órdenes a obtener (default: 50)
  /// [offset] Offset para paginación (default: 0)
  /// [since] Fecha desde la cual obtener órdenes (opcional)
  static Future<Map<String, dynamic>> obtenerOrdenesGoodBarber(
    String apiKey,
    int appId, {
    int limit = 50,
    int offset = 0,
    DateTime? since,
  }) async {
    try {
      final cleanApiKey = apiKey.trim().replaceAll(RegExp(r'\s+'), '');
      
      // Construir URL con parámetros
      // NOTA: GoodBarber puede no soportar filtros de fecha, así que obtenemos todas las órdenes recientes
      String url = '$baseUrl/general/orders/$appId/?limit=$limit&offset=$offset';
      // Intentar agregar filtro de fecha si se proporciona (puede que no funcione en todas las versiones de la API)
      // IMPORTANTE: Si el filtro no funciona, obtenemos todas las órdenes y las filtramos localmente
      if (since != null) {
        try {
          // Formato de fecha para GoodBarber: YYYY-MM-DDTHH:MM:SSZ
          final fechaStr = since.toUtc().toIso8601String().replaceAll(':', '%3A').split('.')[0] + 'Z';
          url += '&created_at__gte=$fechaStr';
          print('   Filtro de fecha: desde $fechaStr');
          print('   ⚠️ NOTA: Si no se obtienen órdenes nuevas, el filtro puede no estar funcionando en la API');
        } catch (e) {
          print('⚠️ Error construyendo filtro de fecha: $e');
          // Continuar sin filtro de fecha
        }
      } else {
        print('   ℹ️ No se proporcionó filtro de fecha, obteniendo todas las órdenes recientes');
      }

      print('📥 Obteniendo órdenes de GoodBarber...');
      print('   URL: $url');
      print('   App ID: $appId');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'token': cleanApiKey, // ✅ Método que funciona
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Órdenes obtenidas: ${data['count'] ?? 0}');
        
        // 🔍 LOGGING DETALLADO: Mostrar estructura completa de la primera orden
        if (data['orders'] != null && (data['orders'] as List).isNotEmpty) {
          final primeraOrden = data['orders'][0];
          print('');
          print('🔍 ===== ESTRUCTURA COMPLETA DE ORDEN GOODBARBER =====');
          print('📋 Orden ID: ${primeraOrden['id']}');
          print('');
          print('📦 CAMPOS PRINCIPALES:');
          print('   - id: ${primeraOrden['id']}');
          print('   - created_at: ${primeraOrden['created_at']}');
          print('   - updated_at: ${primeraOrden['updated_at']}');
          print('   - email: ${primeraOrden['email']}');
          print('   - phone: ${primeraOrden['phone']}');
          print('   - first_name: ${primeraOrden['first_name']}');
          print('   - last_name: ${primeraOrden['last_name']}');
          print('   - order_num: ${primeraOrden['order_num']} (número de orden de GoodBarber)');
          print('   - total: ${primeraOrden['total']}');
          print('   - currency: ${primeraOrden['currency']}');
          print('   - status: ${primeraOrden['status']}');
          print('   - customer_note: ${primeraOrden['customer_note']}');
          print('   - weight: ${primeraOrden['weight']}');
          print('   - shipping_type: ${primeraOrden['shipping_type']} (tipo: ${primeraOrden['shipping_type'].runtimeType})');
          print('   - shipping_method: ${primeraOrden['shipping_method']} (tipo: ${primeraOrden['shipping_method'].runtimeType})');
          // Mostrar también en minúsculas para verificar
          if (primeraOrden['shipping_type'] != null) {
            print('   - shipping_type (lowercase): ${primeraOrden['shipping_type'].toString().toLowerCase()}');
          }
          if (primeraOrden['shipping_method'] != null) {
            print('   - shipping_method (lowercase): ${primeraOrden['shipping_method'].toString().toLowerCase()}');
          }
          print('   - payment_type: ${primeraOrden['payment_type']}');
          print('   - payment_mode: ${primeraOrden['payment_mode']}');
          print('');
          print('📮 SHIPPING_ADDRESS:');
          final shippingAddress = primeraOrden['shipping_address'] ?? {};
          print('   - first_name: ${shippingAddress['first_name']}');
          print('   - last_name: ${shippingAddress['last_name']}');
          print('   - middle_name: ${shippingAddress['middle_name']}');
          print('   - phone: ${shippingAddress['phone']}');
          print('   - street: ${shippingAddress['street']}');
          print('   - extra: ${shippingAddress['extra']}');
          print('   - city: ${shippingAddress['city']}');
          print('   - state: ${shippingAddress['state']}');
          print('   - zipcode: ${shippingAddress['zipcode']}');
          print('   - zip_code: ${shippingAddress['zip_code']}');
          print('   - country: ${shippingAddress['country']}');
          print('   - localized_address: ${shippingAddress['localized_address']}');
          print('   - company: ${shippingAddress['company']}');
          print('   - prefix: ${shippingAddress['prefix']}');
          print('   - suffix: ${shippingAddress['suffix']}');
          print('');
          print('🛒 ITEMS:');
          final items = primeraOrden['items'] ?? [];
          if (items.isNotEmpty) {
            for (int i = 0; i < items.length && i < 3; i++) {
              final item = items[i];
              print('   Item ${i + 1}:');
              print('     - quantity: ${item['quantity']}');
              print('     - price: ${item['price']}');
              print('     - product: ${item['product']}');
              print('     - product.title: ${item['product']?['title']}');
              print('     - variant: ${item['variant']}');
              print('     - weight: ${item['weight']}');
            }
          }
          print('');
          print('📄 JSON COMPLETO (primeros 2000 caracteres):');
          final jsonStr = json.encode(primeraOrden);
          print('   ${jsonStr.length > 2000 ? jsonStr.substring(0, 2000) + "..." : jsonStr}');
          print('🔍 ===== FIN ESTRUCTURA =====');
          print('');
        }
        
        return {
          'exito': true,
          'ordenes': data['orders'] ?? [],
          'count': data['count'] ?? 0,
          'next': data['next'],
          'previous': data['previous'],
        };
      } else {
        print('❌ Error obteniendo órdenes: ${response.statusCode}');
        print('   Response: ${response.body}');
        return {
          'exito': false,
          'error': 'HTTP ${response.statusCode}',
          'mensaje': response.body,
          'ordenes': [],
        };
      }
    } catch (e, stackTrace) {
      print('❌ Error obteniendo órdenes de GoodBarber: $e');
      print('   Stack trace: $stackTrace');
      return {
        'exito': false,
        'error': e.toString(),
        'ordenes': [],
      };
    }
  }

  /// Mapea una orden de GoodBarber al formato de VolonexPro+
  /// [goodbarberOrder] Orden de GoodBarber (JSON)
  /// [emisorNombre] Nombre del emisor (tienda GoodBarber)
  /// [tenantId] ID del tenant en VolonexPro+
  /// [ajustes] Ajustes de GoodBarber (opcional, si no se proporciona se cargarán)
  static Future<Map<String, dynamic>> mapearOrdenGoodBarberALogiFlow(
    Map<String, dynamic> goodbarberOrder,
    String emisorNombre,
    String tenantId,
    int appId,
    String apiKey, {
    Map<String, dynamic>? ajustes,
  }) async {
    try {
      print('');
      print('🔍 ===== MAPEANDO ORDEN GOODBARBER A LOGIFLOW =====');
      print('📋 GoodBarber Order ID: ${goodbarberOrder['id']}');
      
      // 🔥 PASO 1: Obtener orden completa desde el endpoint "Retrieve an order"
      // Este endpoint incluye TODA la información: shipping_type, shipping_method, direcciones de pickup, etc.
      final orderId = goodbarberOrder['id'] as int?;
      Map<String, dynamic>? ordenCompleta;
      
      if (orderId != null) {
        print('📦 [MAPEO] Obteniendo orden completa para orden #$orderId...');
        ordenCompleta = await obtenerOrdenCompleta(apiKey, appId, orderId);
        
        if (ordenCompleta != null) {
          print('✅ [MAPEO] Orden completa obtenida, combinando con datos de la orden...');
          // Combinar ordenCompleta con goodbarberOrder
          // Los campos de ordenCompleta tienen prioridad sobre los de goodbarberOrder
          goodbarberOrder = {...goodbarberOrder, ...ordenCompleta};
        } else {
          print('⚠️ [MAPEO] No se pudo obtener orden completa, usando solo datos de la orden del listado');
        }
      } else {
        print('⚠️ [MAPEO] Order ID es null, no se puede obtener orden completa');
      }
      
      // Cargar ajustes si no se proporcionaron
      Map<String, dynamic> ajustesFinales = ajustes ?? {};
      if (ajustes == null) {
        try {
          final ajustesResponse = await supabase
              .from('goodbarber_ajustes')
              .select('*')
              .eq('tenant_id', tenantId)
              .eq('app_id', appId)
              .maybeSingle();
          
          if (ajustesResponse != null) {
            ajustesFinales = ajustesResponse;
            print('✅ Ajustes cargados desde BD');
          } else {
            // Valores por defecto
            ajustesFinales = {
              'usar_shipping_amount': false,
              'mostrar_items_en_tarjeta': true,
              'mostrar_created_at': true,
              'procesar_zipcode': true,
              'usar_total_goodbarber': false,
            };
            print('ℹ️ Usando ajustes por defecto');
          }
        } catch (e) {
          print('⚠️ Error cargando ajustes: $e, usando valores por defecto');
          ajustesFinales = {
            'usar_shipping_amount': false,
            'mostrar_items_en_tarjeta': true,
            'mostrar_created_at': true,
            'procesar_zipcode': true,
            'usar_total_goodbarber': false,
          };
        }
      }
      
      final usarShippingAmount = ajustesFinales['usar_shipping_amount'] ?? false;
      final mostrarItemsEnTarjeta = ajustesFinales['mostrar_items_en_tarjeta'] ?? true;
      final procesarZipcode = ajustesFinales['procesar_zipcode'] ?? true;
      final usarTotalGoodBarber = ajustesFinales['usar_total_goodbarber'] ?? false;
      
      print('⚙️ Ajustes aplicados:');
      print('   - Usar shipping_amount: $usarShippingAmount');
      print('   - Mostrar items en tarjeta: $mostrarItemsEnTarjeta');
      print('   - Procesar zipcode: $procesarZipcode');
      print('   - Usar total GoodBarber (sin recalcular): $usarTotalGoodBarber');
      
      // 🔍 LOGGING: Mostrar todos los campos disponibles
      print('');
      print('📦 CAMPOS DISPONIBLES EN LA ORDEN:');
      print('   - email: ${goodbarberOrder['email']}');
      print('   - phone: ${goodbarberOrder['phone']}');
      print('   - first_name: ${goodbarberOrder['first_name']}');
      print('   - last_name: ${goodbarberOrder['last_name']}');
      
      // Extraer datos del cliente
      // GoodBarber puede tener los datos del cliente directamente en la orden o en shipping_address
      final firstName = goodbarberOrder['first_name'] ?? '';
      final lastName = goodbarberOrder['last_name'] ?? '';
      final customerEmail = goodbarberOrder['email'] ?? '';
      final customerPhone = goodbarberOrder['phone'] ?? '';
      
      // Si no están en la orden principal, buscar en shipping_address
      final shippingAddress = goodbarberOrder['shipping_address'] ?? {};
      print('');
      print('📮 SHIPPING_ADDRESS DISPONIBLE:');
      print('   - first_name: ${shippingAddress['first_name']}');
      print('   - last_name: ${shippingAddress['last_name']}');
      print('   - middle_name: ${shippingAddress['middle_name']}');
      print('   - phone: ${shippingAddress['phone']}');
      print('   - street: ${shippingAddress['street']}');
      print('   - extra: ${shippingAddress['extra']}');
      print('   - city: ${shippingAddress['city']}');
      print('   - state: ${shippingAddress['state']}');
      print('   - zipcode: ${shippingAddress['zipcode']}');
      print('   - zip_code: ${shippingAddress['zip_code']}');
      print('   - country: ${shippingAddress['country']}');
      print('   - localized_address: ${shippingAddress['localized_address']}');
      
      final firstNameFinal = firstName.isNotEmpty ? firstName : (shippingAddress['first_name'] ?? '');
      final lastNameFinal = lastName.isNotEmpty ? lastName : (shippingAddress['last_name'] ?? '');
      final customerName = '$firstNameFinal $lastNameFinal'.trim();
      final customerPhoneFinal = customerPhone.isNotEmpty ? customerPhone : (shippingAddress['phone'] ?? '');
      
      print('');
      print('✅ DATOS EXTRAÍDOS PARA LOGIFLOW:');
      print('   - Emisor: $emisorNombre (usando nombre de empresa)');
      print('   - Destinatario nombre: $customerName');
      print('   - Destinatario teléfono: $customerPhoneFinal');
      print('   - Destinatario email: $customerEmail');

      // Extraer dirección de envío (GoodBarber usa 'street' no 'address_line_1')
      final street = shippingAddress['street'] ?? '';
      final extra = shippingAddress['extra'] ?? '';
      final city = shippingAddress['city'] ?? '';
      final state = shippingAddress['state'] ?? '';
      final zipCodeRaw = shippingAddress['zipcode'] ?? shippingAddress['zip_code'] ?? '';
      final country = shippingAddress['country'] ?? '';
      final localizedAddress = shippingAddress['localized_address'] ?? '';

      // Procesar zipcode según ajustes y país
      // Si país es Cuba, NO procesar zipcode (Cuba no usa códigos postales para entregas)
      // Si procesarZipcode está desactivado, NO procesar zipcode
      String zipCode = '';
      final countryUpper = country.trim().toUpperCase();
      
      // Mapear código de país a nombre completo para mejor procesamiento
      // GoodBarber puede enviar códigos ISO como "CU", "US", "MX", etc.
      String nombrePais = countryUpper;
      final Map<String, String> codigoANombre = {
        'CU': 'Cuba',
        'CUB': 'Cuba',
        'CUBA': 'Cuba',
        'US': 'Estados Unidos',
        'USA': 'Estados Unidos',
        'MX': 'México',
        'MEX': 'México',
        'CO': 'Colombia',
        'COL': 'Colombia',
        'AR': 'Argentina',
        'ARG': 'Argentina',
        'CL': 'Chile',
        'CHL': 'Chile',
        'PE': 'Perú',
        'PER': 'Perú',
        'VE': 'Venezuela',
        'VEN': 'Venezuela',
        'EC': 'Ecuador',
        'ECU': 'Ecuador',
        'ES': 'España',
        'ESP': 'España',
        'DO': 'República Dominicana',
        'DOM': 'República Dominicana',
        'PA': 'Panamá',
        'PAN': 'Panamá',
        'CR': 'Costa Rica',
        'CA': 'Canadá',
        'CAN': 'Canadá',
      };
      
      if (codigoANombre.containsKey(countryUpper)) {
        nombrePais = codigoANombre[countryUpper]!;
        print('🌍 Código de país detectado: "$countryUpper" → "$nombrePais"');
      } else {
        print('🌍 País recibido: "$countryUpper" (no mapeado, usando código original)');
      }
      
      final isCuba = countryUpper == 'CU' || countryUpper == 'CUB' || countryUpper == 'CUBA' || nombrePais == 'Cuba';
      
      if (procesarZipcode && !isCuba && zipCodeRaw.isNotEmpty) {
        zipCode = zipCodeRaw;
        print('✅ Zipcode procesado: $zipCode (país: $nombrePais)');
      } else if (isCuba) {
        print('ℹ️ Zipcode NO procesado: País es Cuba (Cuba no usa códigos postales para entregas)');
      } else if (!procesarZipcode) {
        print('ℹ️ Zipcode NO procesado: Ajuste desactivado');
      }
      
      // Guardar nombre del país procesado para logging (no se guarda en BD porque pais_destino no existe)
      final paisDestinoFinal = nombrePais;
      print('🌍 País de destino procesado: "$paisDestinoFinal" (código original: "$countryUpper")');

      // IMPORTANTE: La dirección se construye diferente según si es pickup o no
      // - Si es PICKUP: shipping_address contiene la dirección de la TIENDA (no del cliente)
      // - Si NO es pickup: shipping_address contiene la dirección del CLIENTE
      // Por ahora construimos la dirección, luego la ajustaremos si es pickup
      // NOTA: Detectamos pickup ANTES de construir la dirección para saber qué estamos extrayendo
      final shippingTypeRaw = (goodbarberOrder['shipping_type'] ?? '').toString().toLowerCase();
      final shippingMethodRaw = (goodbarberOrder['shipping_method'] ?? '').toString().toLowerCase();
      final isPickupPreCheck = shippingTypeRaw == 'pickup' || 
                                shippingMethodRaw.contains('pickup') ||
                                shippingMethodRaw.contains('store') ||
                                shippingMethodRaw.contains('recoger') ||
                                shippingMethodRaw.contains('almacén') ||
                                shippingMethodRaw.contains('almacen') ||
                                shippingMethodRaw.contains('sucursal');
      
      // Construir dirección completa desde shipping_address
      // IMPORTANTE: Cuando es pickup, esta dirección ES la de la tienda
      final direccionCompleta = localizedAddress.isNotEmpty 
          ? localizedAddress
          : [
              street,
              if (extra.isNotEmpty) extra,
              city,
              state,
              if (zipCode.isNotEmpty) zipCode,
              country,
            ].where((e) => e.isNotEmpty).join(', ');
      
      if (isPickupPreCheck) {
        print('   📍 Dirección desde shipping_address (PICKUP - es dirección de TIENDA): $direccionCompleta');
      } else {
        print('   📍 Dirección desde shipping_address (ENVÍO NORMAL - es dirección del CLIENTE): $direccionCompleta');
      }

      // Extraer items de la orden (GoodBarber usa 'items' no 'line_items')
      final lineItems = goodbarberOrder['items'] ?? goodbarberOrder['line_items'] ?? [];
      final descripcionItems = lineItems
          .map<String>((item) {
            final quantity = item['quantity'] ?? 1;
            // GoodBarber usa item['product']['title'] no item['name']
            final productTitle = item['product']?['title'] ?? item['name'] ?? 'Producto';
            return '${quantity}x $productTitle';
          })
          .join(', ');
      final descripcion = descripcionItems.isNotEmpty 
          ? descripcionItems 
          : 'Pedido de GoodBarber #${goodbarberOrder['id'] ?? 'N/A'}';

      // Calcular peso total
      // GoodBarber puede tener el peso directamente en la orden o en los items
      double? pesoTotal;
      try {
        // Primero intentar obtener el peso directamente de la orden
        final orderWeight = goodbarberOrder['weight'];
        if (orderWeight != null) {
          pesoTotal = orderWeight is num ? orderWeight.toDouble() : double.tryParse(orderWeight.toString());
        }
        
        // Si no hay peso en la orden, intentar sumar pesos de los items
        if (pesoTotal == null || pesoTotal == 0.0) {
          double pesoItems = 0.0;
          for (final item in lineItems) {
            final weight = item['weight'];
            final quantity = item['quantity'] ?? 1;
            if (weight != null) {
              final itemWeight = weight is num ? weight.toDouble() : double.tryParse(weight.toString()) ?? 0.0;
              pesoItems += itemWeight * (quantity is int ? quantity : int.tryParse(quantity.toString()) ?? 1);
            }
          }
          if (pesoItems > 0.0) {
            pesoTotal = pesoItems;
          }
        }
        
        if (pesoTotal == 0.0) pesoTotal = null;
      } catch (e) {
        print('⚠️ Error calculando peso: $e');
        pesoTotal = null;
      }

      // Calcular cantidad de bultos
      // IMPORTANTE: GoodBarber NO envía este campo, por lo tanto siempre usar 1
      int cantidadBultos = 1;
      print('ℹ️ GoodBarber no envía cantidad de bultos, usando valor por defecto: 1');

      // Extraer precio total y shipping_amount
      final total = goodbarberOrder['total'];
      double? precioTotalEnvio;
      if (total != null) {
        precioTotalEnvio = total is num ? total.toDouble() : double.tryParse(total.toString());
      }

      // Extraer shipping_amount de GoodBarber
      final shippingAmount = goodbarberOrder['shipping_amount'];
      double? shippingAmountValue;
      if (shippingAmount != null) {
        shippingAmountValue = shippingAmount is num 
            ? shippingAmount.toDouble() 
            : double.tryParse(shippingAmount.toString());
      }

      // Si usarTotalGoodBarber está activado, usar el total de GoodBarber directamente
      // sin recalcular basado en libras. Esto asegura que el precio coincida exactamente con GoodBarber.
      if (usarTotalGoodBarber && precioTotalEnvio != null && precioTotalEnvio > 0) {
        print('✅ Usando total de GoodBarber directamente: $precioTotalEnvio (sin recalcular basado en libras)');
        // precioTotalEnvio ya está establecido con el total de GoodBarber
      } else if (usarTotalGoodBarber && (precioTotalEnvio == null || precioTotalEnvio <= 0)) {
        print('⚠️ Total de GoodBarber no disponible o es 0, usando cálculo normal');
      } else if (!usarTotalGoodBarber) {
        // Si NO usarTotalGoodBarber, aplicar lógica normal de shipping_amount
        // Si usarShippingAmount está activado, usar shipping_amount en lugar de precio_total_envio
        if (usarShippingAmount && shippingAmountValue != null && shippingAmountValue > 0) {
          precioTotalEnvio = shippingAmountValue;
          print('✅ Usando shipping_amount de GoodBarber: $shippingAmountValue (reemplaza precio_total_envio)');
        } else if (usarShippingAmount && (shippingAmountValue == null || shippingAmountValue <= 0)) {
          print('⚠️ shipping_amount no disponible o es 0, usando precio_total_envio normal');
        }
      }

      // Extraer moneda
      final currency = goodbarberOrder['currency'] ?? 'USD';
      final monedaPrecioTotalEnvio = currency.toString().toUpperCase();
      
      // Guardar shipping_amount en items_adicionales para mostrarlo en tarjetas
      // (si está habilitado y disponible)
      List<Map<String, dynamic>>? itemsAdicionales = null;
      if (usarShippingAmount && shippingAmountValue != null && shippingAmountValue > 0) {
        itemsAdicionales = [
          {
            'nombre': 'Costo de Envío (GoodBarber)',
            'precio': shippingAmountValue,
            'cantidad': 1,
          }
        ];
        print('✅ shipping_amount guardado en items_adicionales para mostrar en tarjetas');
      }

      // Extraer estado y mapearlo
      final estadoGoodBarber = goodbarberOrder['status'] ?? 'pending';
      final estadoLogiFlow = mapearEstadoGoodBarberALogiFlow(estadoGoodBarber);

      // Extraer fecha de creación
      DateTime fechaCreacion = DateTime.now();
      try {
        if (goodbarberOrder['created_at'] != null) {
          fechaCreacion = DateTime.parse(goodbarberOrder['created_at']);
        }
      } catch (e) {
        print('⚠️ Error parseando fecha: $e');
      }

      // Extraer notas del cliente (customer_note es el campo donde el cliente escribe notas para el envío)
      final customerNote = goodbarberOrder['customer_note'] ?? '';
      final notes = goodbarberOrder['notes'] ?? customerNote;
      
      if (customerNote.isNotEmpty) {
        print('📝 Nota del cliente encontrada: $customerNote');
      } else if (notes.isNotEmpty) {
        print('📝 Nota general encontrada: $notes');
      } else {
        print('ℹ️ No hay notas en la orden');
      }

      // Validar que tenemos los campos mínimos requeridos
      if (customerName.isEmpty) {
        print('⚠️ ADVERTENCIA: No se encontró nombre del destinatario');
        // Intentar usar email como fallback
        if (customerEmail.isNotEmpty) {
          final emailParts = customerEmail.split('@');
          final nombreFallback = emailParts.isNotEmpty ? emailParts[0] : 'Cliente GoodBarber';
          print('   Usando email como nombre: $nombreFallback');
        }
      }
      
      if (customerPhoneFinal.isEmpty) {
        print('⚠️ ADVERTENCIA: No se encontró teléfono del destinatario');
        print('   VolonexPro+ requiere teléfono, pero GoodBarber no lo proporcionó');
      }
      
      if (direccionCompleta.isEmpty) {
        print('⚠️ ADVERTENCIA: No se encontró dirección de envío');
      }

      // Extraer número de orden de GoodBarber (order_num)
      // Este es el número de orden que muestra GoodBarber al cliente y la empresa
      // Lo usaremos como numero_orden en VolonexPro+ para mantener consistencia
      final orderNum = goodbarberOrder['order_num'];
      String? numeroOrdenGoodBarber;
      if (orderNum != null) {
        numeroOrdenGoodBarber = orderNum.toString();
        print('📋 Número de orden de GoodBarber encontrado: $numeroOrdenGoodBarber');
      } else {
        print('ℹ️ No se encontró order_num en GoodBarber, se generará automáticamente en VolonexPro+');
      }

      // Detectar método de envío de GoodBarber
      // Si es "pickup", "store_pickup", "recoger en almacén", "en el almacén recoger", etc., activar recoger_en_sucursal en VolonexPro+
      final shippingType = (goodbarberOrder['shipping_type'] ?? '').toString().toLowerCase();
      final shippingMethod = (goodbarberOrder['shipping_method'] ?? '').toString().toLowerCase();
      
      // Logging detallado para diagnosticar
      print('🔍 ===== DETECTANDO MÉTODO DE ENVÍO =====');
      print('   shipping_type: "$shippingType" (raw: "${goodbarberOrder['shipping_type']}")');
      print('   shipping_method: "$shippingMethod" (raw: "${goodbarberOrder['shipping_method']}")');
      print('   shipping_type es null?: ${goodbarberOrder['shipping_type'] == null}');
      print('   shipping_method es null?: ${goodbarberOrder['shipping_method'] == null}');
      
      // Mostrar TODOS los campos de la orden para debugging (especialmente los relacionados con shipping)
      print('');
      print('📋 ===== CAMPOS RELEVANTES DE LA ORDEN GOODBARBER =====');
      final camposRelevantesParaLog = <String, dynamic>{};
      goodbarberOrder.forEach((key, value) {
        final keyLower = key.toString().toLowerCase();
        // Mostrar campos relacionados con shipping, pickup, store, address, o cualquier campo no-null relevante
        if (keyLower.contains('shipping') ||
            keyLower.contains('pickup') ||
            keyLower.contains('store') ||
            keyLower.contains('address') ||
            keyLower.contains('delivery') ||
            keyLower.contains('method') ||
            keyLower.contains('type') ||
            (value != null && !keyLower.contains('thumbnails') && !keyLower.contains('image'))) {
          camposRelevantesParaLog[key] = value;
        }
      });
      
      // Mostrar campos relevantes de forma organizada
      print('   📦 Campos de Shipping:');
      print('      - shipping_type: "${goodbarberOrder['shipping_type']}" (tipo: ${goodbarberOrder['shipping_type']?.runtimeType})');
      print('      - shipping_method: "${goodbarberOrder['shipping_method']}" (tipo: ${goodbarberOrder['shipping_method']?.runtimeType})');
      print('      - shipping_amount: ${goodbarberOrder['shipping_amount']}');
      print('      - shipping_type después de lowercase: "$shippingType"');
      print('      - shipping_method después de lowercase: "$shippingMethod"');
      print('   📍 Campos de Address:');
      if (goodbarberOrder['shipping_address'] != null) {
        final addr = goodbarberOrder['shipping_address'] as Map?;
        print('      - shipping_address.street: ${addr?['street']}');
        print('      - shipping_address.city: ${addr?['city']}');
        print('      - shipping_address.state: ${addr?['state']}');
        print('      - shipping_address.country: ${addr?['country']}');
        print('      - shipping_address.localized_address: ${addr?['localized_address']}');
      } else {
        print('      - shipping_address: NULL');
      }
      print('   🏪 Campos de Store/Pickup:');
      print('      - store_address: ${goodbarberOrder['store_address']}');
      print('      - pickup_address: ${goodbarberOrder['pickup_address']}');
      print('      - store_location: ${goodbarberOrder['store_location']}');
      print('      - pickup_location: ${goodbarberOrder['pickup_location']}');
      print('      - store: ${goodbarberOrder['store']}');
      print('      - pickup_store: ${goodbarberOrder['pickup_store']}');
      print('   📋 Otros campos importantes:');
      print('      - status: ${goodbarberOrder['status']}');
      print('      - order_num: ${goodbarberOrder['order_num']}');
      print('      - id: ${goodbarberOrder['id']}');
      print('==================================================');
      print('');
      
      // Buscar en TODOS los campos posibles que GoodBarber pueda usar para indicar pickup
      print('   📋 Buscando indicadores de pickup en TODOS los campos de la orden...');
      final todosLosCampos = goodbarberOrder.keys.toList();
      final camposRelevantes = <String, dynamic>{};
      for (final key in todosLosCampos) {
        final keyLower = key.toString().toLowerCase();
        final value = goodbarberOrder[key];
        if (keyLower.contains('pickup') || 
            keyLower.contains('store') || 
            keyLower.contains('recoger') ||
            keyLower.contains('almacén') ||
            keyLower.contains('almacen') ||
            keyLower.contains('sucursal') ||
            keyLower.contains('shipping')) {
          camposRelevantes[key] = value;
          print('      - $key: $value');
        }
      }
      
      // Detectar pickup en inglés y español
      // IMPORTANTE: Según documentación GoodBarber, shipping_type puede ser exactamente "pickup"
      bool isPickup = false;
      
      // Verificación exacta primero (más confiable)
      if (shippingType == 'pickup' || shippingMethod == 'pickup') {
        isPickup = true;
        print('   ✅ PICKUP DETECTADO: shipping_type o shipping_method es exactamente "pickup"');
      }
      
      // Verificaciones parciales
      if (!isPickup) {
        if (shippingType.contains('pickup') || 
            shippingType.contains('store') ||
            shippingMethod.contains('pickup') ||
            shippingMethod.contains('store') ||
            // Español - variantes comunes
            shippingType.contains('recoger') ||
            shippingType.contains('almacén') ||
            shippingType.contains('almacen') ||
            shippingType.contains('sucursal') ||
            shippingMethod.contains('recoger') ||
            shippingMethod.contains('almacén') ||
            shippingMethod.contains('almacen') ||
            shippingMethod.contains('sucursal') ||
            // Variantes específicas de GoodBarber
            shippingType.contains('en el almacén recoger') ||
            shippingMethod.contains('en el almacén recoger') ||
            shippingType.contains('recoger en almacén') ||
            shippingMethod.contains('recoger en almacén')) {
          isPickup = true;
          print('   ✅ PICKUP DETECTADO: encontrado en shipping_type o shipping_method (verificación parcial)');
        }
      }
      
      // Buscar en otros campos de la orden (puede que GoodBarber use otros campos)
      if (!isPickup) {
        for (final entry in camposRelevantes.entries) {
          final key = entry.key.toString().toLowerCase();
          final value = entry.value?.toString().toLowerCase() ?? '';
          if (value.contains('pickup') || 
              value.contains('store') ||
              value.contains('recoger') ||
              value.contains('almacén') ||
              value.contains('almacen') ||
              value.contains('sucursal')) {
            isPickup = true;
            print('   ✅ PICKUP DETECTADO: encontrado en campo "$key" con valor "$value"');
            break;
          }
        }
      }
      
      if (!isPickup) {
        print('   ❌ NO se detectó pickup - será tratado como envío normal');
      }
      
      bool recogerEnSucursal = false;
      String? direccionSucursalGoodBarber;
      
      if (isPickup) {
        print('🏪 ✅ MÉTODO DE ENVÍO DETECTADO: RECOGER EN ALMACÉN/TIENDA');
        print('   ✅ Activando recoger_en_sucursal = true');
        recogerEnSucursal = true;
        
        // IMPORTANTE: Cuando es pickup, GoodBarber NO envía dirección del cliente
        // En su lugar, debe enviar la dirección de la tienda configurada en GoodBarber
        // Buscar en múltiples campos posibles donde puede estar la dirección de la tienda
        
        print('🔍 Buscando dirección de tienda en campos de GoodBarber...');
        print('   - goodbarberOrder[\'store_address\']: ${goodbarberOrder['store_address']}');
        print('   - goodbarberOrder[\'pickup_address\']: ${goodbarberOrder['pickup_address']}');
        print('   - goodbarberOrder[\'store_location\']: ${goodbarberOrder['store_location']}');
        print('   - goodbarberOrder[\'pickup_location\']: ${goodbarberOrder['pickup_location']}');
        print('   - goodbarberOrder[\'store\']: ${goodbarberOrder['store']}');
        print('   - goodbarberOrder[\'pickup_store\']: ${goodbarberOrder['pickup_store']}');
        print('   - goodbarberOrder[\'store_name\']: ${goodbarberOrder['store_name']}');
        print('   - goodbarberOrder[\'pickup_store_name\']: ${goodbarberOrder['pickup_store_name']}');
        print('');
        print('📋 TODOS LOS CAMPOS DISPONIBLES EN LA ORDEN (para debugging):');
        print('   🔍 Buscando TODOS los campos que puedan contener dirección de pickup...');
        goodbarberOrder.forEach((key, value) {
          final keyLower = key.toString().toLowerCase();
          // Mostrar TODOS los campos relacionados con store, pickup, address, location, delivery, slot
          if (keyLower.contains('store') || 
              keyLower.contains('pickup') ||
              keyLower.contains('address') ||
              keyLower.contains('location') ||
              keyLower.contains('delivery') ||
              keyLower.contains('slot') ||
              keyLower.contains('branch') ||
              keyLower.contains('shop') ||
              keyLower.contains('warehouse')) {
            print('   - $key: $value');
          }
        });
        print('');
        print('📋 🔥 TODOS LOS CAMPOS DE LA ORDEN (COMPLETO - para encontrar dirección de pickup):');
        goodbarberOrder.forEach((key, value) {
          print('   - $key: ${value.toString().length > 200 ? value.toString().substring(0, 200) + "..." : value}');
        });
        print('');
        
        // 🔍 Buscar en selected_delivery_slot (puede contener información de pickup)
        if (goodbarberOrder['selected_delivery_slot'] != null) {
          print('🔍 🔍 🔍 selected_delivery_slot encontrado:');
          final deliverySlot = goodbarberOrder['selected_delivery_slot'];
          if (deliverySlot is Map) {
            deliverySlot.forEach((key, value) {
              print('   - selected_delivery_slot.$key: $value');
            });
          } else {
            print('   - selected_delivery_slot (raw): $deliverySlot');
          }
        }
        
        // 🔍 Buscar en pricing_details (puede contener información de pickup)
        if (goodbarberOrder['pricing_details'] != null) {
          print('🔍 🔍 🔍 pricing_details encontrado:');
          final pricingDetails = goodbarberOrder['pricing_details'];
          if (pricingDetails is Map) {
            pricingDetails.forEach((key, value) {
              print('   - pricing_details.$key: $value');
            });
          } else {
            print('   - pricing_details (raw): $pricingDetails');
          }
        }
        print('');
        
        // 🔥 BÚSQUEDA MEJORADA: Buscar dirección de tienda en TODOS los campos posibles (incluyendo anidados)
        // Prioridad: store_address > pickup_address > store_location > pickup_location > store > selected_delivery_slot > shipping_address (cuando es pickup)
        String? storeAddress;
        
        // 1. Campos directos
        storeAddress = goodbarberOrder['store_address']?.toString() ?? 
                      goodbarberOrder['pickup_address']?.toString() ??
                      goodbarberOrder['store_location']?.toString() ??
                      goodbarberOrder['pickup_location']?.toString();
        
        // 2. Campos anidados en objetos 'store' o 'pickup_store'
        if (storeAddress == null || storeAddress.isEmpty) {
          if (goodbarberOrder['store'] is Map) {
            final store = goodbarberOrder['store'] as Map;
            storeAddress = store['address']?.toString() ?? 
                          store['location']?.toString() ??
                          store['street']?.toString() ??
                          store['localized_address']?.toString();
            if (storeAddress != null && storeAddress.isNotEmpty) {
              print('   ✅ Dirección encontrada en goodbarberOrder[\'store\']: $storeAddress');
            }
          }
        }
        
        if (storeAddress == null || storeAddress.isEmpty) {
          if (goodbarberOrder['pickup_store'] is Map) {
            final pickupStore = goodbarberOrder['pickup_store'] as Map;
            storeAddress = pickupStore['address']?.toString() ?? 
                          pickupStore['location']?.toString() ??
                          pickupStore['street']?.toString() ??
                          pickupStore['localized_address']?.toString();
            if (storeAddress != null && storeAddress.isNotEmpty) {
              print('   ✅ Dirección encontrada en goodbarberOrder[\'pickup_store\']: $storeAddress');
            }
          }
        }
        
        // 3. Buscar en selected_delivery_slot (puede contener información de pickup)
        if (storeAddress == null || storeAddress.isEmpty) {
          if (goodbarberOrder['selected_delivery_slot'] is Map) {
            final deliverySlot = goodbarberOrder['selected_delivery_slot'] as Map;
            storeAddress = deliverySlot['address']?.toString() ?? 
                          deliverySlot['location']?.toString() ??
                          deliverySlot['store_address']?.toString() ??
                          deliverySlot['pickup_address']?.toString() ??
                          deliverySlot['localized_address']?.toString();
            if (storeAddress != null && storeAddress.isNotEmpty) {
              print('   ✅ Dirección encontrada en selected_delivery_slot: $storeAddress');
            }
          }
        }
        
        // 4. Buscar en shipping_method (puede contener el nombre de la tienda con dirección)
        if (storeAddress == null || storeAddress.isEmpty) {
          final shippingMethod = goodbarberOrder['shipping_method']?.toString() ?? '';
          // Si shipping_method contiene información de dirección (ej: "Recogida en Tienda [Dirección]")
          if (shippingMethod.contains('Tienda') || shippingMethod.contains('Store')) {
            // Intentar extraer dirección del método de envío si está incluida
            print('   ℹ️ shipping_method contiene información de tienda: $shippingMethod');
            // Por ahora, no extraemos la dirección de aquí, pero lo registramos
          }
        }
        
        // 🔥 CORRECCIÓN CRÍTICA: shipping_address contiene la dirección del CLIENTE, NO de la tienda
        // Los logs confirman que shipping_address tiene first_name/last_name del cliente (Javier Alejo)
        // Por lo tanto, NO debemos usar shipping_address cuando es pickup
        // 
        // Buscar dirección de tienda en otros campos de GoodBarber o usar sucursal de VolonexPro+
        String direccionTiendaFinal = '';
        
        // Primero buscar en campos específicos de GoodBarber (si existen)
        if (storeAddress != null && storeAddress.toString().isNotEmpty) {
          direccionTiendaFinal = storeAddress.toString();
          print('   ✅ Dirección de tienda encontrada en campo específico de GoodBarber: $direccionTiendaFinal');
        } else {
          print('   ⚠️ ADVERTENCIA: No se encontró dirección de tienda en campos específicos de GoodBarber');
          print('   ⚠️ shipping_address contiene la dirección del CLIENTE (Javier Alejo), NO de la tienda');
          print('   🔄 Usando OPCIÓN 2: Sucursal principal de VolonexPro+ como fallback...');
          
          // OPCIÓN 2: Usar sucursal principal de VolonexPro+ cuando no encontramos dirección en GoodBarber
          try {
            final supabase = Supabase.instance.client;
            final sucursalPrincipal = await supabase
                .from('sucursales')
                .select('*')
                .eq('tenant_id', tenantId)
                .eq('es_principal', true)
                .maybeSingle();
            
            if (sucursalPrincipal != null && sucursalPrincipal['direccion'] != null) {
              direccionTiendaFinal = sucursalPrincipal['direccion'].toString();
              print('   ✅ Usando sucursal principal de VolonexPro+: $direccionTiendaFinal');
              print('   ℹ️ NOTA: Esta es la sucursal registrada en VolonexPro+ para este tenant');
            } else {
              print('   ⚠️ No se encontró sucursal principal en VolonexPro+');
              // Intentar buscar cualquier sucursal del tenant
              final cualquierSucursal = await supabase
                  .from('sucursales')
                  .select('*')
                  .eq('tenant_id', tenantId)
                  .limit(1)
                  .maybeSingle();
              
              if (cualquierSucursal != null && cualquierSucursal['direccion'] != null) {
                direccionTiendaFinal = cualquierSucursal['direccion'].toString();
                print('   ✅ Usando primera sucursal encontrada de VolonexPro+: $direccionTiendaFinal');
              } else {
                print('   ❌ No se encontró ninguna sucursal en VolonexPro+ para este tenant');
                direccionTiendaFinal = '⚠️ Dirección de tienda no disponible - Configurar sucursal en VolonexPro+ o verificar en GoodBarber';
              }
            }
          } catch (e) {
            print('   ❌ Error buscando sucursal en VolonexPro+: $e');
            direccionTiendaFinal = '⚠️ Dirección de tienda no disponible - Error al buscar sucursal';
          }
        }
        
        // direccionTiendaFinal siempre tiene un valor asignado (puede ser un string de error)
        if (direccionTiendaFinal.isNotEmpty) {
          direccionSucursalGoodBarber = direccionTiendaFinal;
          print('   ✅ ✅ ✅ Dirección de tienda FINAL asignada: $direccionSucursalGoodBarber');
        } else {
          direccionSucursalGoodBarber = '⚠️ Dirección de tienda no disponible - Configurar sucursal en VolonexPro+';
          print('   ❌ No se pudo obtener dirección de tienda de ninguna fuente');
        }
      } else {
        print('🚚 Método de envío detectado: ENVÍO NORMAL (no pickup)');
        print('   ℹ️ recoger_en_sucursal = false (envío normal de reparto)');
        print('   ℹ️ Se usará dirección del cliente desde shipping_address');
      }
      
      print('');
      print('📋 ===== RESULTADO FINAL DE DETECCIÓN =====');
      print('   recoger_en_sucursal: $recogerEnSucursal');
      print('   direccionSucursalGoodBarber: ${direccionSucursalGoodBarber ?? "NO ASIGNADA"}');
      if (recogerEnSucursal) {
        print('   ✅ ORDEN CONFIGURADA COMO RECOGER EN SUCURSAL');
        if (direccionSucursalGoodBarber != null && direccionSucursalGoodBarber.isNotEmpty) {
          print('   ✅ Dirección de tienda disponible: $direccionSucursalGoodBarber');
        } else {
          print('   ⚠️ ADVERTENCIA: recoger_en_sucursal = true pero NO hay dirección de tienda');
        }
      } else {
        print('   ✅ ORDEN CONFIGURADA COMO ENVÍO NORMAL');
      }
      print('==========================================');
      print('');

      // Construir datos de la orden para VolonexPro+
      // IMPORTANTE: Emisor es la empresa (tienda GoodBarber), Destinatario es el cliente
      final ordenData = {
        'emisor_nombre': emisorNombre, // ✅ Nombre de la empresa (tienda GoodBarber)
        'destinatario_nombre': customerName.isNotEmpty 
            ? customerName 
            : (customerEmail.isNotEmpty 
                ? customerEmail.split('@')[0] 
                : 'Cliente GoodBarber #${goodbarberOrder['id']}'),
        // Si es pickup, usar SOLO la dirección de la tienda (NUNCA la dirección del cliente)
        // Si no hay dirección de tienda disponible, mostrar mensaje indicando que debe verificarse en GoodBarber
        // Si NO es pickup, usar la dirección de envío normal (dirección del cliente)
        'direccion_destino': recogerEnSucursal
            ? (direccionSucursalGoodBarber != null && direccionSucursalGoodBarber.isNotEmpty
                ? direccionSucursalGoodBarber
                : '⚠️ Dirección de tienda no disponible - Verificar en GoodBarber (orden pickup)')
            : (direccionCompleta.isNotEmpty 
                ? direccionCompleta 
                : 'Dirección no especificada - Verificar en GoodBarber'),
        'telefono_destinatario': customerPhoneFinal.isNotEmpty 
            ? customerPhoneFinal 
            : null, // ⚠️ Puede ser null si GoodBarber no lo proporciona
        'provincia_destino': state.isNotEmpty ? state : null,
        'municipio_destino': city.isNotEmpty ? city : null,
        // NOTA: pais_destino no existe en la tabla ordenes, pero el mapeo de países
        // se usa para determinar si es Cuba y procesar zipcode correctamente
        'descripcion': descripcion,
        'estado': estadoLogiFlow,
        'fecha_creacion': fechaCreacion.toIso8601String(),
        'peso': pesoTotal,
        'cantidad_bultos': cantidadBultos,
        'precio_total_envio': precioTotalEnvio,
        'moneda_precio_total_envio': monedaPrecioTotalEnvio,
        'notas': notes.isNotEmpty ? notes : null,
        'tenant_id': tenantId,
        // ✅ Activar recoger_en_sucursal si GoodBarber usa pickup
        'recoger_en_sucursal': recogerEnSucursal,
        // Guardar shipping_amount en items_adicionales si está habilitado
        if (itemsAdicionales != null) 'items_adicionales': itemsAdicionales,
        // ✅ Usar el número de orden de GoodBarber si está disponible
        // Si no está disponible, el trigger de BD generará uno automáticamente
        if (numeroOrdenGoodBarber != null && numeroOrdenGoodBarber.isNotEmpty)
          'numero_orden': numeroOrdenGoodBarber,
        'goodbarber_order_id': goodbarberOrder['id'] is int 
            ? goodbarberOrder['id'] 
            : int.tryParse(goodbarberOrder['id'].toString()),
        'goodbarber_app_id': appId, // ✅ Usar el appId pasado como parámetro
        'creado_por_nombre': 'GoodBarber Sync',
        'requiere_pago': false, // Por defecto, las órdenes de GoodBarber ya están pagadas
        'pagado': true, // Las órdenes de GoodBarber vienen pagadas
        'moneda': monedaPrecioTotalEnvio,
      };

      print('');
      print('✅ Orden mapeada exitosamente:');
      print('   GoodBarber ID: ${goodbarberOrder['id']}');
      print('   Número de orden GoodBarber: ${numeroOrdenGoodBarber ?? "Se generará automáticamente"}');
      print('   Estado: $estadoGoodBarber → $estadoLogiFlow');
      print('   Emisor: $emisorNombre');
      print('   Destinatario: $customerName');
      print('   Teléfono: ${customerPhoneFinal.isNotEmpty ? customerPhoneFinal : "NO DISPONIBLE"}');
      // Mostrar dirección final que se guardará
      final direccionFinal = recogerEnSucursal
          ? (direccionSucursalGoodBarber != null && direccionSucursalGoodBarber.isNotEmpty
              ? direccionSucursalGoodBarber
              : '⚠️ Dirección de tienda no disponible - Verificar en GoodBarber (orden pickup)')
          : direccionCompleta;
      print('   Dirección FINAL (que se guardará): ${direccionFinal.isNotEmpty ? direccionFinal : "NO DISPONIBLE"}');
      if (recogerEnSucursal) {
        if (direccionSucursalGoodBarber != null && direccionSucursalGoodBarber.isNotEmpty) {
          print('   ✅ Es recoger en sucursal - Dirección de tienda: $direccionSucursalGoodBarber');
        } else {
          print('   ⚠️ Es recoger en sucursal - Dirección de tienda NO DISPONIBLE (GoodBarber no la envió)');
          print('   ⚠️ NO se usará la dirección del cliente porque es pickup');
        }
      } else {
        print('   ✅ Es envío normal - Dirección del cliente: $direccionCompleta');
      }
      print('   Items: $descripcionItems');
      print('   Precio total: $precioTotalEnvio $monedaPrecioTotalEnvio');
      print('   Peso: ${pesoTotal ?? "NO DISPONIBLE"}');
      print('   Notas: ${notes.isNotEmpty ? notes : "Sin notas"}');
      print('   Recoger en Sucursal: $recogerEnSucursal');
      print('🔍 ===== FIN MAPEO =====');
      print('');

      return ordenData;
    } catch (e, stackTrace) {
      print('❌ Error mapeando orden de GoodBarber: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Actualiza el estado de una orden en GoodBarber
  /// Obtiene una orden completa desde GoodBarber (incluye toda la información de shipping)
  /// Según la documentación: GET /publicapi/v2/general/orders/{webzine_id}/order/{order_id}/
  /// [apiKey] API Key de GoodBarber
  /// [appId] App ID de GoodBarber (webzine_id)
  /// [orderId] ID de la orden en GoodBarber
  /// Retorna un Map con la orden completa o null si hay error
  static Future<Map<String, dynamic>?> obtenerOrdenCompleta(
    String apiKey,
    int appId,
    int orderId,
  ) async {
    try {
      // Endpoint para obtener la orden completa (según documentación: Retrieve an order)
      final url = '$baseUrl/general/orders/$appId/order/$orderId/';
      
      print('📦 [ORDEN COMPLETA] Obteniendo orden completa desde GoodBarber...');
      print('   URL: $url');
      print('   Order ID: $orderId');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'token': apiKey,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        print('✅ [ORDEN COMPLETA] Orden completa obtenida exitosamente');
        print('   📋 Campos disponibles: ${data.keys.join(", ")}');
        print('   📦 shipping_type: ${data['shipping_type']}');
        print('   📦 shipping_method: ${data['shipping_method']}');
        print('   📦 shipping_address: ${data['shipping_address']}');
        print('   📦 store_address: ${data['store_address']}');
        print('   📦 pickup_address: ${data['pickup_address']}');
        print('   📦 store: ${data['store']}');
        print('   📦 pickup_store: ${data['pickup_store']}');
        
        // 🔥 LOGGING DETALLADO: Mostrar TODOS los campos relacionados con pickup/store
        print('');
        print('🔍 🔍 🔍 [ORDEN COMPLETA] BUSCANDO CAMPOS DE PICKUP/STORE 🔍 🔍 🔍');
        data.forEach((key, value) {
          final keyLower = key.toLowerCase();
          if (keyLower.contains('store') || 
              keyLower.contains('pickup') ||
              keyLower.contains('branch') ||
              keyLower.contains('warehouse') ||
              keyLower.contains('location') ||
              keyLower.contains('delivery_slot') ||
              keyLower.contains('shipping')) {
            print('   📍 $key: ${value is Map ? json.encode(value) : value}');
            
            // Si es un objeto, explorar sus campos anidados
            if (value is Map) {
              value.forEach((nestedKey, nestedValue) {
                final nestedKeyLower = nestedKey.toString().toLowerCase();
                if (nestedKeyLower.contains('address') ||
                    nestedKeyLower.contains('location') ||
                    nestedKeyLower.contains('name') ||
                    nestedKeyLower.contains('street') ||
                    nestedKeyLower.contains('city') ||
                    nestedKeyLower.contains('state') ||
                    nestedKeyLower.contains('country')) {
                  print('      └─ $nestedKey: $nestedValue');
                }
              });
            }
          }
        });
        print('🔍 🔍 🔍 FIN BÚSQUEDA DE CAMPOS PICKUP/STORE 🔍 🔍 🔍');
        print('');
        
        return data;
      } else {
        print('❌ [ORDEN COMPLETA] Error al obtener orden completa: ${response.statusCode}');
        print('   Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ [ORDEN COMPLETA] Error obteniendo orden completa: $e');
      return null;
    }
  }

  /// Según la documentación: PATCH /publicapi/v2/general/orders/{webzine_id}/order/{order_id}/shipping/
  /// [apiKey] API Key de GoodBarber
  /// [appId] App ID de GoodBarber (webzine_id)
  /// [orderId] ID de la orden en GoodBarber
  /// [nuevoEstado] Nuevo estado (PENDING, FULFILLED o DELIVERED)
  static Future<Map<String, dynamic>> actualizarEstadoOrdenGoodBarber(
    String apiKey,
    int appId,
    int orderId,
    String nuevoEstado,
  ) async {
    try {
      final cleanApiKey = apiKey.trim().replaceAll(RegExp(r'\s+'), '');
      
      // URL correcta según documentación: /general/orders/{webzine_id}/order/{order_id}/shipping/
      final url = '$baseUrl/general/orders/$appId/order/$orderId/shipping/';

      print('🔄 Actualizando estado en GoodBarber...');
      print('   URL: $url');
      print('   Order ID: $orderId');
      print('   Nuevo estado: $nuevoEstado');

      // El estado ya viene mapeado desde mapearEstadoLogiFlowAGoodBarber
      // Solo puede ser 'FULFILLED' o 'DELIVERED' (GoodBarber no permite PENDING)
      final estadoGoodBarber = nuevoEstado.toUpperCase();
      
      // Validar que el estado sea válido
      if (estadoGoodBarber != 'FULFILLED' && estadoGoodBarber != 'DELIVERED' && estadoGoodBarber != 'CANCELLED') {
        print('❌ Error: GoodBarber solo permite FULFILLED, DELIVERED o CANCELLED, recibido: $estadoGoodBarber');
        return {
          'exito': false,
          'error': 'Estado inválido',
          'mensaje': 'GoodBarber solo permite actualizar a FULFILLED, DELIVERED o CANCELLED',
        };
      }

      final response = await http.patch(
        Uri.parse(url),
        headers: {
          'token': cleanApiKey, // ✅ Método que funciona
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'status': estadoGoodBarber, // FULFILLED, DELIVERED o CANCELLED
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('✅ Estado actualizado exitosamente en GoodBarber');
        return {
          'exito': true,
          'mensaje': 'Estado actualizado exitosamente',
        };
      } else {
        final responseBody = response.body;
        print('❌ Error actualizando estado: ${response.statusCode}');
        print('   Response: $responseBody');
        
        // Manejar errores específicos de GoodBarber
        if (response.statusCode == 400) {
          try {
            final errorJson = json.decode(responseBody);
            final errorCode = errorJson['error_code']?.toString() ?? '';
            final errorDescription = errorJson['error_description']?.toString() ?? '';
            
            // Error 3999: No se puede actualizar a PENDING, al mismo estado, o cambios no permitidos
            // Esto puede pasar cuando intentamos hacer un "descenso" (ej: ENTREGADO → EN TRANSITO, EN TRANSITO → POR ENVIAR)
            // O cuando intentamos cancelar una orden que ya está en un estado avanzado (ej: ENTREGADO → CANCELADA)
            if (errorCode == '3999') {
              print('⚠️ GoodBarber rechazó la actualización: $errorDescription');
              print('   Esto puede ser normal si se intenta hacer un "descenso" de estado o cancelar una orden avanzada');
              // No es un error crítico, solo informativo
              // GoodBarber puede rechazar cambios hacia atrás o cancelaciones según sus políticas
              return {
                'exito': false,
                'error': 'GoodBarber rechazó la actualización',
                'mensaje': errorDescription,
                'no_critico': true, // Marcar como no crítico para evitar loops
              };
            }
          } catch (e) {
            // Si no se puede parsear el JSON, continuar con el error normal
          }
        }
        
        return {
          'exito': false,
          'error': 'HTTP ${response.statusCode}',
          'mensaje': responseBody,
        };
      }
    } catch (e, stackTrace) {
      print('❌ Error actualizando estado en GoodBarber: $e');
      print('   Stack trace: $stackTrace');
      return {
        'exito': false,
        'error': e.toString(),
      };
    }
  }
}

