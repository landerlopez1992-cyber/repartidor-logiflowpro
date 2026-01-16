import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import '../models/orden.dart';
import '../main.dart';

class OrdenPrintModal extends StatefulWidget {
  final Orden orden;

  const OrdenPrintModal({
    super.key,
    required this.orden,
  });

  @override
  State<OrdenPrintModal> createState() => _OrdenPrintModalState();
}

class _OrdenPrintModalState extends State<OrdenPrintModal> {
  bool _isLoading = true;
  bool _incluirQR = true;
  bool _incluirDatosDestinatario = true;
  bool _incluirSoloNombreDestinatario = false;
  bool _incluirNumeroOrden = true;
  bool _incluirLogoEmpresa = false;
  bool _incluirNumeroBultos = false;
  bool _incluirNombreEmpresa = false;
  bool _incluirRepartidorAsignado = false;
  
  // Datos de la empresa
  String? _empresaLogoUrl;
  String? _empresaNombre;
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _cargarConfiguracion();
  }

  Future<void> _cargarConfiguracion() async {
    try {
      print('📋 Cargando configuración de impresión...');
      
      // Obtener tenant_id del usuario actual
      String? tenantId;
      final user = supabase.auth.currentUser;
      if (user != null) {
        try {
          final userData = await supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .limit(1)
              .maybeSingle();
          
          if (userData != null && userData['tenant_id'] != null) {
            tenantId = userData['tenant_id'].toString();
            print('✅ Tenant ID obtenido: $tenantId');
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id: $e');
        }
      }
      
      // Cargar configuración filtrando por tenant_id
      var query = supabase
          .from('configuracion_envios')
          .select('incluir_qr, incluir_datos_destinatario, incluir_solo_nombre_destinatario, incluir_numero_orden, incluir_logo_empresa, incluir_numero_bultos, incluir_nombre_empresa, incluir_repartidor_asignado');
      
      if (tenantId != null && tenantId.isNotEmpty) {
        query = query.eq('tenant_id', tenantId);
        print('🔒 Filtrando configuración por tenant_id: $tenantId');
      }
      
      final responseList = await query.limit(1);

      if (mounted) {
        setState(() {
          if (responseList.isEmpty) {
            print('⚠️ No hay configuración, usando valores por defecto');
            // Usar valores por defecto (todo desactivado excepto los que normalmente están activos)
            _incluirQR = false;
            _incluirDatosDestinatario = false;
            _incluirSoloNombreDestinatario = false;
            _incluirNumeroOrden = false;
            _incluirLogoEmpresa = false;
            _incluirNumeroBultos = false;
            _incluirNombreEmpresa = false;
            _incluirRepartidorAsignado = false;
          } else {
            final response = responseList[0];
            // Usar directamente los interruptores individuales (sin valores por defecto)
            _incluirQR = response['incluir_qr'] == true;
            _incluirDatosDestinatario = response['incluir_datos_destinatario'] == true;
            _incluirSoloNombreDestinatario = response['incluir_solo_nombre_destinatario'] == true;
            _incluirNumeroOrden = response['incluir_numero_orden'] == true;
            _incluirLogoEmpresa = response['incluir_logo_empresa'] == true;
            _incluirNumeroBultos = response['incluir_numero_bultos'] == true;
            _incluirNombreEmpresa = response['incluir_nombre_empresa'] == true;
            _incluirRepartidorAsignado = response['incluir_repartidor_asignado'] == true;
            print('✅ Configuración cargada: QR=$_incluirQR, Destinatario=$_incluirDatosDestinatario, SoloNombreDestinatario=$_incluirSoloNombreDestinatario, NumOrden=$_incluirNumeroOrden, Logo=$_incluirLogoEmpresa, Bultos=$_incluirNumeroBultos, Nombre=$_incluirNombreEmpresa, Repartidor=$_incluirRepartidorAsignado');
          }
        });
      }
      
      // Cargar datos de la empresa SIEMPRE (para la vista previa)
      await _cargarDatosEmpresa();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error al cargar configuración de impresión: $e');
      if (mounted) {
        setState(() {
          // Usar valores por defecto en caso de error (todo desactivado)
          _incluirQR = false;
          _incluirDatosDestinatario = false;
          _incluirSoloNombreDestinatario = false;
          _incluirNumeroOrden = false;
          _incluirLogoEmpresa = false;
          _incluirNumeroBultos = false;
          _incluirNombreEmpresa = false;
          _incluirRepartidorAsignado = false;
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _cargarDatosEmpresa() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      
      if (userData == null || userData['tenant_id'] == null) return;
      
      final tenantId = userData['tenant_id'];
      
      final tenantData = await supabase
          .from('tenants')
          .select('nombre, logo_url')
          .eq('id', tenantId)
          .maybeSingle();
      
      if (tenantData != null) {
        if (mounted) {
          setState(() {
            _empresaNombre = tenantData['nombre'];
            _empresaLogoUrl = tenantData['logo_url'];
          });
        }
        
        // Descargar el logo si está activado
        if (_incluirLogoEmpresa && _empresaLogoUrl != null && _empresaLogoUrl!.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(_empresaLogoUrl!));
            if (response.statusCode == 200 && mounted) {
              setState(() {
                _logoBytes = response.bodyBytes;
              });
            }
          } catch (e) {
            print('⚠️ Error descargando logo: $e');
          }
        }
      }
    } catch (e) {
      print('❌ Error cargando datos de empresa: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(const Color(0xFF4CAF50)),
              ),
              const SizedBox(height: 16),
              Text(
                'Cargando configuración...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: kIsWeb ? 700 : double.infinity,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1A2E),
              const Color(0xFF16213E),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.local_printshop,
                          color: Color(0xFF66BB6A),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Imprimir Etiqueta del Paquete',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Información de la orden
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.1),
                            Colors.white.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Orden #${widget.orden.numeroOrden}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Destinatario: ${widget.orden.receptor}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                          if (widget.orden.direccionDestino != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Dirección: ${widget.orden.direccionDestino}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Vista previa de la configuración
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.1),
                            Colors.white.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Vista Previa',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                      const SizedBox(height: 12),
                      
                          const SizedBox(height: 12),
                          
                          // Logo de la empresa - SIEMPRE SE MUESTRA
                          if (_logoBytes != null)
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.1),
                                      Colors.white.withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                ),
                                child: Image.memory(
                                  _logoBytes!,
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          
                          // Nombre de la empresa - SIEMPRE SE MUESTRA
                          if (_empresaNombre != null) ...[
                            if (_logoBytes != null) const SizedBox(height: 8),
                            Center(
                              child: Text(
                                _empresaNombre!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          
                          // Número de orden - SIEMPRE SE MUESTRA
                          if (_logoBytes != null || _empresaNombre != null) const SizedBox(height: 8),
                          Center(
                            child: Text(
                              '#${widget.orden.numeroOrden}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          
                          // Número de bultos - SIEMPRE SE MUESTRA
                          if (widget.orden.cantidadBultos != null && widget.orden.cantidadBultos! > 0) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFFFF9800).withOpacity(0.2),
                                      const Color(0xFFFF9800).withOpacity(0.1),
                                    ],
                                  ),
                                  border: Border.all(color: const Color(0xFFFF9800), width: 1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.inventory_2, size: 14, color: Color(0xFFFF9800)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${widget.orden.cantidadBultos}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          
                          // Repartidor asignado - SIEMPRE SE MUESTRA
                          if (widget.orden.repartidor != null && widget.orden.repartidor!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                'Repartidor: ${widget.orden.repartidor}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                          
                          // Código QR - SIEMPRE SE MUESTRA
                          const SizedBox(height: 14),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.1),
                                    Colors.white.withOpacity(0.05),
                                  ],
                                ),
                                border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white,
                              ),
                              child: Center(
                                child: QrImageView(
                                  data: widget.orden.id, // El ID de la orden es único
                                  version: QrVersions.auto,
                                  size: 120,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF37474F),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF37474F),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                          // Datos del destinatario - SIEMPRE SE MUESTRAN
                          const SizedBox(height: 14),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.08),
                                    Colors.white.withOpacity(0.04),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'PARA:',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white.withOpacity(0.7),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.orden.receptor.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (widget.orden.telefonoDestinatario != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tel: ${widget.orden.telefonoDestinatario}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  if (widget.orden.direccionDestino != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.orden.direccionDestino!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Botones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.7),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: const Text('Cancelar', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _imprimirEtiqueta,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 4,
                      shadowColor: const Color(0xFF4CAF50).withOpacity(0.4),
                    ),
                    child: const Text('Imprimir', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _imprimirEtiqueta() async {
    try {
      print('🖨️ [ORDEN_PRINT] Iniciando impresión de etiqueta...');
      
      // Obtener cantidad de bultos antes de generar el PDF
      final cantidadBultos = widget.orden.cantidadBultos ?? 1;
      final numeroBultos = cantidadBultos > 0 ? cantidadBultos : 1;
      
      print('📦 [ORDEN_PRINT] Orden #${widget.orden.numeroOrden} - Bultos: $numeroBultos');
      
      final pdf = await _generarPDF();
      
      // Verificar que el PDF se haya generado correctamente
      final pdfBytes = await pdf.save();
      print('✅ [ORDEN_PRINT] PDF generado: ${pdfBytes.length} bytes');
      print('📄 [ORDEN_PRINT] Se generaron $numeroBultos página(s) en el PDF (una por cada bulto)');
      
      // Mostrar mensaje informativo si hay múltiples bultos
      if (numeroBultos > 1 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se generaron $numeroBultos etiquetas (una por cada bulto). El diálogo de impresión mostrará todas las páginas.'),
            backgroundColor: const Color(0xFF4CAF50),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
      
      print('✅ [ORDEN_PRINT] Diálogo de impresión abierto');
    } catch (e) {
      print('❌ [ORDEN_PRINT] Error al imprimir: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al preparar impresión: $e'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<pw.Document> _generarPDF() async {
    final pdf = pw.Document();
    
    // Debug: Verificar qué está activado
    print('🔍 [ORDEN_PRINT] DEBUG PDF - Configuración:');
    print('   - _incluirQR: $_incluirQR');
    print('   - _incluirDatosDestinatario: $_incluirDatosDestinatario');
    print('   - _incluirSoloNombreDestinatario: $_incluirSoloNombreDestinatario');
    print('   - _incluirNumeroOrden: $_incluirNumeroOrden');
    print('   - _incluirLogoEmpresa: $_incluirLogoEmpresa');
    print('   - _incluirNumeroBultos: $_incluirNumeroBultos');
    print('   - _incluirNombreEmpresa: $_incluirNombreEmpresa');
    print('   - _incluirRepartidorAsignado: $_incluirRepartidorAsignado');
    print('   - Orden ID: ${widget.orden.id}');
    
    // Generar el código QR como imagen (solo si está habilitado)
    Uint8List? qrImageBytes;
    if (_incluirQR) {
      try {
        print('🔄 [ORDEN_PRINT] Generando QR para orden ID: ${widget.orden.id}');
        qrImageBytes = await _generarQRBytes();
        if (qrImageBytes != null) {
          print('✅ [ORDEN_PRINT] QR generado correctamente: ${qrImageBytes.length} bytes');
        } else {
          print('❌ [ORDEN_PRINT] QR es null después de generar');
        }
      } catch (e, stackTrace) {
        print('❌ [ORDEN_PRINT] Error generando QR: $e');
        print('   Stack trace: $stackTrace');
        qrImageBytes = null;
      }
    } else {
      print('⚠️ [ORDEN_PRINT] QR deshabilitado en configuración');
    }

    // Formato 4x6 pulgadas para etiquetas térmicas (estándar de paquetería)
    // 288 puntos x 432 puntos (72 DPI)
    final labelFormat = PdfPageFormat(
      4 * PdfPageFormat.inch,  // 4 pulgadas de ancho
      6 * PdfPageFormat.inch,  // 6 pulgadas de alto
      marginAll: 0.15 * PdfPageFormat.inch, // Márgenes pequeños
    );

    // Logs antes de construir el PDF
    print('🔍 [ORDEN_PRINT] Antes de construir PDF:');
    print('   - _incluirQR: $_incluirQR');
    print('   - qrImageBytes: ${qrImageBytes != null ? "${qrImageBytes.length} bytes" : "null"}');
    print('   - Orden ID: ${widget.orden.id}');
    print('   - Cantidad de bultos: ${widget.orden.cantidadBultos ?? 1}');
    
    // Obtener cantidad de bultos (mínimo 1 si es null o 0)
    final cantidadBultos = widget.orden.cantidadBultos ?? 1;
    final numeroBultos = cantidadBultos > 0 ? cantidadBultos : 1;
    
    print('📦 Generando $numeroBultos etiqueta(s) para orden #${widget.orden.numeroOrden}');
    
    // Generar una página por cada bulto
    for (int i = 0; i < numeroBultos; i++) {
    pdf.addPage(
      pw.Page(
        pageFormat: labelFormat,
        build: (pw.Context context) {
          // Si SOLO QR está activado (sin otros elementos), mostrar QR centrado verticalmente
          if (_incluirQR && !_incluirDatosDestinatario && !_incluirSoloNombreDestinatario && !_incluirNumeroOrden && !_incluirLogoEmpresa && !_incluirNumeroBultos && !_incluirNombreEmpresa && !_incluirRepartidorAsignado && qrImageBytes != null) {
            return pw.Center(
              child: pw.Container(
                width: 250,  // QR más grande y centrado
                height: 250,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 2, color: PdfColors.black),
                ),
                child: pw.Image(
                  pw.MemoryImage(qrImageBytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
            );
          }
          
          // Si hay más elementos además del QR, mostrar todo según configuración
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            mainAxisAlignment: pw.MainAxisAlignment.center, // Centrar verticalmente
            children: [
              // Logo de la empresa (solo si está habilitado) - Tamaño reducido
              if (_incluirLogoEmpresa && _logoBytes != null) ...[
                pw.Center(
                  child: pw.Image(
                    pw.MemoryImage(_logoBytes!),
                    width: 50,
                    height: 50,
                    fit: pw.BoxFit.contain,
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
              
              // Nombre de la empresa (solo si está habilitado) - Tamaño reducido
              if (_incluirNombreEmpresa && _empresaNombre != null) ...[
                pw.Text(
                  _empresaNombre!,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                ),
                pw.SizedBox(height: 4),
              ],
              
              // Número de orden (solo si está habilitado) - Tamaño reducido
              if (_incluirNumeroOrden) ...[
                pw.Text(
                  '#${widget.orden.numeroOrden}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
              ],
              
              // Número de bultos (solo si está habilitado) - Tamaño reducido
              if (_incluirNumeroBultos && widget.orden.cantidadBultos != null && widget.orden.cantidadBultos! > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 1, color: PdfColors.black),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(
                            'Bultos: ${widget.orden.cantidadBultos}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
              ],
              
              // Repartidor asignado (solo si está habilitado) - Tamaño reducido
              if (_incluirRepartidorAsignado && widget.orden.repartidor != null && widget.orden.repartidor!.isNotEmpty) ...[
                pw.Text(
                  'Rep: ${widget.orden.repartidor}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.normal,
                  ),
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                ),
                pw.SizedBox(height: 4),
              ],
              
              // CÓDIGO QR GRANDE - Prioritario (solo si está habilitado) - Centrado verticalmente
              if (_incluirQR) ...[
                if (qrImageBytes != null) ...[
                  pw.Spacer(flex: 1), // Espacio antes del QR para centrarlo
                  pw.Center(
                    child: pw.Container(
                      width: 180,  // QR grande pero ajustado para que quepa todo
                      height: 180,
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(width: 2, color: PdfColors.black),
                      ),
                      child: pw.Image(
                        pw.MemoryImage(qrImageBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                  pw.Spacer(flex: 1), // Espacio después del QR para centrarlo
                  pw.SizedBox(height: 6),
                ] else ...[
                  // Si el QR está habilitado pero no se pudo generar, mostrar mensaje
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.yellow100,
                      border: pw.Border.all(color: PdfColors.orange, width: 1),
                    ),
                    child: pw.Text(
                      'QR no disponible',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.orange,
                        fontStyle: pw.FontStyle.italic,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
              ],
              
              // Divider solo si hay más contenido después del QR
              if (_incluirDatosDestinatario || _incluirSoloNombreDestinatario) ...[
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),
              ],
              
              // Solo nombre del destinatario (si está habilitado) - TAMAÑO REDUCIDO para no obstruir QR
              if (_incluirSoloNombreDestinatario && !_incluirDatosDestinatario) ...[
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: pw.Text(
                    widget.orden.receptor.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8, // Reducido de 12 a 8 para no obstruir QR
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                  ),
                ),
                pw.SizedBox(height: 2), // Reducido de 4 a 2
              ],
              
              // Destinatario - INFORMACIÓN COMPLETA (solo si está habilitado) - Tamaño reducido
              if (_incluirDatosDestinatario)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey300,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PARA:',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 1),
                      pw.Text(
                        widget.orden.receptor.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                      if (widget.orden.telefonoDestinatario != null) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          'Tel: ${widget.orden.telefonoDestinatario}',
                          style: const pw.TextStyle(fontSize: 7),
                        ),
                      ],
                      pw.SizedBox(height: 1),
                      pw.Text(
                        widget.orden.direccionDestino,
                        style: const pw.TextStyle(fontSize: 7),
                        maxLines: 2,
                      ),
                      // Provincia y Municipio
                      if (widget.orden.provinciaDestino != null || widget.orden.municipioDestino != null) ...[
                        pw.SizedBox(height: 1),
                        pw.Text(
                          '${widget.orden.municipioDestino ?? ''}, ${widget.orden.provinciaDestino ?? ''}'.trim().replaceAll(RegExp(r'^,\s*|,\s*$'), ''),
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          maxLines: 1,
                        ),
                      ],
                    ],
                  ),
                ),
              
              if (_incluirDatosDestinatario || _incluirSoloNombreDestinatario)
                pw.SizedBox(height: 4),
              
              pw.Spacer(),
              
              // Pie de página minimalista
              pw.Text(
                'Impreso: ${_formatFechaCorta(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 5),
              ),
            ],
          );
        },
      ),
    );
    }

    print('✅ [ORDEN_PRINT] PDF generado con $numeroBultos página(s) (una por cada bulto)');
    print('📦 [ORDEN_PRINT] Orden #${widget.orden.numeroOrden} - Bultos: $numeroBultos - Páginas generadas: $numeroBultos');

    return pdf;
  }

  Future<Uint8List> _generarQRBytes() async {
    try {
      print('🔄 [ORDEN_PRINT] Iniciando generación de QR...');
      print('   - Orden ID: ${widget.orden.id}');
      print('   - Tipo de ID: ${widget.orden.id.runtimeType}');
      
      if (widget.orden.id == null || widget.orden.id.toString().isEmpty) {
        throw Exception('El ID de la orden es null o vacío');
      }
      
      final qrImageData = await QrPainter(
        data: widget.orden.id.toString(), // Asegurar que sea String
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        color: const Color(0xFF37474F),
        emptyColor: Colors.white,
      ).toImageData(300);

      if (qrImageData == null) {
        throw Exception('QrPainter retornó null');
      }

      // toImageData retorna ByteData directamente, convertirlo a Uint8List
      final bytes = qrImageData.buffer.asUint8List();
      print('✅ [ORDEN_PRINT] QR generado: ${bytes.length} bytes');
      return bytes;
    } catch (e, stackTrace) {
      print('❌ [ORDEN_PRINT] Error en _generarQRBytes: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  String _formatFechaCorta(DateTime fecha) {
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
  }
}
