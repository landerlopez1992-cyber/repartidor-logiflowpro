import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../models/orden.dart';
import '../services/goodbarber_sync_service.dart';
import '../services/email_service.dart';
import '../services/sync_service.dart';
import '../services/orden_cache_service.dart';
import '../services/configuracion_service.dart';
import 'detalle_orden_screen.dart';

class QRScannerFullscreen extends StatefulWidget {
  final String? repartidorNombre;
  final bool esRepartidorMaster;

  const QRScannerFullscreen({
    super.key,
    this.repartidorNombre,
    this.esRepartidorMaster = false,
  });

  @override
  State<QRScannerFullscreen> createState() => _QRScannerFullscreenState();
}

class _QRScannerFullscreenState extends State<QRScannerFullscreen> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      torchEnabled: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final barcodes = capture.barcodes;
    for (final b in barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        try {
          final syncService = SyncService();
          Orden? orden;
          
          // ✅ INTENTO 1: Cargar desde Supabase si hay conexión
          if (syncService.isOnline) {
            try {
              print('📡 Buscando orden en Supabase (online)...');
              final data = await supabase.from('ordenes').select('*').eq('id', value).single();
              if (!mounted) return;
              orden = Orden.fromJson(data);
              print('✅ Orden encontrada en Supabase: ${orden.numeroOrden}');
            } catch (e) {
              print('⚠️ Error al buscar en Supabase: $e');
              // Continuar para buscar en caché
            }
          }
          
          // ✅ INTENTO 2: Buscar en caché local si no se encontró online o no hay conexión
          if (orden == null) {
            print('💾 Buscando orden en caché local (offline o error en Supabase)...');
            final ordenesCache = await OrdenCacheService.getCachedOrders();
            try {
              orden = ordenesCache.firstWhere((o) => o.id == value);
              print('✅ Orden encontrada en caché: ${orden.numeroOrden}');
            } catch (e) {
              print('❌ Orden no encontrada en caché');
              // No se encontró ni online ni en caché
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      syncService.isOnline 
                        ? 'Orden no encontrada' 
                        : 'Sin conexión y orden no disponible offline.\nConéctate a internet para escanear esta orden.'
                    ),
                    backgroundColor: const Color(0xFFDC2626),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              _handled = false;
              return;
            }
          }
          
          if (orden == null) {
            _handled = false;
            return;
          }
          
          // Validar si la orden está asignada al repartidor
          final ordenAsignadaA = orden.repartidor;
          final esMiOrden = ordenAsignadaA != null && 
                           widget.repartidorNombre != null &&
                           ordenAsignadaA.trim().toUpperCase() == widget.repartidorNombre!.trim().toUpperCase();
          
          if (!esMiOrden && ordenAsignadaA != null && ordenAsignadaA.isNotEmpty) {
            // La orden no está asignada a este repartidor
            if (widget.esRepartidorMaster) {
              // Repartidor master: mostrar modal de confirmación
              final continuar = await _mostrarModalRepartidorMaster(
                orden.numeroOrden,
                ordenAsignadaA,
              );
              if (!mounted) return;
              if (continuar == true) {
                // Si está en "EN TRANSITO", mostrar modal de recibir orden
                if (orden.estado == 'EN TRANSITO') {
                  final accion = await _mostrarModalConfirmacionRecibir(orden);
                  if (!mounted) return;
                  if (accion == 'chequear') {
                    // Abrir orden normalmente
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
                    );
                  } else if (accion == 'recibir') {
                    // Recibir orden y volver a escáner
                    await _recibirOrden(orden);
                    _handled = false; // Permitir escanear otra orden
                  } else {
                    // Cancelar, permitir escanear otra orden
                    _handled = false;
                  }
                } else if (orden.estado == 'EN REPARTO' && orden.recogerEnSucursal) {
                  // Si está en "EN REPARTO" y es recogida en sucursal, mostrar modal especial
                  final accion = await _mostrarModalListoParaRecoger(orden);
                  if (!mounted) return;
                  if (accion == 'ver') {
                    // Abrir orden normalmente
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
                    );
                  } else if (accion == 'aceptar') {
                    // Marcar como "Listo para recoger"
                    await _marcarComoListoParaRecoger(orden);
                    _handled = false; // Permitir escanear otra orden
                  } else {
                    // Cancelar/Rechazar, permitir escanear otra orden
                    _handled = false;
                  }
                } else {
                  // Si no está en "EN TRANSITO" ni es "EN REPARTO" con recogida en sucursal, abrir orden normalmente
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
                  );
                }
              } else {
                // Cancelar, permitir escanear otra orden
                _handled = false;
              }
            } else {
              // Repartidor normal: mostrar modal de error
              await _mostrarModalOrdenNoAsignada(orden.numeroOrden, ordenAsignadaA);
              if (!mounted) return;
              // Permitir escanear otra orden
              _handled = false;
            }
          } else {
            // La orden está asignada a este repartidor o no tiene repartidor asignado
            // Si está en "EN TRANSITO", mostrar modal de recibir orden
            if (orden.estado == 'EN TRANSITO') {
              final accion = await _mostrarModalConfirmacionRecibir(orden);
              if (!mounted) return;
              if (accion == 'chequear') {
                // Abrir orden normalmente
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
                );
              } else if (accion == 'recibir') {
                // Recibir orden y volver a escáner
                await _recibirOrden(orden);
                _handled = false; // Permitir escanear otra orden
              } else {
                // Cancelar, permitir escanear otra orden
                _handled = false;
              }
            } else if (orden.estado == 'EN REPARTO' && orden.recogerEnSucursal) {
              // Si está en "EN REPARTO" y es recogida en sucursal, mostrar modal especial
              final accion = await _mostrarModalListoParaRecoger(orden);
              if (!mounted) return;
              if (accion == 'ver') {
                // Abrir orden normalmente
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
                );
              } else if (accion == 'aceptar') {
                // Marcar como "Listo para recoger"
                await _marcarComoListoParaRecoger(orden);
                _handled = false; // Permitir escanear otra orden
              } else {
                // Cancelar/Rechazar, permitir escanear otra orden
                _handled = false;
              }
            } else {
              // Si no está en "EN TRANSITO" ni es "EN REPARTO" con recogida en sucursal, abrir orden normalmente
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden!)),
              );
            }
          }
        } on SocketException {
          // Error de conexión de red
          _handled = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Sin conexión a internet. Verifica tu conexión e intenta nuevamente.'),
                  ),
                ],
              ),
              backgroundColor: Color(0xFFDC2626),
              duration: Duration(seconds: 4),
            ),
          );
        } catch (e) {
          // Otros errores (orden no encontrada, etc.)
          _handled = false;
          if (!mounted) return;
          
          // Determinar mensaje de error
          String mensaje = 'No se encontró la orden';
          if (e.toString().contains('multiple') || e.toString().contains('0 rows')) {
            mensaje = 'QR inválido o orden no existe';
          } else if (e.toString().contains('timeout')) {
            mensaje = 'Tiempo de espera agotado. Intenta nuevamente.';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(mensaje),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFDC2626),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        break;
      }
    }
  }

  Future<void> _mostrarModalOrdenNoAsignada(String numeroOrden, String repartidorAsignado) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Orden no asignada',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2C2C2C),
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'La orden '),
                  TextSpan(
                    text: '$numeroOrden',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const TextSpan(text: ' no le pertenece a usted.\n\n'),
                  const TextSpan(text: 'Debe contactar al repartidor '),
                  TextSpan(
                    text: repartidorAsignado,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const TextSpan(text: ' asignado a esta orden.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Orden #$numeroOrden asignada a: $repartidorAsignado',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2C2C2C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF37474F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<String?> _mostrarModalConfirmacionRecibir(Orden orden) async {
    // 🔍 Verificar si se debe validar bultos completos
    final configService = ConfiguracionService();
    final validarBultos = await configService.validarBultosCompletos();
    final cantidadBultos = orden.cantidadBultos;
    
    print('🔍 Verificando validación de bultos:');
    print('   - validar_bultos_completos: $validarBultos');
    print('   - cantidadBultos: $cantidadBultos');
    
    // Si está activo y la orden tiene más de 1 bulto, mostrar modal de validación de bultos
    if (validarBultos && cantidadBultos > 1) {
      print('📦 Validación de bultos activa - Mostrando modal de escaneo de bultos');
      final resultado = await _mostrarModalValidacionBultos(orden);
      if (!mounted) return null;
      if (resultado == true) {
        // Todos los bultos fueron escaneados, proceder con recibir orden
        return 'recibir';
      } else {
        // Cancelado o no completado
        return null;
      }
    }
    
    // Si no está activo o tiene 1 bulto, mostrar modal normal
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.local_shipping, color: Color(0xFF2196F3), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Orden Escaneada',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Has escaneado una orden en tránsito. ¿Qué deseas hacer?',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF2C2C2C),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2196F3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Orden: #${orden.numeroOrden}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emisor: ${orden.emisor}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('chequear'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF37474F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Chequear Orden'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('recibir'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Recibir Orden'),
          ),
        ],
      ),
    );
  }

  Future<String?> _mostrarModalListoParaRecoger(Orden orden) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Icon(
              Icons.store,
              color: const Color(0xFFFF9800),
              size: 28,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Orden Escaneada',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'La orden está lista para que el destinatario ${orden.receptor} pase a recogerla en la sucursal. ¿Qué deseas hacer?',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF2C2C2C),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Orden: #${orden.numeroOrden}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Destinatario: ${orden.receptor}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Botón Ver Orden
          TextButton(
            onPressed: () => Navigator.of(context).pop('ver'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF37474F),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Ver Orden',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón Denegar
          TextButton(
            onPressed: () => Navigator.of(context).pop('denegar'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Denegar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón Aceptar
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop('aceptar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Aceptar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _marcarComoListoParaRecoger(Orden orden) async {
    try {
      final syncService = SyncService();
      final updateData = <String, dynamic>{'estado': 'LISTO PARA RECOGER'};

      bool actualizadoExitosamente = false;

      // ✅ OFFLINE-FIRST: actualizar local inmediato
      try {
        orden.estado = 'LISTO PARA RECOGER';
        await OrdenCacheService.updateCachedOrder(orden);
      } catch (e) {
        print('⚠️ Error actualizando caché local LISTO PARA RECOGER (QR): $e');
      }

      // Intentar BD solo si hay conectividad (si falla DNS, se encola)
      if (syncService.isOnline) {
        try {
          await supabase.from('ordenes').update(updateData).eq('id', orden.id);
          actualizadoExitosamente = true;
        } catch (e) {
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') ||
              errorString.contains('SocketException') ||
              errorString.contains('ClientException')) {
            print('📴 Sin conexión real a Supabase (QR) - Encolando LISTO PARA RECOGER');
            actualizadoExitosamente = false;
          } else {
            rethrow;
          }
        }
      }

      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: orden.id,
            data: updateData,
          );
        } catch (e) {
          print('⚠️ Error encolando LISTO PARA RECOGER (QR): $e');
        }
      }

      // Sincronizar con GoodBarber si la orden está vinculada
      if (actualizadoExitosamente) {
        try {
          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
            supabase,
            orden.id,
            'LISTO PARA RECOGER',
          );
        } catch (e) {
          print('⚠️ Error sincronizando estado con GoodBarber: $e');
        }
      }

      // Enviar email al emisor cuando la orden está lista para recoger
      print('📧 ===== INICIANDO PROCESO DE EMAIL LISTO PARA RECOGER =====');
      if (actualizadoExitosamente) {
        try {
        // Recargar la orden para obtener datos actualizados
        final ordenData = await supabase
            .from('ordenes')
            .select('*')
            .eq('id', orden.id)
            .single();
        
        final ordenActualizada = Orden.fromJson(ordenData);
        ordenActualizada.estado = 'LISTO PARA RECOGER';
        
        // Obtener tenant_id de la orden
        final tenantId = ordenActualizada.tenantId;
        
        // Obtener email del emisor desde la tabla emisores
        String? emailEmisor;
        if (tenantId != null) {
          try {
            final emisorData = await supabase
                .from('emisores')
                .select('email')
                .eq('nombre', ordenActualizada.emisor)
                .eq('tenant_id', tenantId)
                .maybeSingle();
            
            if (emisorData != null && emisorData['email'] != null) {
              emailEmisor = emisorData['email'] as String;
              print('📧 Email del emisor obtenido: $emailEmisor');
            } else {
              print('⚠️ No se encontró email del emisor en la tabla emisores');
            }
          } catch (e) {
            print('⚠️ Error obteniendo email del emisor: $e');
          }
        }
        
        // Enviar email si tenemos el email del emisor
        if (emailEmisor != null && emailEmisor.isNotEmpty && tenantId != null) {
          EmailService.enviarEmailOrdenListaParaRecoger(ordenActualizada, emailEmisor, tenantId: tenantId).then((enviado) {
            print(enviado ? '✅ ✅ ✅ Email LISTO PARA RECOGER enviado EXITOSAMENTE ✅ ✅ ✅' : '⚠️ ⚠️ ⚠️ Email LISTO PARA RECOGER falló ⚠️ ⚠️ ⚠️');
          }).catchError((e) {
            print('❌ ❌ ❌ ERROR CRÍTICO enviando email LISTO PARA RECOGER ❌ ❌ ❌');
            print('❌ Error: $e');
          });
        } else {
          print('⚠️ No se puede enviar email: emailEmisor=${emailEmisor != null ? "disponible" : "null"}, tenantId=${tenantId != null ? "disponible" : "null"}');
        }
        } catch (e) {
          print('❌ Error en proceso de email LISTO PARA RECOGER: $e');
        }
      } else {
        print('📴 Modo offline (QR): email omitido');
      }

      // Mostrar icono de confirmación
      if (!mounted) return;
      await _mostrarIconoConfirmacion();

      // Volver a habilitar el escáner
      _handled = false;
    } on SocketException {
      // ✅ OFFLINE-FIRST: no bloquear
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text('✅ Guardado offline. Se sincronizará al volver la señal.'),
              ),
            ],
          ),
          backgroundColor: Color(0xFFFF9800),
          duration: Duration(seconds: 4),
        ),
      );
      _handled = false;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Error al marcar como listo para recoger: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 3),
        ),
      );
      _handled = false;
    }
  }

  Future<void> _recibirOrden(Orden orden) async {
    try {
      final syncService = SyncService();
      final updateData = <String, dynamic>{'estado': 'EN REPARTO'};

      bool actualizadoExitosamente = false;

      // ✅ OFFLINE-FIRST: actualizar local inmediato
      try {
        orden.estado = 'EN REPARTO';
        await OrdenCacheService.updateCachedOrder(orden);
        print('💾 Orden actualizada en caché local: EN TRANSITO → EN REPARTO');
      } catch (e) {
        print('⚠️ Error actualizando caché local EN REPARTO (QR): $e');
      }

      // Intentar BD solo si hay conectividad (si falla DNS, se encola)
      if (syncService.isOnline) {
        try {
          await supabase.from('ordenes').update(updateData).eq('id', orden.id);
          actualizadoExitosamente = true;
          print('✅ Orden marcada como EN REPARTO en Supabase (online)');
        } catch (e) {
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') ||
              errorString.contains('SocketException') ||
              errorString.contains('ClientException')) {
            print('📴 Sin conexión real a Supabase (QR) - Encolando EN REPARTO');
            actualizadoExitosamente = false;
          } else {
            rethrow;
          }
        }
      } else {
        print('📴 Sin conexión - Encolando EN REPARTO');
      }

      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: orden.id,
            data: updateData,
          );
          print('📝 Operación EN REPARTO agregada a cola de sincronización');
        } catch (e) {
          print('⚠️ Error encolando EN REPARTO (QR): $e');
        }
      }

      // Sincronizar con GoodBarber si la orden está vinculada (solo si se actualizó exitosamente)
      if (actualizadoExitosamente) {
        try {
          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
            supabase,
            orden.id,
            'EN REPARTO',
          );
        } catch (e) {
          print('⚠️ Error sincronizando estado con GoodBarber: $e');
        }
      }

      // Mostrar icono de confirmación
      if (!mounted) return;
      await _mostrarIconoConfirmacion();

      // Mostrar mensaje de éxito (offline o online)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                actualizadoExitosamente ? Icons.check_circle : Icons.wifi_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  actualizadoExitosamente
                      ? '✅ Orden recibida exitosamente'
                      : '✅ Orden recibida (offline). Se sincronizará al volver la señal.',
                ),
              ),
            ],
          ),
          backgroundColor: actualizadoExitosamente
              ? const Color(0xFF4CAF50)
              : const Color(0xFFFF9800),
          duration: const Duration(seconds: 3),
        ),
      );

      // Volver a habilitar el escáner
      _handled = false;
    } on SocketException {
      // ✅ OFFLINE-FIRST: no bloquear, ya se guardó en caché
      if (!mounted) return;
      await _mostrarIconoConfirmacion();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text('✅ Orden recibida (offline). Se sincronizará al volver la señal.'),
              ),
            ],
          ),
          backgroundColor: Color(0xFFFF9800),
          duration: Duration(seconds: 4),
        ),
      );
      _handled = false;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Error al recibir orden: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 3),
        ),
      );
      _handled = false;
    }
  }

  /// Modal para validar que todos los bultos estén escaneados
  Future<bool?> _mostrarModalValidacionBultos(Orden orden) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BultosScannerModal(
        orden: orden,
        cantidadBultos: orden.cantidadBultos,
        onCompletado: (todosEscaneados) {
          // Callback para cuando todos los bultos estén escaneados
        },
      ),
    );
  }

  Future<void> _mostrarIconoConfirmacion() async {
    if (!mounted) return;
    
    // Mostrar el diálogo
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (context) => const Center(
        child: Card(
          color: Color(0xFF4CAF50),
          shape: CircleBorder(),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 80,
            ),
          ),
        ),
      ),
    );

    // Esperar 1.5 segundos y cerrar el diálogo
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<bool?> _mostrarModalRepartidorMaster(String numeroOrden, String repartidorAsignado) async {
    // Verificar si el usuario ya seleccionó "No molestar más"
    final prefs = await SharedPreferences.getInstance();
    final noMolestarMas = prefs.getBool('qr_master_no_molestar') ?? false;
    
    if (noMolestarMas) {
      // Si ya seleccionó "No molestar más", continuar directamente
      return true;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Color(0xFFFF9800), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Repartidor Master',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF2C2C2C),
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'Esta orden '),
                  TextSpan(
                    text: '$numeroOrden',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF9800),
                    ),
                  ),
                  const TextSpan(text: ' no es su orden.\n\n'),
                  const TextSpan(text: 'Pertenece al repartidor '),
                  TextSpan(
                    text: repartidorAsignado,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const TextSpan(text: ', pero como repartidor Master puede acceder a esta orden.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFFF9800), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Orden #$numeroOrden asignada a: $repartidorAsignado',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF2C2C2C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Guardar preferencia "No molestar más"
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('qr_master_no_molestar', true);
              if (!mounted) return;
              Navigator.of(context).pop(true); // Continuar
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: const Text('No molestar más'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true), // Continuar
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Acceder a la orden'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double frameSize = size.width * 0.72;
    final double left = (size.width - frameSize) / 2;
    final double top = (size.height - frameSize) / 2;
    final double labelTop = top > 56 ? top - 60 : 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Cámara de fondo
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            fit: BoxFit.cover,
          ),

          // Overlay oscuro con recorte transparente en el centro
          IgnorePointer(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(
                scanAreaRect: Rect.fromLTWH(left, top, frameSize, frameSize),
                borderRadius: 16,
              ),
              child: Container(),
            ),
          ),

          // Marco central verde
          IgnorePointer(
            child: Center(
              child: Container(
                width: frameSize,
                height: frameSize,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF4CAF50), width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          // Mira telescópica (cruz central)
          IgnorePointer(
            child: Center(
              child: SizedBox(
                width: frameSize,
                height: frameSize,
                child: Stack(
                  children: [
                    // Línea horizontal
                    Center(
                      child: Container(
                        width: 60,
                        height: 1,
                        color: const Color(0xFF4CAF50).withOpacity(0.8),
                      ),
                    ),
                    // Línea vertical
                    Center(
                      child: Container(
                        width: 1,
                        height: 60,
                        color: const Color(0xFF4CAF50).withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Texto sobre el marco
          Positioned(
            left: 0,
            right: 0,
            top: labelTop,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Escanea el paquete',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),



          // Botones inferiores (Cerrar y Flash)
          Positioned(
            left: 24,
            right: 24,
            top: top + frameSize + 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Botón Flash
                ElevatedButton.icon(
                  onPressed: () => _controller.toggleTorch(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF37474F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('Flash'),
                ),
                // Botón Cerrar
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// CustomPainter para crear overlay oscuro con área transparente en el centro
class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanAreaRect;
  final double borderRadius;

  _ScannerOverlayPainter({
    required this.scanAreaRect,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        scanAreaRect,
        Radius.circular(borderRadius),
      ));

    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withOpacity(0.90),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Modal para escanear bultos uno por uno
class _BultosScannerModal extends StatefulWidget {
  final Orden orden;
  final int cantidadBultos;
  final Function(bool) onCompletado;

  const _BultosScannerModal({
    required this.orden,
    required this.cantidadBultos,
    required this.onCompletado,
  });

  @override
  State<_BultosScannerModal> createState() => _BultosScannerModalState();
}

class _BultosScannerModalState extends State<_BultosScannerModal> {
  late MobileScannerController _scannerController;
  int _bultosEscaneados = 0; // Contador de bultos escaneados
  bool _procesando = false;
  DateTime? _ultimoEscaneo; // Para prevenir escaneos muy rápidos

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      torchEnabled: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onBarcodeDetect(BarcodeCapture capture) async {
    if (_procesando) return;
    
    // Prevenir escaneos muy rápidos (menos de 500ms entre escaneos)
    final ahora = DateTime.now();
    if (_ultimoEscaneo != null && ahora.difference(_ultimoEscaneo!).inMilliseconds < 500) {
      return;
    }
    
    final barcodes = capture.barcodes;
    for (final b in barcodes) {
      final value = b.rawValue;
      if (value != null && value.isNotEmpty && value == widget.orden.id) {
        // El QR escaneado debe ser el ID de la orden
        // Verificar que no se haya alcanzado el máximo de bultos
        if (_bultosEscaneados >= widget.cantidadBultos) {
          return;
        }
        
        setState(() {
          _procesando = true;
          _bultosEscaneados++;
          _ultimoEscaneo = ahora;
        });
        
        // Mostrar confirmación de bulto escaneado
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bulto $_bultosEscaneados/${widget.cantidadBultos} escaneado',
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF4CAF50),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        
        // Si todos los bultos están escaneados, habilitar botón de continuar
        if (_bultosEscaneados >= widget.cantidadBultos) {
          widget.onCompletado(true);
        }
        
        // Resetear procesando después de un pequeño delay
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          setState(() {
            _procesando = false;
          });
        }
        
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progreso = _bultosEscaneados;
    final total = widget.cantidadBultos;
    final porcentaje = total > 0 ? (progreso / total) : 0.0;
    final todosEscaneados = progreso >= total;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF2196F3),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Validar Bultos',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Orden: #${widget.orden.numeroOrden}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            
            // Progreso
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Bultos escaneados: $progreso/$total',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: porcentaje,
                    backgroundColor: const Color(0xFFE0E0E0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      todosEscaneados ? const Color(0xFF4CAF50) : const Color(0xFF2196F3),
                    ),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 8),
                  if (todosEscaneados)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Todos los bultos escaneados',
                          style: TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Escanea el siguiente bulto...',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            
            // Escáner
            Container(
              height: 300,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2196F3), width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onBarcodeDetect,
                    ),
                    // Overlay con instrucciones
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_scanner, color: Colors.white, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'Apunta la cámara al QR del bulto',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Botones
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF666666),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: todosEscaneados
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

