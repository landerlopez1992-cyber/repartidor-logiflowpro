import 'package:supabase_flutter/supabase_flutter.dart';
import 'goodbarber_service.dart';

/// Servicio para sincronización bidireccional con GoodBarber
class GoodBarberSyncService {
  final SupabaseClient supabase;

  GoodBarberSyncService(this.supabase);

  /// Busca o crea un emisor basado en el nombre de la empresa
  /// Retorna el ID del emisor (existente o nuevo)
  static Future<String?> buscarOCrearEmisor(
    SupabaseClient supabase,
    String tenantId,
    String nombreEmpresa,
    String? email,
  ) async {
    try {
      print('🔍 Buscando emisor existente...');
      print('   - Nombre: $nombreEmpresa');
      print('   - Tenant ID: $tenantId');

      // Buscar emisor existente por nombre y tenant_id
      final emisoresEncontrados = await supabase
          .from('emisores')
          .select('*')
          .eq('tenant_id', tenantId)
          .ilike('nombre', nombreEmpresa.trim())
          .limit(5);

      if (emisoresEncontrados.isNotEmpty) {
        final emisorExistente = emisoresEncontrados[0];
        final emisorId = emisorExistente['id']?.toString();
        print('✅ Emisor existente encontrado: ID=$emisorId, Nombre=${emisorExistente['nombre']}');
        return emisorId;
      }

      // Si no existe, crear nuevo emisor
      print('➕ Creando nuevo emisor...');
      
      final nuevoEmisor = {
        'nombre': nombreEmpresa.trim(),
        'email': email?.trim().isNotEmpty == true ? email?.trim() : null,
        'tenant_id': tenantId,
      };

      final response = await supabase
          .from('emisores')
          .insert(nuevoEmisor)
          .select('id')
          .single();

      final nuevoId = response['id']?.toString();
      print('✅ Nuevo emisor creado: ID=$nuevoId, Nombre=$nombreEmpresa');
      return nuevoId;
    } catch (e, stackTrace) {
      print('❌ Error buscando/creando emisor: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Busca o crea un destinatario basado en los datos de GoodBarber
  /// Retorna el ID del destinatario (existente o nuevo)
  static Future<String?> buscarOCrearDestinatario(
    SupabaseClient supabase,
    String tenantId,
    String nombre,
    String? telefono,
    String direccion,
    String? provincia,
    String? municipio,
    String? email,
  ) async {
    try {
      print('🔍 Buscando destinatario existente...');
      print('   - Nombre: $nombre');
      print('   - Teléfono: $telefono');
      print('   - Dirección: $direccion');
      print('   - Tenant ID: $tenantId');

      // Normalizar teléfono para búsqueda (solo últimos 8 dígitos)
      String? telefonoNormalizado;
      if (telefono != null && telefono.isNotEmpty) {
        final soloDigitos = telefono.replaceAll(RegExp(r'[^\d]'), '');
        if (soloDigitos.length >= 8) {
          telefonoNormalizado = soloDigitos.substring(soloDigitos.length - 8);
        }
      }

      // Buscar destinatario existente por múltiples criterios
      List<Map<String, dynamic>> destinatariosEncontrados = [];

      // Búsqueda 1: Por teléfono (si está disponible)
      if (telefonoNormalizado != null) {
        try {
          final queryTelefono = supabase
              .from('destinatarios')
              .select('*')
              .eq('tenant_id', tenantId)
              .ilike('telefono', '%$telefonoNormalizado');
          
          final resultadosTelefono = await queryTelefono;
          if (resultadosTelefono.isNotEmpty) {
            destinatariosEncontrados.addAll((resultadosTelefono as List).cast<Map<String, dynamic>>());
            print('   ✅ Encontrados ${resultadosTelefono.length} destinatarios por teléfono');
          }
        } catch (e) {
          print('   ⚠️ Error buscando por teléfono: $e');
        }
      }

      // Búsqueda 2: Por nombre y dirección (si no se encontró por teléfono)
      if (destinatariosEncontrados.isEmpty && nombre.isNotEmpty && direccion.isNotEmpty) {
        try {
          final queryNombreDir = supabase
              .from('destinatarios')
              .select('*')
              .eq('tenant_id', tenantId)
              .ilike('nombre', nombre.trim())
              .ilike('direccion', '%${direccion.split(',').first.trim()}%');
          
          final resultadosNombreDir = await queryNombreDir;
          if (resultadosNombreDir.isNotEmpty) {
            destinatariosEncontrados.addAll((resultadosNombreDir as List).cast<Map<String, dynamic>>());
            print('   ✅ Encontrados ${resultadosNombreDir.length} destinatarios por nombre y dirección');
          }
        } catch (e) {
          print('   ⚠️ Error buscando por nombre/dirección: $e');
        }
      }

      // Si encontramos destinatarios, usar el primero
      if (destinatariosEncontrados.isNotEmpty) {
        final destinatarioExistente = destinatariosEncontrados[0];
        final destinatarioId = destinatarioExistente['id']?.toString();
        print('✅ Destinatario existente encontrado: ID=$destinatarioId, Nombre=${destinatarioExistente['nombre']}');
        return destinatarioId;
      }

      // Si no existe, crear nuevo destinatario
      print('➕ Creando nuevo destinatario...');
      
      // Normalizar teléfono para guardar (agregar prefijo si no tiene)
      String? telefonoFinal = telefono;
      if (telefono != null && telefono.isNotEmpty) {
        final soloDigitos = telefono.replaceAll(RegExp(r'[^\d]'), '');
        if (!telefono.startsWith('+')) {
          // Si no tiene prefijo, asumir +53 (Cuba) o +1 (USA) según el país
          // Por ahora, usar +53 como default
          telefonoFinal = '+53$soloDigitos';
        }
      }

      final nuevoDestinatario = {
        'nombre': nombre.trim(),
        'telefono': telefonoFinal,
        'direccion': direccion.trim(),
        'provincia': provincia,
        'municipio': municipio,
        'email': email?.trim().isNotEmpty == true ? email?.trim() : null,
        'tenant_id': tenantId,
      };

      final response = await supabase
          .from('destinatarios')
          .insert(nuevoDestinatario)
          .select('id')
          .single();

      final nuevoId = response['id']?.toString();
      print('✅ Nuevo destinatario creado: ID=$nuevoId, Nombre=$nombre');
      return nuevoId;
    } catch (e, stackTrace) {
      print('❌ Error buscando/creando destinatario: $e');
      print('   Stack trace: $stackTrace');
      return null;
    }
  }

  /// Sincroniza órdenes de GoodBarber a VolonexPro+
  /// [tenantId] ID del tenant
  /// [apiKey] API Key de GoodBarber
  /// [appId] App ID de GoodBarber
  /// [emisorNombre] Nombre del emisor (tienda GoodBarber)
  /// [since] Fecha desde la cual sincronizar (opcional, por defecto últimas 24 horas)
  static Future<Map<String, dynamic>> sincronizarOrdenesDesdeGoodBarber(
    SupabaseClient supabase,
    String tenantId,
    String apiKey,
    int appId,
    String emisorNombre, {
    DateTime? since,
  }) async {
    try {
      print('🔄 ===== INICIANDO SINCRONIZACIÓN DESDE GOODBARBER =====');
      print('   Tenant ID: $tenantId');
      print('   App ID: $appId');
      print('   Emisor: $emisorNombre');

      // Si no se proporciona fecha, usar últimas 24 horas
      final fechaDesde = since ?? DateTime.now().subtract(const Duration(days: 1));
      print('   Sincronizando órdenes desde: ${fechaDesde.toIso8601String()}');

      // Obtener órdenes de GoodBarber
      final resultado = await GoodBarberService.obtenerOrdenesGoodBarber(
        apiKey,
        appId,
        limit: 100, // Obtener hasta 100 órdenes
        since: fechaDesde,
      );

      if (!resultado['exito']) {
        print('❌ Error obteniendo órdenes de GoodBarber: ${resultado['error']}');
        return {
          'exito': false,
          'error': resultado['error'],
          'ordenes_sincronizadas': 0,
          'ordenes_creadas': 0,
          'ordenes_actualizadas': 0,
        };
      }

      final ordenesGoodBarber = resultado['ordenes'] as List;
      print('📦 Órdenes obtenidas de GoodBarber (sin filtrar): ${ordenesGoodBarber.length}');

      // Filtrar órdenes localmente por fecha si el filtro de la API no funcionó
      List ordenesFiltradas = ordenesGoodBarber;
      if (since != null) {
        ordenesFiltradas = [];
        int ordenesExcluidasPorFecha = 0;
        for (final orden in ordenesGoodBarber) {
          try {
            final createdAtStr = orden['created_at'];
            if (createdAtStr != null) {
              final createdAt = DateTime.parse(createdAtStr);
              if (createdAt.isAfter(fechaDesde) || createdAt.isAtSameMomentAs(fechaDesde)) {
                ordenesFiltradas.add(orden);
                print('   ✅ Orden ID=${orden['id']} incluida (created_at: $createdAtStr >= $fechaDesde)');
              } else {
                ordenesExcluidasPorFecha++;
                print('   ⏭️ Orden ID=${orden['id']} EXCLUIDA por fecha (created_at: $createdAtStr < $fechaDesde)');
              }
            } else {
              // Si no tiene fecha, incluirla por seguridad (puede ser nueva)
              print('⚠️ Orden sin created_at, incluyéndola por seguridad: ID=${orden['id']}');
              ordenesFiltradas.add(orden);
            }
          } catch (e) {
            // Si hay error parseando fecha, incluirla por seguridad
            print('⚠️ Error parseando fecha de orden ID=${orden['id']}, incluyéndola por seguridad: $e');
            ordenesFiltradas.add(orden);
          }
        }
        print('📦 Órdenes filtradas por fecha (desde ${fechaDesde.toIso8601String()}): ${ordenesFiltradas.length}');
        if (ordenesExcluidasPorFecha > 0) {
          print('   ⚠️ $ordenesExcluidasPorFecha órdenes fueron excluidas por ser anteriores a la fecha de sincronización');
        }
      } else {
        print('ℹ️ No se aplicó filtro de fecha (since es null), procesando todas las órdenes obtenidas');
      }

      if (ordenesFiltradas.isEmpty) {
        print('ℹ️ No hay órdenes nuevas para sincronizar (después de filtrar)');
        return {
          'exito': true,
          'ordenes_sincronizadas': 0,
          'ordenes_creadas': 0,
          'ordenes_actualizadas': 0,
        };
      }

      int ordenesCreadas = 0;
      int ordenesActualizadas = 0;
      int ordenesOmitidas = 0;

      // Procesar cada orden
      print('');
      print('🔄 ===== PROCESANDO ${ordenesFiltradas.length} ÓRDENES FILTRADAS =====');
      for (int i = 0; i < ordenesFiltradas.length; i++) {
        final ordenGoodBarber = ordenesFiltradas[i];
        try {
          print('');
          print('📦 [${i + 1}/${ordenesFiltradas.length}] Procesando orden...');
          print('   - ID: ${ordenGoodBarber['id']}');
          print('   - Order Num: ${ordenGoodBarber['order_num']}');
          print('   - Estado: ${ordenGoodBarber['status']}');
          print('   - Created At: ${ordenGoodBarber['created_at']}');
          
          final goodbarberOrderIdRaw = ordenGoodBarber['id'];
          if (goodbarberOrderIdRaw == null) {
            print('⚠️ Orden sin ID, omitiendo...');
            ordenesOmitidas++;
            continue;
          }

          // Convertir ID a int si es necesario
          final goodbarberOrderId = goodbarberOrderIdRaw is int 
              ? goodbarberOrderIdRaw 
              : int.tryParse(goodbarberOrderIdRaw.toString());
          
          if (goodbarberOrderId == null) {
            print('⚠️ Orden con ID inválido: $goodbarberOrderIdRaw, omitiendo...');
            ordenesOmitidas++;
            continue;
          }

          print('🔍 Verificando orden GoodBarber ID: $goodbarberOrderId (App ID: $appId, Tenant: $tenantId)');
          print('   📋 Estado en GoodBarber: ${ordenGoodBarber['status']}');
          print('   📅 Fecha creación: ${ordenGoodBarber['created_at']}');
          print('   📦 Order Num: ${ordenGoodBarber['order_num']}');

          // Verificar si la orden ya existe en VolonexPro+ (incluyendo eliminadas)
          // IMPORTANTE: Verificar por goodbarber_order_id Y goodbarber_app_id Y tenant_id
          // NO incluir filtro de estado para verificar también órdenes eliminadas
          final ordenExistente = await supabase
              .from('ordenes')
              .select('id, estado, goodbarber_order_id, goodbarber_app_id, tenant_id')
              .eq('goodbarber_order_id', goodbarberOrderId)
              .eq('goodbarber_app_id', appId)
              .eq('tenant_id', tenantId)
              .maybeSingle();
          
          print('   🔍 Resultado búsqueda en BD: ${ordenExistente != null ? "EXISTE (ID: ${ordenExistente['id']}, Estado: ${ordenExistente['estado']})" : "NO EXISTE - SE CREARÁ NUEVA"}');
          
          // IMPORTANTE: Si la orden está CANCELADA o ENTREGADA en VolonexPro+, verificar si GoodBarber la reactivó
          // Si GoodBarber cambió el estado a PENDING (POR ENVIAR), debemos reactivar la orden
          if (ordenExistente != null) {
            final estadoActualEnLogiFlow = ordenExistente['estado'] as String?;
            final estadoGoodBarber = ordenGoodBarber['status'] ?? 'pending';
            final estadoLogiFlowDesdeGoodBarber = GoodBarberService.mapearEstadoGoodBarberALogiFlow(estadoGoodBarber);
            
            print('   🔄 Orden EXISTE en VolonexPro+:');
            print('      - Estado actual en VolonexPro+: $estadoActualEnLogiFlow');
            print('      - Estado en GoodBarber: $estadoGoodBarber → $estadoLogiFlowDesdeGoodBarber');
            
            // REGLA DE REACTIVACIÓN: Si está CANCELADA o ENTREGADA en VolonexPro+, pero GoodBarber la reactivó a PENDING (POR ENVIAR)
            // Esto significa que GoodBarber reactivó la orden manualmente, debemos reactivarla en VolonexPro+ también
            if ((estadoActualEnLogiFlow == 'CANCELADA' || estadoActualEnLogiFlow == 'ENTREGADO') 
                && estadoLogiFlowDesdeGoodBarber == 'POR ENVIAR') {
              print('🔄 🔄 🔄 REACTIVACIÓN DE ORDEN DETECTADA');
              print('   Estado anterior en VolonexPro+: $estadoActualEnLogiFlow');
              print('   Estado en GoodBarber: $estadoGoodBarber → POR ENVIAR');
              print('   GoodBarber reactivó la orden manualmente, reactivando en VolonexPro+...');
              
              // Forzar actualización del estado a POR ENVIAR (bypass de las reglas normales)
              await supabase
                  .from('ordenes')
                  .update({'estado': 'POR ENVIAR'})
                  .eq('id', ordenExistente['id']);
              
              print('✅ ✅ ✅ Orden reactivada exitosamente: estado actualizado a POR ENVIAR');
              ordenesActualizadas++;
              continue; // Continuar con la siguiente orden
            }
            
            // Si está CANCELADA en VolonexPro+ y GoodBarber también la tiene como CANCELLED, sincronizar
            if (estadoActualEnLogiFlow == 'CANCELADA' && estadoLogiFlowDesdeGoodBarber == 'CANCELADA') {
              print('✅ Orden cancelada en ambos sistemas, sincronizando estado');
              // El estado ya está correcto, solo continuar
              ordenesOmitidas++;
              continue;
            }
            
            // Si está CANCELADA en VolonexPro+ pero GoodBarber NO la canceló y NO la reactivó
            // Esto puede indicar que GoodBarber rechazó la cancelación pero la orden sigue activa
            // En este caso, NO reactivamos automáticamente (solo si GoodBarber explícitamente la reactiva a PENDING)
            if (estadoActualEnLogiFlow == 'CANCELADA' && estadoLogiFlowDesdeGoodBarber != 'CANCELADA' && estadoLogiFlowDesdeGoodBarber != 'POR ENVIAR') {
              print('⚠️ Orden CANCELADA en VolonexPro+ pero GoodBarber la tiene en "$estadoGoodBarber" (no PENDING)');
              print('   La orden permanecerá CANCELADA en VolonexPro+ hasta que GoodBarber la reactive explícitamente a PENDING');
              ordenesOmitidas++;
              continue;
            }
          } else {
            // La orden NO existe en VolonexPro+ - DEBE crearse sin importar el estado en GoodBarber
            final estadoGoodBarber = ordenGoodBarber['status'] ?? 'pending';
            print('   ➕ Orden NO EXISTE en VolonexPro+ - SE CREARÁ (estado en GoodBarber: $estadoGoodBarber)');
          }

          if (ordenExistente != null) {
            print('✅ Orden ya existe en BD: ID=${ordenExistente['id']}, Estado=${ordenExistente['estado']}');
          } else {
            print('➕ Orden NO existe en BD, se creará nueva');
            print('   GoodBarber Order ID: $goodbarberOrderId');
            print('   Estado en GoodBarber: ${ordenGoodBarber['status']}');
          }

          if (ordenExistente != null) {
            // La orden ya existe, actualizar estado y otros campos si es necesario
            print('🔄 Orden ya existe (ID: $goodbarberOrderId), verificando estado y campos...');
            
            final estadoGoodBarber = ordenGoodBarber['status'] ?? 'pending';
            final estadoLogiFlowDesdeGoodBarber = GoodBarberService.mapearEstadoGoodBarberALogiFlow(estadoGoodBarber);
            final estadoActualEnLogiFlow = ordenExistente['estado'];

            print('   Estado actual en VolonexPro+: $estadoActualEnLogiFlow');
            print('   Estado desde GoodBarber: $estadoGoodBarber → $estadoLogiFlowDesdeGoodBarber');

            // Verificar si debemos actualizar el estado
            // REGLAS ESPECIALES:
            // 1. GoodBarber NO puede marcar como "ENTREGADO" (solo VolonexPro+ puede por políticas obligatorias)
            // 2. GoodBarber SÍ puede cancelar (CANCELADA)
            // 3. NO sobrescribir si el estado actual en VolonexPro+ es más avanzado que el de GoodBarber
            
            final puedeActualizarDesdeGoodBarber = _puedeActualizarEstadoDesdeGoodBarber(
              estadoActualEnLogiFlow,
              estadoLogiFlowDesdeGoodBarber,
            );

            // 🔥 NUEVO: Obtener datos completos de la orden para actualizar campos de pickup
            print('📦 Obteniendo orden completa desde GoodBarber para actualizar campos...');
            final ordenDataRaw = await GoodBarberService.mapearOrdenGoodBarberALogiFlow(
              ordenGoodBarber,
              emisorNombre,
              tenantId,
              appId,
              apiKey,
            );
            
            // Preparar campos a actualizar
            final camposAActualizar = <String, dynamic>{};
            bool necesitaActualizacion = false;
            
            // Actualizar estado si es necesario
            if (puedeActualizarDesdeGoodBarber && estadoActualEnLogiFlow != estadoLogiFlowDesdeGoodBarber) {
              camposAActualizar['estado'] = estadoLogiFlowDesdeGoodBarber;
              necesitaActualizacion = true;
              print('✅ Estado a actualizar: $estadoActualEnLogiFlow → $estadoLogiFlowDesdeGoodBarber');
            } else if (!puedeActualizarDesdeGoodBarber) {
              print('⚠️ NO se actualiza estado desde GoodBarber: $estadoLogiFlowDesdeGoodBarber (política: solo VolonexPro+ puede marcar ENTREGADO)');
            } else {
              print('ℹ️ Estado ya está actualizado: $estadoLogiFlowDesdeGoodBarber');
            }
            
            // Actualizar campos de pickup si es necesario
            final recogerEnSucursalActual = ordenExistente['recoger_en_sucursal'] as bool? ?? false;
            final recogerEnSucursalNuevo = ordenDataRaw['recoger_en_sucursal'] as bool? ?? false;
            final direccionDestinoActual = ordenExistente['direccion_destino'] as String? ?? '';
            final direccionDestinoNuevo = ordenDataRaw['direccion_destino'] as String? ?? '';
            
            if (recogerEnSucursalNuevo != recogerEnSucursalActual) {
              camposAActualizar['recoger_en_sucursal'] = recogerEnSucursalNuevo;
              necesitaActualizacion = true;
              print('✅ recoger_en_sucursal a actualizar: $recogerEnSucursalActual → $recogerEnSucursalNuevo');
            }
            
            // Si es pickup y la dirección es diferente (o está vacía), actualizarla
            if (recogerEnSucursalNuevo && 
                direccionDestinoNuevo.isNotEmpty && 
                direccionDestinoNuevo != direccionDestinoActual) {
              camposAActualizar['direccion_destino'] = direccionDestinoNuevo;
              necesitaActualizacion = true;
              print('✅ direccion_destino a actualizar (pickup): "$direccionDestinoActual" → "$direccionDestinoNuevo"');
            }
            
            // Actualizar otros campos relevantes si es necesario
            if (ordenDataRaw['numero_orden'] != null && ordenDataRaw['numero_orden'] != ordenExistente['numero_orden']) {
              camposAActualizar['numero_orden'] = ordenDataRaw['numero_orden'];
              necesitaActualizacion = true;
              print('✅ numero_orden a actualizar: ${ordenExistente['numero_orden']} → ${ordenDataRaw['numero_orden']}');
            }
            
            if (necesitaActualizacion) {
              await supabase
                  .from('ordenes')
                  .update(camposAActualizar)
                  .eq('id', ordenExistente['id']);
              
              print('✅ ✅ ✅ ORDEN ACTUALIZADA EXITOSAMENTE ✅ ✅ ✅');
              print('   Campos actualizados: ${camposAActualizar.keys.join(", ")}');
              ordenesActualizadas++;
            } else {
              print('ℹ️ No hay campos que actualizar para esta orden');
            }
          } else {
            // La orden no existe, crearla
            print('');
            print('➕ ===== CREANDO NUEVA ORDEN =====');
            print('   GoodBarber Order ID: $goodbarberOrderId');
            print('   GoodBarber App ID: $appId');
            print('   Tenant ID: $tenantId');
            print('   Estado en GoodBarber: ${ordenGoodBarber['status']}');
            print('   Fecha creación: ${ordenGoodBarber['created_at']}');
            print('   Order Num: ${ordenGoodBarber['order_num']}');
            print('');

            // Mapear orden de GoodBarber a VolonexPro+
            final ordenDataRaw = await GoodBarberService.mapearOrdenGoodBarberALogiFlow(
              ordenGoodBarber,
              emisorNombre,
              tenantId,
              appId, // ✅ Pasar appId explícitamente
              apiKey, // ✅ Pasar apiKey para obtener información de shipping
            );
            
            print('✅ Orden mapeada exitosamente, datos preparados para insertar');

            // 🔍 Buscar o crear emisor automáticamente (la empresa)
            print('🔍 Buscando/creando emisor para la orden...');
            final emisorId = await buscarOCrearEmisor(
              supabase,
              tenantId,
              emisorNombre, // Nombre de la empresa (J.Alvarez Express Services LLC)
              null, // No tenemos email del emisor desde GoodBarber
            );

            // 🔍 Buscar o crear destinatario automáticamente (el cliente)
            final destinatarioNombre = ordenDataRaw['destinatario_nombre'] as String? ?? '';
            final destinatarioTelefono = ordenDataRaw['telefono_destinatario'] as String?;
            final destinatarioDireccion = ordenDataRaw['direccion_destino'] as String? ?? '';
            final destinatarioProvincia = ordenDataRaw['provincia_destino'] as String?;
            final destinatarioMunicipio = ordenDataRaw['municipio_destino'] as String?;
            final destinatarioEmail = ordenGoodBarber['email'] as String?;

            print('🔍 Buscando/creando destinatario para la orden...');
            final destinatarioId = await buscarOCrearDestinatario(
              supabase,
              tenantId,
              destinatarioNombre,
              destinatarioTelefono,
              destinatarioDireccion,
              destinatarioProvincia,
              destinatarioMunicipio,
              destinatarioEmail,
            );

            // Agregar emisor_id y destinatario_id a los datos de la orden si se encontraron/crearon
            final ordenData = Map<String, dynamic>.from(ordenDataRaw);
            if (emisorId != null) {
              ordenData['emisor_id'] = emisorId;
              print('✅ Emisor vinculado a la orden: ID=$emisorId');
            } else {
              print('⚠️ No se pudo crear/vincular emisor, la orden se creará sin emisor_id');
            }
            
            if (destinatarioId != null) {
              ordenData['destinatario_id'] = destinatarioId;
              print('✅ Destinatario vinculado a la orden: ID=$destinatarioId');
            } else {
              print('⚠️ No se pudo crear/vincular destinatario, la orden se creará sin destinatario_id');
            }

            // Verificar una vez más antes de insertar (doble verificación para evitar duplicados)
            final verificacionFinal = await supabase
                .from('ordenes')
                .select('id')
                .eq('goodbarber_order_id', goodbarberOrderId)
                .eq('goodbarber_app_id', appId)
                .eq('tenant_id', tenantId)
                .maybeSingle();

            if (verificacionFinal != null) {
              print('⚠️ Orden ya existe (verificación final), omitiendo creación duplicada');
              ordenesOmitidas++;
              continue;
            }

            // Insertar orden en VolonexPro+
            // NOTA: Esta inserción disparará el callback de Realtime INSERT, pero ya no causará bucle
            // porque el callback ahora usa _recargarOrdenesSinSincronizar() en lugar de _cargarOrdenes()
            try {
              print('📝 Intentando insertar orden en base de datos...');
              print('   Datos a insertar:');
              print('   - emisor_nombre: ${ordenData['emisor_nombre']}');
              print('   - destinatario_nombre: ${ordenData['destinatario_nombre']}');
              print('   - estado: ${ordenData['estado']}');
              print('   - goodbarber_order_id: ${ordenData['goodbarber_order_id']}');
              print('   - goodbarber_app_id: ${ordenData['goodbarber_app_id']}');
              print('   - recoger_en_sucursal: ${ordenData['recoger_en_sucursal']}');
              
              final resultadoInsert = await supabase.from('ordenes').insert(ordenData).select('id, numero_orden').maybeSingle();
              
              if (resultadoInsert == null) {
                print('❌ Error: La orden se insertó pero no se pudo obtener el resultado');
                ordenesOmitidas++;
                continue;
              }
              print('✅ ✅ ✅ ORDEN CREADA EXITOSAMENTE ✅ ✅ ✅');
              print('   VolonexPro+ Order ID: ${resultadoInsert['id']}');
              print('   Número de Orden: ${resultadoInsert['numero_orden']}');
              print('   GoodBarber Order ID: ${ordenData['goodbarber_order_id']}');
              ordenesCreadas++;
            } catch (insertError) {
              print('❌ ❌ ❌ ERROR AL INSERTAR ORDEN ❌ ❌ ❌');
              print('   Error completo: $insertError');
              print('   Tipo de error: ${insertError.runtimeType}');
              
              // Si hay un error de duplicado (unique constraint), la orden ya existe
              if (insertError.toString().contains('duplicate') || 
                  insertError.toString().contains('unique') ||
                  insertError.toString().contains('23505')) {
                print('⚠️ Orden duplicada detectada (error de BD), omitiendo');
                ordenesOmitidas++;
              } else {
                print('❌ Error insertando orden (no es duplicado): $insertError');
                ordenesOmitidas++;
              }
            }
          }
        } catch (e, stackTrace) {
          print('❌ Error procesando orden: $e');
          print('   Stack trace: $stackTrace');
          ordenesOmitidas++;
        }
      }

      print('');
      print('✅ ===== SINCRONIZACIÓN COMPLETADA =====');
      print('   📦 Total órdenes procesadas: ${ordenesFiltradas.length}');
      print('   ➕ Órdenes creadas: $ordenesCreadas (incluye órdenes eliminadas que se restauran)');
      print('   🔄 Órdenes actualizadas: $ordenesActualizadas');
      print('   ⏭️ Órdenes omitidas: $ordenesOmitidas');
      if (ordenesCreadas == 0 && ordenesActualizadas == 0 && ordenesFiltradas.isNotEmpty) {
        print('   ⚠️ ADVERTENCIA: Se procesaron ${ordenesFiltradas.length} órdenes pero ninguna fue creada ni actualizada');
        print('   ⚠️ Esto puede indicar que todas las órdenes ya existen o están canceladas');
      }

      return {
        'exito': true,
        'ordenes_sincronizadas': ordenesGoodBarber.length,
        'ordenes_creadas': ordenesCreadas,
        'ordenes_actualizadas': ordenesActualizadas,
        'ordenes_omitidas': ordenesOmitidas,
      };
    } catch (e, stackTrace) {
      print('❌ Error en sincronización: $e');
      print('   Stack trace: $stackTrace');
      return {
        'exito': false,
        'error': e.toString(),
        'ordenes_sincronizadas': 0,
        'ordenes_creadas': 0,
        'ordenes_actualizadas': 0,
      };
    }
  }

  /// Sincroniza el estado de una orden de VolonexPro+ a GoodBarber
  /// Se llama automáticamente cuando cambia el estado de una orden
  static Future<Map<String, dynamic>> sincronizarEstadoAGoodBarber(
    SupabaseClient supabase,
    String ordenId,
    String nuevoEstado,
  ) async {
    try {
      print('🔄 ===== SINCRONIZANDO ESTADO A GOODBARBER =====');
      print('   Orden ID: $ordenId');
      print('   Nuevo estado: $nuevoEstado');

      // Obtener información de la orden
      final orden = await supabase
          .from('ordenes')
          .select('goodbarber_order_id, goodbarber_app_id, tenant_id')
          .eq('id', ordenId)
          .maybeSingle();

      if (orden == null) {
        print('⚠️ Orden no encontrada');
        return {
          'exito': false,
          'error': 'Orden no encontrada',
        };
      }

      final goodbarberOrderId = orden['goodbarber_order_id'];
      final goodbarberAppId = orden['goodbarber_app_id'];

      if (goodbarberOrderId == null || goodbarberAppId == null) {
        print('ℹ️ Orden no está vinculada con GoodBarber, omitiendo sincronización');
        return {
          'exito': true,
          'mensaje': 'Orden no vinculada con GoodBarber',
        };
      }

      // Obtener configuración de GoodBarber del tenant
      final configuracion = await supabase
          .from('goodbarber_integrations')
          .select('api_key, app_id')
          .eq('tenant_id', orden['tenant_id'])
          .eq('app_id', goodbarberAppId)
          .eq('activo', true)
          .maybeSingle();

      if (configuracion == null) {
        print('⚠️ Configuración de GoodBarber no encontrada');
        return {
          'exito': false,
          'error': 'Configuración de GoodBarber no encontrada',
        };
      }

      // Mapear estado de VolonexPro+ a GoodBarber
      final estadoGoodBarber = GoodBarberService.mapearEstadoLogiFlowAGoodBarber(nuevoEstado);

      if (estadoGoodBarber == null) {
        print('ℹ️ Estado no se sincroniza con GoodBarber: $nuevoEstado');
        return {
          'exito': true,
          'mensaje': 'Estado no se sincroniza con GoodBarber',
        };
      }

      // Verificar estado actual en GoodBarber antes de actualizar
      // Esto evita errores 400 cuando se intenta actualizar al mismo estado
      try {
        final ordenesGoodBarber = await GoodBarberService.obtenerOrdenesGoodBarber(
          configuracion['api_key'],
          goodbarberAppId,
          limit: 100,
        );

        if (ordenesGoodBarber['exito'] == true) {
          final ordenes = ordenesGoodBarber['ordenes'] as List<dynamic>? ?? [];
          dynamic ordenEnGoodBarber;
          try {
            ordenEnGoodBarber = ordenes.firstWhere(
              (o) => o['id'] == goodbarberOrderId,
            );
          } catch (e) {
            // Orden no encontrada en la lista, continuar con actualización
            ordenEnGoodBarber = null;
          }

          if (ordenEnGoodBarber != null) {
            final estadoActualEnGoodBarber = (ordenEnGoodBarber['status'] ?? '').toString().toUpperCase();
            final estadoNuevoUpper = estadoGoodBarber.toUpperCase();

            if (estadoActualEnGoodBarber == estadoNuevoUpper) {
              print('ℹ️ Estado ya está actualizado en GoodBarber: $estadoNuevoUpper');
              return {
                'exito': true,
                'mensaje': 'Estado ya está actualizado en GoodBarber',
              };
            }
          }
        }
      } catch (e) {
        print('⚠️ Error verificando estado en GoodBarber, continuando con actualización: $e');
      }

      // Actualizar estado en GoodBarber
      final resultado = await GoodBarberService.actualizarEstadoOrdenGoodBarber(
        configuracion['api_key'],
        goodbarberAppId,
        goodbarberOrderId,
        estadoGoodBarber,
      );

      if (resultado['exito']) {
        print('✅ Estado sincronizado exitosamente a GoodBarber');
      } else {
        print('❌ Error sincronizando estado: ${resultado['error']}');
      }

      return resultado;
    } catch (e, stackTrace) {
      print('❌ Error sincronizando estado a GoodBarber: $e');
      print('   Stack trace: $stackTrace');
      return {
        'exito': false,
        'error': e.toString(),
      };
    }
  }

  /// Sincroniza estados de órdenes de VolonexPro+ a GoodBarber periódicamente
  /// Esto asegura que si GoodBarber cambia un estado en su tablero, se actualice con el estado real de VolonexPro+
  /// Se ejecuta periódicamente para mantener sincronización bidireccional
  static Future<Map<String, dynamic>> sincronizarEstadosALogiflowAGoodBarber(
    SupabaseClient supabase,
    String tenantId,
  ) async {
    try {
      print('🔄 ===== SINCRONIZANDO ESTADOS DE LOGIFLOW A GOODBARBER =====');
      print('   Tenant ID: $tenantId');

      // Obtener todas las órdenes vinculadas con GoodBarber que no estén en POR ENVIAR o CANCELADA
      final ordenesGoodBarber = await supabase
          .from('ordenes')
          .select('id, estado, goodbarber_order_id, goodbarber_app_id')
          .eq('tenant_id', tenantId)
          .not('goodbarber_order_id', 'is', null)
          .not('goodbarber_app_id', 'is', null)
          .inFilter('estado', ['EN TRANSITO', 'EN REPARTO', 'ENTREGADO'])
          .limit(100); // Limitar a 100 órdenes por sincronización para no sobrecargar

      if (ordenesGoodBarber.isEmpty) {
        print('ℹ️ No hay órdenes para sincronizar');
        return {
          'exito': true,
          'ordenes_sincronizadas': 0,
        };
      }

      print('📋 Encontradas ${ordenesGoodBarber.length} órdenes para sincronizar');

      // Obtener configuración de GoodBarber
      final configuracion = await supabase
          .from('goodbarber_integrations')
          .select('api_key, app_id')
          .eq('tenant_id', tenantId)
          .eq('activo', true)
          .maybeSingle();

      if (configuracion == null) {
        print('⚠️ Configuración de GoodBarber no encontrada');
        return {
          'exito': false,
          'error': 'Configuración de GoodBarber no encontrada',
        };
      }

      int ordenesSincronizadas = 0;
      int ordenesOmitidas = 0;

      // Sincronizar cada orden
      for (final orden in ordenesGoodBarber) {
        try {
          final ordenId = orden['id'] as String;
          final estadoActual = orden['estado'] as String;
          final goodbarberAppId = orden['goodbarber_app_id'] as int;

          // Solo sincronizar si el app_id coincide con la configuración
          if (goodbarberAppId != configuracion['app_id']) {
            continue;
          }

          // Sincronizar estado
          final resultado = await sincronizarEstadoAGoodBarber(
            supabase,
            ordenId,
            estadoActual,
          );

          if (resultado['exito'] == true) {
            ordenesSincronizadas++;
            print('✅ Orden ${orden['id']} sincronizada: $estadoActual');
          } else {
            ordenesOmitidas++;
            print('⚠️ Orden ${orden['id']} omitida: ${resultado['error'] ?? resultado['mensaje']}');
          }
        } catch (e) {
          print('❌ Error sincronizando orden ${orden['id']}: $e');
          ordenesOmitidas++;
        }
      }

      print('✅ ===== SINCRONIZACIÓN COMPLETADA =====');
      print('   Órdenes sincronizadas: $ordenesSincronizadas');
      print('   Órdenes omitidas: $ordenesOmitidas');

      return {
        'exito': true,
        'ordenes_sincronizadas': ordenesSincronizadas,
        'ordenes_omitidas': ordenesOmitidas,
      };
    } catch (e, stackTrace) {
      print('❌ Error sincronizando estados a GoodBarber: $e');
      print('   Stack trace: $stackTrace');
      return {
        'exito': false,
        'error': e.toString(),
        'ordenes_sincronizadas': 0,
      };
    }
  }

  /// Determina si GoodBarber puede actualizar el estado de una orden
  /// REGLAS DE CONTROL:
  /// 1. GoodBarber puede controlar POR ENVIAR solo cuando crea la orden o cuando está en POR ENVIAR
  /// 2. GoodBarber NO puede controlar EN TRANSITO, EN REPARTO, ENTREGADO (solo VolonexPro+ puede)
  /// 3. GoodBarber puede cancelar (CANCELADA) solo si la orden está en POR ENVIAR
  /// 4. Una vez que VolonexPro+ marca EN TRANSITO o más avanzado, GoodBarber pierde control (solo lectura)
  static bool _puedeActualizarEstadoDesdeGoodBarber(String estadoActual, String estadoDesdeGoodBarber) {
    final estadoActualUpper = estadoActual.toUpperCase();
    final estadoDesdeGoodBarberUpper = estadoDesdeGoodBarber.toUpperCase();

    print('   🔍 Verificando si GoodBarber puede actualizar estado:');
    print('      Estado actual en VolonexPro+: $estadoActual');
    print('      Estado desde GoodBarber: $estadoDesdeGoodBarber');

    // REGLA 1: Si la orden ya está en EN TRANSITO o EN REPARTO,
    // GoodBarber pierde el control (solo lectura). No puede cambiar nada.
    // EXCEPCIÓN: Si está ENTREGADO y GoodBarber intenta reactivar a POR ENVIAR, se permite (reactivación)
    if (estadoActualUpper == 'EN TRANSITO' || estadoActualUpper == 'EN REPARTO') {
      print('      ❌ NO permitido: Orden ya está en "$estadoActual", GoodBarber perdió el control (solo lectura)');
      return false;
    }
    
    // EXCEPCIÓN ESPECIAL: Si está ENTREGADO y GoodBarber intenta reactivar a POR ENVIAR, permitir
    if (estadoActualUpper == 'ENTREGADO' && estadoDesdeGoodBarberUpper == 'POR ENVIAR') {
      print('      ✅ EXCEPCIÓN: Orden ENTREGADA puede ser reactivada a POR ENVIAR por GoodBarber');
      return true;
    }
    
    // Si está ENTREGADO y NO es reactivación, no permitir
    if (estadoActualUpper == 'ENTREGADO') {
      print('      ❌ NO permitido: Orden ya está en "$estadoActual", GoodBarber perdió el control (solo lectura)');
      return false;
    }

    // REGLA 2: GoodBarber NO puede marcar como ENTREGADO
    // Solo VolonexPro+ puede marcar como ENTREGADO porque tiene políticas obligatorias (foto, firma, etc.)
    if (estadoDesdeGoodBarberUpper == 'ENTREGADO') {
      print('      ❌ NO permitido: GoodBarber NO puede marcar como ENTREGADO (solo VolonexPro+ puede)');
      return false;
    }

    // REGLA 3: GoodBarber NO puede marcar como EN TRANSITO
    // Solo VolonexPro+ puede marcar como EN TRANSITO (es la empresa logística que decide cuándo enviar)
    if (estadoDesdeGoodBarberUpper == 'EN TRANSITO') {
      print('      ❌ NO permitido: GoodBarber NO puede marcar como EN TRANSITO (solo VolonexPro+ puede)');
      return false;
    }

    // REGLA 4: GoodBarber NO puede marcar como EN REPARTO (no existe en GoodBarber)
    if (estadoDesdeGoodBarberUpper == 'EN REPARTO') {
      print('      ❌ NO permitido: EN REPARTO no existe en GoodBarber');
      return false;
    }

    // REGLA 5: GoodBarber puede cancelar (CANCELADA) solo si la orden está en POR ENVIAR
    if (estadoDesdeGoodBarberUpper == 'CANCELADA') {
      if (estadoActualUpper == 'POR ENVIAR') {
        print('      ✅ Permitido: GoodBarber puede cancelar órdenes en POR ENVIAR');
        return true;
      } else {
        print('      ❌ NO permitido: GoodBarber solo puede cancelar si la orden está en POR ENVIAR (actual: $estadoActual)');
        return false;
      }
    }

    // REGLA 6: GoodBarber puede controlar POR ENVIAR solo si la orden está en POR ENVIAR
    // (permite crear órdenes nuevas o mantener en POR ENVIAR)
    if (estadoDesdeGoodBarberUpper == 'POR ENVIAR') {
      if (estadoActualUpper == 'POR ENVIAR') {
        print('      ✅ Permitido: GoodBarber puede mantener en POR ENVIAR');
        return true;
      } else {
        print('      ❌ NO permitido: GoodBarber no puede cambiar de vuelta a POR ENVIAR desde $estadoActual');
        return false;
      }
    }

    // Si llegamos aquí, el estado no está permitido
    print('      ❌ NO permitido: Estado "$estadoDesdeGoodBarberUpper" no está permitido desde GoodBarber');
    return false;
  }
}

