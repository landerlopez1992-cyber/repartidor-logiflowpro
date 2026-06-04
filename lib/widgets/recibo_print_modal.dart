import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import '../models/orden.dart';
import '../main.dart';
import '../config/app_colors.dart';

class ReciboPrintModal extends StatefulWidget {
  final Orden orden;

  const ReciboPrintModal({
    super.key,
    required this.orden,
  });

  @override
  State<ReciboPrintModal> createState() => _ReciboPrintModalState();
}

class _ReciboPrintModalState extends State<ReciboPrintModal> {
  String? _empresaLogoUrl;
  String? _empresaNombre;
  String? _empresaDireccion;
  String? _empresaTelefono;
  String? _empresaEmail;
  String? _empresaSitioWeb;
  bool _isLoadingLogo = true;
  Uint8List? _logoBytes;
  Uint8List? _qrImageBytes;
  
  // Datos del emisor (email y teléfono)
  String? _emisorEmail;
  String? _emisorTelefono;
  
  // Configuración de precios
  double? _precioPorLibra;
  double? _costoEnvio;
  List<Map<String, dynamic>> _umbrales = []; // Umbrales de precio por volumen
  
  // Configuración de fee de remesa
  bool _cobrarFeeRemesa = false;
  String _tipoFeeRemesa = 'porcentaje';
  double _porcentajeFeeRemesa = 0.0;
  double _feeFijoRemesa = 0.0;
  
  // URL del código QR (se actualizará con el sitio web de la empresa)
  String? _qrAppUrl;
  
  // Configuración de QR del recibo
  bool _mostrarQRRecibo = true;
  bool _activarQR1Recibo = false;
  bool _activarQR2Recibo = false;
  String _urlQR1Recibo = '';
  String _urlQR2Recibo = '';
  String _textoQR1Recibo = 'Escanea para descargar'; // Texto personalizado para QR 1
  String _textoQR2Recibo = 'Escanea para descargar'; // Texto personalizado para QR 2
  bool _mostrarTextoPromocionalRecibo = true;
  String _textoPromocionalRecibo = '';
  
  // URLs de los QRs personalizados
  Uint8List? _qr1ImageBytes;
  Uint8List? _qr2ImageBytes;
  
  // URL del servicio de generación de QR (imagen) - para compatibilidad con código antiguo
  String? get _qrImageUrl => _qrAppUrl != null 
      ? 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=$_qrAppUrl'
      : null;

  @override
  void initState() {
    super.initState();
    print('🚀 [RECIBO_PRINT_MODAL] initState - Iniciando modal');
    _cargarLogoEmpresa();
    _cargarConfiguracionPrecios();
    _cargarConfiguracionQRRecibo();
    // _cargarQRImagen() se llamará después de cargar los datos de la empresa en _cargarLogoEmpresa()
  }
  
  Future<void> _cargarConfiguracionQRRecibo() async {
    try {
      print('🔄 [CARGAR_CONFIG_QR] Iniciando carga desde Supabase...');
      final responseList = await supabase
          .from('configuracion_envios')
          .select('mostrar_qr_recibo, activar_qr1_recibo, activar_qr2_recibo, url_qr1_recibo, url_qr2_recibo, texto_qr1_recibo, texto_qr2_recibo, mostrar_texto_promocional_recibo, texto_promocional_recibo')
          .limit(1);
      
      print('🔄 [CARGAR_CONFIG_QR] Respuesta de Supabase: $responseList');
      
      if (responseList.isNotEmpty) {
        final config = responseList[0];
        print('🔄 [CARGAR_CONFIG_QR] Configuración encontrada: $config');
        
        if (mounted) {
          setState(() {
            _mostrarQRRecibo = config['mostrar_qr_recibo'] ?? true;
            _activarQR1Recibo = config['activar_qr1_recibo'] ?? false;
            _activarQR2Recibo = config['activar_qr2_recibo'] ?? false;
            _urlQR1Recibo = config['url_qr1_recibo'] ?? '';
            _urlQR2Recibo = config['url_qr2_recibo'] ?? '';
            _textoQR1Recibo = config['texto_qr1_recibo'] ?? 'Escanea para descargar';
            _textoQR2Recibo = config['texto_qr2_recibo'] ?? 'Escanea para descargar';
            _mostrarTextoPromocionalRecibo = config['mostrar_texto_promocional_recibo'] ?? true;
            _textoPromocionalRecibo = config['texto_promocional_recibo'] ?? '';
            
            print('✅ [CARGAR_CONFIG_QR] Variables de estado actualizadas:');
            print('   - _mostrarQRRecibo: $_mostrarQRRecibo');
            print('   - _activarQR1Recibo: $_activarQR1Recibo');
            print('   - _urlQR1Recibo: "$_urlQR1Recibo"');
            print('   - _textoQR1Recibo: "$_textoQR1Recibo"');
            print('   - _activarQR2Recibo: $_activarQR2Recibo');
            print('   - _urlQR2Recibo: "$_urlQR2Recibo"');
            print('   - _textoQR2Recibo: "$_textoQR2Recibo"');
          });
          
          // Cargar QRs FUERA del setState para poder usar await
          if (_activarQR1Recibo && _urlQR1Recibo.isNotEmpty) {
            print('✅ [CARGAR_CONFIG_QR] QR 1 activado, iniciando descarga...');
            await _cargarQRImagenPersonalizado(_urlQR1Recibo, 1);
            // Esperar a que se complete la carga
            int intentos = 0;
            while (_qr1ImageBytes == null && intentos < 50 && mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              intentos++;
            }
            if (_qr1ImageBytes != null) {
              print('✅ [CARGAR_CONFIG_QR] QR 1 cargado correctamente: ${_qr1ImageBytes!.length} bytes');
            } else {
              print('❌ [CARGAR_CONFIG_QR] QR 1 no se pudo cargar después de 5 segundos');
            }
          } else {
            print('⚠️ [CARGAR_CONFIG_QR] QR 1 NO se cargará: activado=$_activarQR1Recibo, URL vacía=${_urlQR1Recibo.isEmpty}');
          }
          if (_activarQR2Recibo && _urlQR2Recibo.isNotEmpty) {
            print('✅ [CARGAR_CONFIG_QR] QR 2 activado, iniciando descarga...');
            await _cargarQRImagenPersonalizado(_urlQR2Recibo, 2);
            // Esperar a que se complete la carga
            int intentos = 0;
            while (_qr2ImageBytes == null && intentos < 50 && mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              intentos++;
            }
            if (_qr2ImageBytes != null) {
              print('✅ [CARGAR_CONFIG_QR] QR 2 cargado correctamente: ${_qr2ImageBytes!.length} bytes');
            } else {
              print('❌ [CARGAR_CONFIG_QR] QR 2 no se pudo cargar después de 5 segundos');
            }
          } else {
            print('⚠️ [CARGAR_CONFIG_QR] QR 2 NO se cargará: activado=$_activarQR2Recibo, URL vacía=${_urlQR2Recibo.isEmpty}');
          }
        }
      } else {
        print('⚠️ [CARGAR_CONFIG_QR] No se encontró configuración en Supabase');
      }
    } catch (e, stackTrace) {
      print('❌ [CARGAR_CONFIG_QR] Error al cargar configuración: $e');
      print('   Stack trace: $stackTrace');
    }
  }
  
  Future<void> _cargarQRImagenPersonalizado(String url, int numeroQR) async {
    try {
      print('🔄 [CARGAR_QR_$numeroQR] Iniciando descarga...');
      print('   URL recibida: "$url"');
      
      if (url.isEmpty) {
        print('⚠️ [CARGAR_QR_$numeroQR] URL vacía, abortando');
        return;
      }
      
      final qrImageUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(url)}';
      
      print('🔄 [CARGAR_QR_$numeroQR] Descargando desde: $qrImageUrl');
      
      final response = await http.get(Uri.parse(qrImageUrl));
      
      print('📥 [CARGAR_QR_$numeroQR] Respuesta HTTP:');
      print('   Status: ${response.statusCode}');
      print('   Tamaño: ${response.bodyBytes.length} bytes');
      
      if (response.statusCode == 200) {
        final imageBytes = response.bodyBytes;
        print('✅ [CARGAR_QR_$numeroQR] Imagen descargada correctamente: ${imageBytes.length} bytes');
        
        if (mounted) {
          setState(() {
            if (numeroQR == 1) {
              _qr1ImageBytes = imageBytes;
            } else {
              _qr2ImageBytes = imageBytes;
            }
          });
          print('✅ [CARGAR_QR_$numeroQR] Guardado en setState');
        } else {
          if (numeroQR == 1) {
            _qr1ImageBytes = imageBytes;
          } else {
            _qr2ImageBytes = imageBytes;
          }
          print('✅ [CARGAR_QR_$numeroQR] Guardado sin setState (widget no mounted)');
        }
        
        // Verificación final
        final finalBytes = numeroQR == 1 ? _qr1ImageBytes : _qr2ImageBytes;
        if (finalBytes != null) {
          print('✅ [CARGAR_QR_$numeroQR] VERIFICACIÓN FINAL: QR guardado correctamente (${finalBytes.length} bytes)');
        } else {
          print('❌ [CARGAR_QR_$numeroQR] VERIFICACIÓN FINAL: QR es NULL después de guardar!!!');
        }
      } else {
        print('❌ [CARGAR_QR_$numeroQR] Error HTTP: Status ${response.statusCode}');
        print('   Respuesta: ${response.body}');
      }
    } catch (e, stackTrace) {
      print('❌ [CARGAR_QR_$numeroQR] Excepción: $e');
      print('   Stack trace: $stackTrace');
    }
  }
  
  Future<void> _cargarQRImagen() async {
    try {
      final qrImageUrl = _qrImageUrl;
      if (qrImageUrl == null) {
        print('⚠️ No hay URL de QR disponible aún');
        return;
      }
      
      print('🔄 Descargando imagen QR desde: $qrImageUrl');
      final response = await http.get(Uri.parse(qrImageUrl));
      
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _qrImageBytes = response.bodyBytes;
        });
        print('✅ QR imagen descargada correctamente (${_qrImageBytes!.length} bytes)');
      } else {
        print('❌ Error descargando QR: Status ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error cargando QR imagen: $e');
    }
  }

  Future<void> _cargarLogoEmpresa() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoadingLogo = false;
        });
        return;
      }

      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .single();

      final tenantId = userData['tenant_id'];
      if (tenantId == null) {
        setState(() {
          _isLoadingLogo = false;
        });
        return;
      }

      final empresaData = await supabase
          .from('tenants')
          .select('nombre, logo_url, direccion, telefono, email_contacto, sitio_web')
          .eq('id', tenantId)
          .single();

      final logoUrl = empresaData['logo_url'];
      final nombre = empresaData['nombre'];
      final direccion = empresaData['direccion'];
      final telefono = empresaData['telefono'];
      final email = empresaData['email_contacto'];
      final sitioWeb = empresaData['sitio_web'];

      if (mounted) {
        setState(() {
          _empresaNombre = nombre;
          _empresaLogoUrl = logoUrl;
          _empresaDireccion = direccion;
          _empresaTelefono = telefono;
          _empresaEmail = email;
          _empresaSitioWeb = sitioWeb;
          
          // Actualizar URL del QR con el sitio web de la empresa
          if (sitioWeb != null && sitioWeb.toString().trim().isNotEmpty) {
            // Si el sitio web no tiene http/https, agregarlo
            String sitioWebUrl = sitioWeb.toString().trim();
            if (!sitioWebUrl.startsWith('http://') && !sitioWebUrl.startsWith('https://')) {
              sitioWebUrl = 'https://$sitioWebUrl';
            }
            // Agregar /app al final si no está presente
            if (!sitioWebUrl.endsWith('/app')) {
              sitioWebUrl = '$sitioWebUrl/app';
            }
            _qrAppUrl = sitioWebUrl;
          } else {
            // CRÍTICO: No usar URL de otra empresa como fallback
            // Si no hay sitio web configurado, usar URL genérica o vacía
            _qrAppUrl = 'https://www.logiflowpro.com/app';
            print('⚠️ No hay sitio web configurado para esta empresa, usando URL genérica');
          }
          
          // Cargar QR después de tener el sitio web
          _cargarQRImagen();
        });

        // Cargar los bytes de la imagen si existe
        if (logoUrl != null && logoUrl.toString().isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(logoUrl));
            if (response.statusCode == 200) {
              setState(() {
                _logoBytes = response.bodyBytes;
              });
            }
          } catch (e) {
            print('Error cargando logo: $e');
          }
        }

        setState(() {
          _isLoadingLogo = false;
        });
        
        // Cargar datos del emisor (email y teléfono)
        await _cargarDatosEmisor();
      }
    } catch (e) {
      print('Error cargando datos de empresa: $e');
      if (mounted) {
        setState(() {
          _isLoadingLogo = false;
        });
      }
    }
  }

  Future<void> _cargarConfiguracionPrecios() async {
    try {
      // Obtener tenant_id del usuario actual
      final user = supabase.auth.currentUser;
      if (user == null) return;
      
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      
      final tenantId = userData?['tenant_id'];
      if (tenantId == null) return;
      
      final responseList = await supabase
          .from('configuracion_envios')
          .select('precio_por_libra, costo_envio, cobrar_fee_remesa, tipo_fee_remesa, porcentaje_fee_remesa, fee_fijo_remesa')
          .eq('tenant_id', tenantId)
          .limit(1);
      
      // Cargar umbrales de precio por libra
      List<Map<String, dynamic>> umbrales = [];
      try {
        final umbralesResponse = await supabase
            .from('umbrales_precio_libra')
            .select()
            .eq('tenant_id', tenantId)
            .eq('activo', true)
            .order('umbral_minimo', ascending: false); // Ordenar de mayor a menor
        umbrales = List<Map<String, dynamic>>.from(umbralesResponse);
        print('✅ [RECIBO] ${umbrales.length} umbrales cargados');
      } catch (e) {
        print('⚠️ [RECIBO] Error al cargar umbrales: $e');
      }
      
      if (responseList.isNotEmpty) {
        final config = responseList[0];
        if (mounted) {
          setState(() {
            _precioPorLibra = (config['precio_por_libra'] ?? 0.0).toDouble();
            _costoEnvio = (config['costo_envio'] ?? 0.0).toDouble();
            _umbrales = umbrales;
            
            // Configuración de fee de remesa
            _cobrarFeeRemesa = config['cobrar_fee_remesa'] ?? false;
            _tipoFeeRemesa = config['tipo_fee_remesa'] ?? 'porcentaje';
            _porcentajeFeeRemesa = (config['porcentaje_fee_remesa'] ?? 0.0).toDouble();
            _feeFijoRemesa = (config['fee_fijo_remesa'] ?? 0.0).toDouble();
          });
        }
      }
    } catch (e) {
      print('❌ Error al cargar configuración de precios: $e');
    }
  }
  
  // Calcular fee de remesa
  double _calcularFeeRemesa(double cantidadRemesa) {
    if (!_cobrarFeeRemesa || cantidadRemesa <= 0) return 0.0;
    
    if (_tipoFeeRemesa == 'porcentaje' && _porcentajeFeeRemesa > 0) {
      return (cantidadRemesa * _porcentajeFeeRemesa) / 100;
    } else if (_tipoFeeRemesa == 'fijo' && _feeFijoRemesa > 0) {
      return _feeFijoRemesa;
    }
    return 0.0;
  }
  
  // Calcular precio REAL por libra aplicado según umbrales de configuración
  // CRÍTICO: Usar los umbrales configurados, NO dividir precio_total_envio
  double? _calcularPrecioRealPorLibra() {
    if (widget.orden.peso == null || widget.orden.peso! <= 0) {
      return null;
    }
    
    final libras = widget.orden.peso!;
    
    // Determinar qué precio por libra aplicar según umbrales (igual que en editar_orden_screen)
    double precioAplicar = _precioPorLibra ?? 0.0; // Precio base por defecto
    
    if (_umbrales.isNotEmpty && libras > 0) {
      // Buscar el umbral más alto que cumpla la condición
      for (var umbral in _umbrales) { // Ya están ordenados de mayor a menor
        final umbralMin = umbral['umbral_minimo'] as int? ?? 0;
        final precioUmbral = (umbral['precio_por_libra'] as num?)?.toDouble() ?? 0.0;
        
        if (libras >= umbralMin && umbralMin > 0 && precioUmbral > 0) {
          precioAplicar = precioUmbral;
          print('✅ [RECIBO] Umbral aplicado: ${umbralMin}+ lbs → \$${precioUmbral}/libra para ${libras} lbs');
          break; // Usar el primer umbral que cumpla (el más alto)
        }
      }
    }
    
    return precioAplicar > 0 ? precioAplicar : null;
  }
  
  // Verificar si hay oferta aplicada comparando precio real vs precio base
  bool _tieneOfertaAplicada() {
    final precioReal = _calcularPrecioRealPorLibra();
    if (precioReal == null || _precioPorLibra == null || _precioPorLibra! <= 0) {
      return false;
    }
    // Si el precio real es menor que el precio base, hay oferta aplicada
    return precioReal < _precioPorLibra!;
  }
  
  // Calcular total recalculado sumando todos los componentes
  double _calcularTotalRecibo() {
    // CRÍTICO: Usar precio_total_envio como fuente de verdad si está disponible
    if (widget.orden.precioTotalEnvio != null && widget.orden.precioTotalEnvio! > 0) {
      return widget.orden.precioTotalEnvio!;
    }
    
    // Fallback: recalcular desde componentes
    double total = 0.0;
    bool hayDatosParaRecalcular = false;
    
    // Libras (si hay precio por libra configurado)
    if (widget.orden.peso != null && widget.orden.peso! > 0 && _precioPorLibra != null && _precioPorLibra! > 0) {
      total += widget.orden.peso! * _precioPorLibra!;
      hayDatosParaRecalcular = true;
    }
    
    // Costo de entrega (si está configurado Y la orden NO es recogida en sucursal)
    if (_costoEnvio != null && _costoEnvio! > 0 && !widget.orden.recogerEnSucursal) {
      total += _costoEnvio!;
      hayDatosParaRecalcular = true;
    }
    
    // Items adicionales
    if (widget.orden.itemsAdicionales != null && widget.orden.itemsAdicionales!.isNotEmpty) {
      for (var item in widget.orden.itemsAdicionales!) {
        final tipo = item['tipo']?.toString() ?? '';
        if (tipo == 'LB') {
          final precioPorLibra = (item['precio_por_libra'] ?? 0.0).toDouble();
          final peso = (item['peso'] ?? 0.0).toDouble();
          if (precioPorLibra > 0 && peso > 0) {
            total += precioPorLibra * peso;
            hayDatosParaRecalcular = true;
          }
        } else if (tipo == 'PRECIO_FIJO') {
          final precioFijo = (item['precio_fijo'] ?? 0.0).toDouble();
          if (precioFijo > 0) {
            total += precioFijo;
            hayDatosParaRecalcular = true;
          }
        }
      }
    }
    
    // Remesa
    if (widget.orden.tieneRemesa && widget.orden.cantidadRemesa != null && widget.orden.cantidadRemesa! > 0) {
      total += widget.orden.cantidadRemesa!;
      // Fee de remesa (si está configurado)
      final feeRemesa = _calcularFeeRemesa(widget.orden.cantidadRemesa!);
      if (feeRemesa > 0) {
        total += feeRemesa;
      }
      hayDatosParaRecalcular = true;
    }
    
    // Si hay datos para recalcular, usar el total recalculado
    // Si no, usar el monto guardado (puede ser que la orden se creó sin cálculo automático)
    return hayDatosParaRecalcular ? total : widget.orden.montoCobrar;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.receipt,
                      color: Color(0xFF66BB6A),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Imprimir Recibo',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            
            // Contenido
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Vista previa del recibo
                    Container(
                      width: double.infinity,
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
                          // Logo y título
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isLoadingLogo)
                                const SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF4CAF50),
                                    ),
                                  ),
                                )
                              else if (_empresaLogoUrl != null && _empresaLogoUrl!.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    _empresaLogoUrl!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0E0E0),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.business,
                                          size: 30,
                                          color: AppColors.darkTextMuted,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              else
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0E0E0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.business,
                                    size: 30,
                                    color: AppColors.darkTextMuted,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Título
                          Center(
                            child: Text(
                              _empresaNombre ?? 'RECIBO DE ENVÍO',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Texto de bienvenida
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Gracias por preferir a ${_empresaNombre ?? 'nuestra empresa'} la agencia más rápida en envíos a Cuba, en nuestras manos tu paquete llega volando!!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'RECIBO DE ENVÍO',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Divider(color: Colors.white.withOpacity(0.2), height: 1),
                          const SizedBox(height: 16),
                          
                          // Número de orden
                          _buildReciboRow('Número de Orden', Text(
                            '#${widget.orden.numeroOrden}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          )),
                          const SizedBox(height: 12),
                          
                          // Nombre y apellido de emisor con email y teléfono
                          _buildReciboRow(
                            'Emisor',
                            _buildEmisorConContacto(widget.orden.emisor),
                          ),
                          const SizedBox(height: 12),
                          
                          // Nombre del destinatario
                          _buildReciboRow('Destinatario', Text(
                            widget.orden.receptor,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.8),
                            ),
                          )),
                          const SizedBox(height: 12),
                          
                          // Dirección del destinatario (con municipio y provincia)
                          _buildReciboRow(
                            'Dirección de Entrega',
                            _buildDireccionCompleta(),
                          ),
                          const SizedBox(height: 12),
                          
                          // Teléfono del destinatario
                          if (widget.orden.telefonoDestinatario != null && widget.orden.telefonoDestinatario!.isNotEmpty) ...[
                            _buildReciboRow('Teléfono Destinatario', Text(
                              widget.orden.telefonoDestinatario!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 12),
                          
                          // Desglose de precios
                          Container(
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DESGLOSE DE PRECIOS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Divider(height: 16, color: Colors.white.withOpacity(0.2)),
                                
                                // Libras (con precio REAL aplicado, puede incluir ofertas)
                                if (widget.orden.peso != null && widget.orden.peso! > 0) ...[
                                  Builder(
                                    builder: (context) {
                                      final precioReal = _calcularPrecioRealPorLibra();
                                      final tieneOferta = _tieneOfertaAplicada();
                                      final precioMostrar = precioReal ?? _precioPorLibra ?? 0.0;
                                      final totalLibras = precioMostrar * widget.orden.peso!;
                                      
                                      return Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${widget.orden.peso!.toStringAsFixed(0)} LB a \$${precioMostrar.toStringAsFixed(2)} USD${tieneOferta ? ' (Oferta)' : ''}',
                                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                          ),
                                          Text(
                                            '\$${totalLibras.toStringAsFixed(2)} USD',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                
                                // Costo de entrega/delivery (solo si NO es recogida en sucursal)
                                if (_costoEnvio != null && _costoEnvio! > 0 && !widget.orden.recogerEnSucursal) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Entrega / Delivery',
                                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                      ),
                                      Text(
                                        '\$${_costoEnvio!.toStringAsFixed(2)} USD',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                
                                // Items adicionales (si existen)
                                if (widget.orden.itemsAdicionales != null && widget.orden.itemsAdicionales!.isNotEmpty) ...[
                                  ...widget.orden.itemsAdicionales!.map((item) {
                                    final nombre = item['nombre']?.toString() ?? 'Item';
                                    final tipo = item['tipo']?.toString() ?? '';
                                    double precio = 0.0;
                                    String descripcion = '';
                                    
                                    if (tipo == 'LB') {
                                      final precioPorLibra = (item['precio_por_libra'] ?? 0.0).toDouble();
                                      final peso = (item['peso'] ?? 0.0).toDouble();
                                      precio = precioPorLibra * peso;
                                      descripcion = '${peso.toStringAsFixed(1)} LB a \$${precioPorLibra.toStringAsFixed(2)} USD';
                                    } else if (tipo == 'PRECIO_FIJO') {
                                      precio = (item['precio_fijo'] ?? 0.0).toDouble();
                                      descripcion = 'Precio fijo';
                                    }
                                    
                                    if (precio > 0) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$nombre ($descripcion)',
                                                style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                              ),
                                            ),
                                            Text(
                                              '\$${precio.toStringAsFixed(2)} USD',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }).toList(),
                                ],
                                
                                // Remesa (si existe)
                                if (widget.orden.tieneRemesa && widget.orden.cantidadRemesa != null && widget.orden.cantidadRemesa! > 0) ...[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Remesa',
                                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                      ),
                                      Text(
                                        '\$${widget.orden.cantidadRemesa!.toStringAsFixed(2)} USD',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                  // Fee de remesa (si está configurado)
                                  if (_cobrarFeeRemesa) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _tipoFeeRemesa == 'porcentaje' 
                                              ? 'Fee remesa (${_porcentajeFeeRemesa.toStringAsFixed(1)}%)'
                                              : 'Fee remesa',
                                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                                        ),
                                        Text(
                                          '\$${_calcularFeeRemesa(widget.orden.cantidadRemesa!).toStringAsFixed(2)} USD',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                ],
                                
                                Divider(height: 16, color: Colors.white.withOpacity(0.2)),
                                
                                // Total (recalculado)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'PRECIO TOTAL:',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      '\$${_calcularTotalRecibo().toStringAsFixed(2)} ${widget.orden.moneda}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFF9800),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          
                          // Información de remesa (si aplica)
                          if (widget.orden.tieneRemesa) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFFF9800).withOpacity(0.2),
                                    const Color(0xFFFF9800).withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF9800), width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Remesa Enviada',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFF9800),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'El cliente envió ${widget.orden.cantidadRemesa != null ? '\$${widget.orden.cantidadRemesa!.toStringAsFixed(2)} USD' : 'una cantidad no especificada'} a ${widget.orden.receptor}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          // Advertencia de Pago Contra Entrega (si aplica)
                          if (widget.orden.requierePago && !widget.orden.pagado) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFFDC2626).withOpacity(0.2),
                                    const Color(0xFFDC2626).withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning, color: Color(0xFFDC2626), size: 20),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '⚠️ PAGO CONTRA ENTREGA',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'IMPORTANTE: El destinatario debe pagar al recibir la orden',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'MONTO A COBRAR:',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          '\$${widget.orden.montoCobrar.toStringAsFixed(2)} ${widget.orden.moneda}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (widget.orden.notasPago != null && widget.orden.notasPago!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Nota: ${widget.orden.notasPago}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: Colors.white.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          Divider(color: Colors.white.withOpacity(0.2), height: 1),
                          const SizedBox(height: 14),
                          
                          // Datos de contacto de la empresa
                          Text(
                            'Datos de Contacto',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_empresaNombre != null && _empresaNombre!.isNotEmpty)
                            _buildReciboRow('Empresa', Text(
                              _empresaNombre!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                          if (_empresaDireccion != null && _empresaDireccion!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildReciboRow('Dirección', Text(
                              _empresaDireccion!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                          ],
                          if (_empresaTelefono != null && _empresaTelefono!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildReciboRow('Teléfono', Text(
                              _empresaTelefono!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                          ],
                          if (_empresaEmail != null && _empresaEmail!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildReciboRow('Email', Text(
                              _empresaEmail!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                          ],
                          if (_empresaSitioWeb != null && _empresaSitioWeb!.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildReciboRow('Sitio Web', Text(
                              _empresaSitioWeb!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            )),
                          ],
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
                  top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
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
                  ElevatedButton.icon(
                    onPressed: () => _imprimirRecibo(context),
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Imprimir Recibo', style: TextStyle(fontSize: 14)),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReciboRow(String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ),
        Expanded(
          child: value,
        ),
      ],
    );
  }

  Future<void> _imprimirRecibo(BuildContext context) async {
    try {
      print('🔄 [IMPRIMIR_RECIBO] Iniciando generación de PDF...');
      
      // Mostrar diálogo de carga mientras se preparan los QRs
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    SizedBox(height: 16),
                    Text('Preparando recibo...'),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      
      // RECARGAR configuración justo antes de imprimir para asegurar valores actuales
      print('🔄 [IMPRIMIR_RECIBO] Recargando configuración desde Supabase...');
      await _cargarConfiguracionQRRecibo();
      
      // Esperar un momento para que se complete la carga
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verificar estado de QRs antes de generar PDF
      print('🔍 [IMPRIMIR_RECIBO] Estado de QRs después de recargar configuración:');
      print('  - _mostrarQRRecibo: $_mostrarQRRecibo');
      print('  - _activarQR1Recibo: $_activarQR1Recibo');
      print('  - _urlQR1Recibo: "$_urlQR1Recibo"');
      print('  - _qr1ImageBytes: ${_qr1ImageBytes != null ? "${_qr1ImageBytes!.length} bytes" : "null"}');
      print('  - _activarQR2Recibo: $_activarQR2Recibo');
      print('  - _urlQR2Recibo: "$_urlQR2Recibo"');
      print('  - _qr2ImageBytes: ${_qr2ImageBytes != null ? "${_qr2ImageBytes!.length} bytes" : "null"}');
      
      // Cargar QRs si están activos pero no están cargados
      if (_mostrarQRRecibo) {
        // Cargar QR 1 si está activo
        if (_activarQR1Recibo && _urlQR1Recibo.isNotEmpty) {
          if (_qr1ImageBytes == null) {
            print('⚠️ [IMPRIMIR_RECIBO] QR 1 activo pero no cargado, cargando ahora...');
            await _cargarQRImagenPersonalizado(_urlQR1Recibo, 1);
            // Esperar hasta que se complete la descarga (máximo 5 segundos)
            int intentos = 0;
            while (_qr1ImageBytes == null && intentos < 50 && mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              intentos++;
            }
            if (_qr1ImageBytes != null) {
              print('✅ [IMPRIMIR_RECIBO] QR 1 cargado después de ${intentos * 100}ms');
            } else {
              print('❌ [IMPRIMIR_RECIBO] QR 1 no se pudo cargar después de 5 segundos');
            }
          } else {
            print('✅ [IMPRIMIR_RECIBO] QR 1 ya estaba cargado: ${_qr1ImageBytes!.length} bytes');
          }
        }
        
        // Cargar QR 2 si está activo
        if (_activarQR2Recibo && _urlQR2Recibo.isNotEmpty) {
          if (_qr2ImageBytes == null) {
            print('⚠️ [IMPRIMIR_RECIBO] QR 2 activo pero no cargado, cargando ahora...');
            await _cargarQRImagenPersonalizado(_urlQR2Recibo, 2);
            // Esperar hasta que se complete la descarga (máximo 5 segundos)
            int intentos = 0;
            while (_qr2ImageBytes == null && intentos < 50 && mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              intentos++;
            }
            if (_qr2ImageBytes != null) {
              print('✅ [IMPRIMIR_RECIBO] QR 2 cargado después de ${intentos * 100}ms');
            } else {
              print('❌ [IMPRIMIR_RECIBO] QR 2 no se pudo cargar después de 5 segundos');
            }
          } else {
            print('✅ [IMPRIMIR_RECIBO] QR 2 ya estaba cargado: ${_qr2ImageBytes!.length} bytes');
          }
        }
        
        // Si no hay QRs personalizados activos, cargar el QR por defecto
        if (!_activarQR1Recibo && !_activarQR2Recibo) {
          if (_qrImageBytes == null) {
            print('⚠️ [IMPRIMIR_RECIBO] QR por defecto no cargado, cargando ahora...');
            await _cargarQRImagen();
            // Esperar hasta que se complete la descarga (máximo 5 segundos)
            int intentos = 0;
            while (_qrImageBytes == null && intentos < 50 && mounted) {
              await Future.delayed(const Duration(milliseconds: 100));
              intentos++;
            }
            if (_qrImageBytes != null) {
              print('✅ [IMPRIMIR_RECIBO] QR por defecto cargado después de ${intentos * 100}ms');
            } else {
              print('❌ [IMPRIMIR_RECIBO] QR por defecto no se pudo cargar después de 5 segundos');
            }
          } else {
            print('✅ [IMPRIMIR_RECIBO] QR por defecto ya estaba cargado: ${_qrImageBytes!.length} bytes');
          }
        }
      }
      
      // Cerrar diálogo de carga
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      // Verificar estado después de intentar cargar
      print('🔍 [IMPRIMIR_RECIBO] Estado de QRs después de intentar cargar:');
      print('  - _mostrarQRRecibo: $_mostrarQRRecibo');
      print('  - _activarQR1Recibo: $_activarQR1Recibo');
      print('  - _urlQR1Recibo: "$_urlQR1Recibo"');
      print('  - _qr1ImageBytes: ${_qr1ImageBytes != null ? "${_qr1ImageBytes!.length} bytes" : "null"}');
      print('  - _activarQR2Recibo: $_activarQR2Recibo');
      print('  - _urlQR2Recibo: "$_urlQR2Recibo"');
      print('  - _qr2ImageBytes: ${_qr2ImageBytes != null ? "${_qr2ImageBytes!.length} bytes" : "null"}');
      print('  - _qrImageBytes: ${_qrImageBytes != null ? "${_qrImageBytes!.length} bytes" : "null"}');
      
      // Verificar condiciones para mostrar QRs en PDF
      print('🔍 [IMPRIMIR_RECIBO] Condiciones para mostrar QRs en PDF:');
      print('  - _mostrarQRRecibo es true: $_mostrarQRRecibo');
      print('  - _activarQR1Recibo: $_activarQR1Recibo');
      print('  - _activarQR2Recibo: $_activarQR2Recibo');
      print('  - _qr1ImageBytes: ${_qr1ImageBytes != null ? "${_qr1ImageBytes!.length} bytes" : "null"}');
      print('  - _qr2ImageBytes: ${_qr2ImageBytes != null ? "${_qr2ImageBytes!.length} bytes" : "null"}');
      print('  - _qrImageBytes: ${_qrImageBytes != null ? "${_qrImageBytes!.length} bytes" : "null"}');
      
      if (_activarQR1Recibo) {
        print('  - QR 1 activado: $_activarQR1Recibo');
        print('  - QR 1 tiene imagen: ${_qr1ImageBytes != null}');
        print('  - QR 1 se mostrará: ${_activarQR1Recibo && _qr1ImageBytes != null}');
      }
      if (_activarQR2Recibo) {
        print('  - QR 2 activado: $_activarQR2Recibo');
        print('  - QR 2 tiene imagen: ${_qr2ImageBytes != null}');
        print('  - QR 2 se mostrará: ${_activarQR2Recibo && _qr2ImageBytes != null}');
      }
      if (!_activarQR1Recibo && !_activarQR2Recibo) {
        print('  - QR por defecto se mostrará: ${_qrImageBytes != null}');
      }
      
      // VALIDACIÓN FINAL: Si _mostrarQRRecibo es true pero no hay QRs cargados, mostrar advertencia
      if (_mostrarQRRecibo) {
        final tieneQR1 = _activarQR1Recibo && _qr1ImageBytes != null;
        final tieneQR2 = _activarQR2Recibo && _qr2ImageBytes != null;
        final tieneQRDefault = !_activarQR1Recibo && !_activarQR2Recibo && _qrImageBytes != null;
        
        if (!tieneQR1 && !tieneQR2 && !tieneQRDefault) {
          print('⚠️⚠️⚠️ [IMPRIMIR_RECIBO] ADVERTENCIA: _mostrarQRRecibo es true pero NO hay QRs cargados!');
          print('   Esto significa que los QRs NO aparecerán en el PDF.');
        } else {
          print('✅ [IMPRIMIR_RECIBO] QRs listos para renderizar en PDF');
        }
      }
      
      final pdf = pw.Document();

      // Cargar logo como imagen para PDF
      pw.MemoryImage? logoImage;
      if (_logoBytes != null) {
        try {
          logoImage = pw.MemoryImage(_logoBytes!);
          print('✅ Logo cargado correctamente');
        } catch (e) {
          print('❌ Error creando imagen del logo: $e');
        }
      } else {
        print('⚠️ No hay logo disponible');
      }

      print('📄 Agregando página al PDF...');
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Logo y título
                if (logoImage != null)
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.Image(logoImage, fit: pw.BoxFit.cover),
                  )
                else
                  pw.Container(
                    width: 60,
                    height: 60,
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey300,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        _empresaNombre != null && _empresaNombre!.isNotEmpty
                            ? _empresaNombre![0].toUpperCase()
                            : 'E',
                        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ),
                pw.SizedBox(height: 8),
                // Título de empresa
                pw.Text(
                  _empresaNombre ?? 'Empresa',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 6),
                // Texto de bienvenida
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 20),
                  child: pw.Text(
                    _empresaNombre != null && _empresaNombre!.isNotEmpty
                        ? 'Gracias por preferir a $_empresaNombre la agencia más rápida en envíos a Cuba, en nuestras manos tu paquete llega volando!!'
                        : 'Gracias por preferir nuestros servicios de envío.',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text('RECIBO DE ENVÍO', style: const pw.TextStyle(fontSize: 14)),
                pw.SizedBox(height: 12),
                pw.Divider(),
                pw.SizedBox(height: 12),
                
                // Datos básicos
                _buildPdfRow('Orden', '#${widget.orden.numeroOrden}'),
                pw.SizedBox(height: 8),
                _buildPdfRow('Emisor', _buildEmisorConContactoPdf(widget.orden.emisor)),
                pw.SizedBox(height: 8),
                _buildPdfRow('Destinatario', widget.orden.receptor),
                pw.SizedBox(height: 8),
                _buildPdfRow('Dirección', _buildDireccionCompletaPdf()),
                if (widget.orden.telefonoDestinatario != null && widget.orden.telefonoDestinatario!.isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  _buildPdfRow('Teléfono Destinatario', widget.orden.telefonoDestinatario!),
                ],
                pw.SizedBox(height: 10),
                
                // Desglose de precios
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DESGLOSE DE PRECIOS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Divider(),
                      if (widget.orden.peso != null && widget.orden.peso! > 0) ...[
                        () {
                          final precioReal = _calcularPrecioRealPorLibra();
                          final tieneOferta = _tieneOfertaAplicada();
                          final precioMostrar = precioReal ?? _precioPorLibra ?? 0.0;
                          final totalLibras = precioMostrar * widget.orden.peso!;
                          
                          return pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                '${widget.orden.peso!.toStringAsFixed(0)} LB a \$${precioMostrar.toStringAsFixed(2)} USD${tieneOferta ? ' (Oferta)' : ''}',
                                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                              ),
                              pw.Text(
                                '\$${totalLibras.toStringAsFixed(2)} USD',
                                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                              ),
                            ],
                          );
                        }(),
                        pw.SizedBox(height: 4),
                      ],
                      // Costo de entrega/delivery (solo si NO es recogida en sucursal)
                      if (_costoEnvio != null && _costoEnvio! > 0 && !widget.orden.recogerEnSucursal) ...[
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Entrega / Delivery',
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                            ),
                            pw.Text(
                              '\$${_costoEnvio!.toStringAsFixed(2)} USD',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      // Items adicionales (si existen) - DESPUÉS de entrega, ANTES de remesa
                      if (widget.orden.itemsAdicionales != null && widget.orden.itemsAdicionales!.isNotEmpty) ...[
                        pw.SizedBox(height: 4),
                        ...widget.orden.itemsAdicionales!.map((item) {
                          final nombre = item['nombre']?.toString() ?? 'Item';
                          final tipo = item['tipo']?.toString() ?? '';
                          double precio = 0.0;
                          String descripcion = '';
                          
                          if (tipo == 'LB') {
                            final precioPorLibra = (item['precio_por_libra'] ?? 0.0).toDouble();
                            final peso = (item['peso'] ?? 0.0).toDouble();
                            precio = precioPorLibra * peso;
                            descripcion = '${peso.toStringAsFixed(1)} LB a \$${precioPorLibra.toStringAsFixed(2)} USD';
                          } else if (tipo == 'PRECIO_FIJO') {
                            precio = (item['precio_fijo'] ?? 0.0).toDouble();
                            descripcion = 'Precio fijo';
                          }
                          
                          if (precio > 0) {
                            return pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 4),
                              child: pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Expanded(
                                    child: pw.Text(
                                      '$nombre ($descripcion)',
                                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                                    ),
                                  ),
                                  pw.Text(
                                    '\$${precio.toStringAsFixed(2)} USD',
                                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }
                          return pw.SizedBox.shrink();
                        }).toList(),
                      ],
                      // Remesa (si existe) - DESPUÉS de items adicionales
                      if (widget.orden.tieneRemesa && widget.orden.cantidadRemesa != null && widget.orden.cantidadRemesa! > 0) ...[
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Remesa',
                              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                            ),
                            pw.Text(
                              '\$${widget.orden.cantidadRemesa!.toStringAsFixed(2)} USD',
                              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                            ),
                          ],
                        ),
                        // Fee de remesa (si está configurado)
                        if (_cobrarFeeRemesa) ...[
                          pw.SizedBox(height: 4),
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                _tipoFeeRemesa == 'porcentaje' 
                                    ? 'Fee remesa (${_porcentajeFeeRemesa.toStringAsFixed(1)}%)'
                                    : 'Fee remesa',
                                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                              ),
                              pw.Text(
                                '\$${_calcularFeeRemesa(widget.orden.cantidadRemesa!).toStringAsFixed(2)} USD',
                                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ],
                      pw.Divider(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('PRECIO TOTAL:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                          pw.Text('\$${_calcularTotalRecibo().toStringAsFixed(2)} ${widget.orden.moneda}', 
                            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.orange)),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                
                // Información de remesa (si aplica)
                if (widget.orden.tieneRemesa) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.orange, width: 1),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Remesa Enviada',
                          style: pw.TextStyle(
                            fontSize: 11.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.orange,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'El cliente envió ${widget.orden.cantidadRemesa != null ? '\$${widget.orden.cantidadRemesa!.toStringAsFixed(2)} USD' : 'una cantidad no especificada'} a ${widget.orden.receptor}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
                
                // Pago contra entrega (si aplica)
                if (widget.orden.requierePago && !widget.orden.pagado) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.red50,
                      border: pw.Border.all(color: PdfColors.red, width: 1.5),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '⚠️ PAGO CONTRA ENTREGA',
                          style: pw.TextStyle(
                            fontSize: 11.5,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.red,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'IMPORTANTE: El destinatario debe pagar al recibir la orden',
                          style: pw.TextStyle(
                            fontSize: 10.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 5),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.red,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'MONTO A COBRAR:',
                                style: pw.TextStyle(
                                  fontSize: 11,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                ),
                              ),
                              pw.Text(
                                '\$${widget.orden.montoCobrar.toStringAsFixed(2)} ${widget.orden.moneda}',
                                style: pw.TextStyle(
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.orden.notasPago != null && widget.orden.notasPago!.isNotEmpty) ...[
                          pw.SizedBox(height: 5),
                          pw.Text(
                            'Nota: ${widget.orden.notasPago}',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
                
                // Datos de contacto
                pw.Divider(),
                pw.SizedBox(height: 6), // Reducido de 8 a 6
                pw.Text('Datos de Contacto', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4), // Reducido de 6 a 4
                if (_empresaNombre != null && _empresaNombre!.isNotEmpty)
                  _buildPdfRow('Empresa', _empresaNombre!),
                if (_empresaDireccion != null && _empresaDireccion!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _buildPdfRow('Dirección', _empresaDireccion!),
                ],
                if (_empresaTelefono != null && _empresaTelefono!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _buildPdfRow('Teléfono', _empresaTelefono!),
                ],
                if (_empresaEmail != null && _empresaEmail!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _buildPdfRow('Email', _empresaEmail!),
                ],
                if (_empresaSitioWeb != null && _empresaSitioWeb!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _buildPdfRow('Sitio Web', _empresaSitioWeb!),
                ],
                pw.SizedBox(height: 6), // Reducido de 10 a 6 para dejar más espacio a QRs
                
                // Texto promocional personalizado (si está activo) - REDUCIDO para dejar espacio a QRs
                if (_mostrarTextoPromocionalRecibo && _textoPromocionalRecibo.isNotEmpty) ...[
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      _textoPromocionalRecibo,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 8.5, // Reducido de 9.5 a 8.5
                        color: PdfColors.grey700,
                        height: 1.2, // Reducido de 1.4 a 1.2 para más compacto
                      ),
                      maxLines: 4, // Limitar a 4 líneas máximo
                    ),
                  ),
                  pw.SizedBox(height: 6), // Reducido de 10 a 6
                ],
                
                // QR Codes personalizados (si están activos)
                if (_mostrarQRRecibo) ...[
                  pw.SizedBox(height: 4), // Espaciado mínimo antes de QRs
                  pw.Center(
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        // QR 1 - Tamaño reducido para asegurar que quepa en la página
                        if (_activarQR1Recibo && _qr1ImageBytes != null)
                          pw.Container(
                            margin: (_activarQR2Recibo && _qr2ImageBytes != null) 
                                ? pw.EdgeInsets.only(right: 8)
                                : pw.EdgeInsets.only(right: 0),
                            child: pw.Column(
                              mainAxisSize: pw.MainAxisSize.min,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Container(
                                  width: 70, // Reducido de 80 a 70
                                  height: 70, // Reducido de 80 a 70
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(color: PdfColors.grey400, width: 1),
                                    borderRadius: pw.BorderRadius.circular(4),
                                    color: PdfColors.white,
                                  ),
                                  child: pw.Image(
                                    pw.MemoryImage(_qr1ImageBytes!),
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                                pw.SizedBox(height: 2), // Reducido de 4 a 2
                                pw.Text(
                                  _textoQR1Recibo.isNotEmpty ? _textoQR1Recibo : 'Escanea para descargar',
                                  style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic), // Reducido de 8 a 7
                                  textAlign: pw.TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        // QR 2 - Tamaño reducido para asegurar que quepa en la página
                        if (_activarQR2Recibo && _qr2ImageBytes != null)
                          pw.Container(
                            child: pw.Column(
                              mainAxisSize: pw.MainAxisSize.min,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Container(
                                  width: 70, // Reducido de 80 a 70
                                  height: 70, // Reducido de 80 a 70
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(color: PdfColors.grey400, width: 1),
                                    borderRadius: pw.BorderRadius.circular(4),
                                    color: PdfColors.white,
                                  ),
                                  child: pw.Image(
                                    pw.MemoryImage(_qr2ImageBytes!),
                                    fit: pw.BoxFit.contain,
                                  ),
                                ),
                                pw.SizedBox(height: 2), // Reducido de 4 a 2
                                pw.Text(
                                  _textoQR2Recibo.isNotEmpty ? _textoQR2Recibo : 'Escanea para descargar',
                                  style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic), // Reducido de 8 a 7
                                  textAlign: pw.TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        // QR por defecto (si no hay QRs personalizados activos) - Tamaño reducido
                        if (!_activarQR1Recibo && !_activarQR2Recibo && _qrImageBytes != null)
                          pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Container(
                                width: 70, // Reducido de 80 a 70
                                height: 70, // Reducido de 80 a 70
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: PdfColors.grey400, width: 1),
                                  borderRadius: pw.BorderRadius.circular(4),
                                  color: PdfColors.white,
                                ),
                                child: pw.Image(
                                  pw.MemoryImage(_qrImageBytes!),
                                  fit: pw.BoxFit.contain,
                                ),
                              ),
                              pw.SizedBox(height: 2), // Reducido de 4 a 2
                              pw.Text(
                                'Escanea para descargar',
                                style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic), // Reducido de 8 a 7
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ),
                        // Mensaje de debug si no hay QRs disponibles
                        if (_mostrarQRRecibo && 
                            ((_activarQR1Recibo && _qr1ImageBytes == null) || 
                             (_activarQR2Recibo && _qr2ImageBytes == null) ||
                             (!_activarQR1Recibo && !_activarQR2Recibo && _qrImageBytes == null)))
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: pw.BoxDecoration(
                              color: PdfColors.yellow100,
                              border: pw.Border.all(color: PdfColors.orange, width: 1),
                              borderRadius: pw.BorderRadius.circular(4),
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
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );

      print('💾 Guardando PDF...');
      final pdfBytes = await pdf.save();
      print('✅ PDF generado correctamente (${pdfBytes.length} bytes)');

      print('🖨️ Abriendo diálogo de impresión...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );

      print('✅ PDF enviado a impresión');
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recibo enviado a impresión'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e, stackTrace) {
      print('❌ ERROR AL GENERAR PDF: $e');
      print('Stack trace: $stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al imprimir: $e'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  pw.Widget _buildPdfRow(String label, String value) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 10.5,
              color: PdfColors.black,
            ),
          ),
        ),
      ],
    );
  }
  
  // Cargar email y teléfono del emisor desde la BD
  Future<void> _cargarDatosEmisor() async {
    try {
      if (widget.orden.emisor.isEmpty || widget.orden.emisor == 'Sin emisor') {
        return;
      }
      
      final emisorData = await supabase
          .from('emisores')
          .select('email, telefono')
          .eq('nombre', widget.orden.emisor)
          .eq('tenant_id', widget.orden.tenantId ?? '')
          .maybeSingle();
      
      if (emisorData != null) {
        setState(() {
          _emisorEmail = emisorData['email']?.toString();
          _emisorTelefono = emisorData['telefono']?.toString();
        });
        print('✅ Datos del emisor cargados: email=$_emisorEmail, teléfono=$_emisorTelefono');
      }
    } catch (e) {
      print('❌ Error cargando datos del emisor: $e');
    }
  }
  
  // Construir emisor con email y teléfono
  Widget _buildEmisorConContacto(String nombreEmisor) {
    final List<Widget> children = [
      Text(
        nombreEmisor,
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    ];
    
    if (_emisorTelefono != null && _emisorTelefono!.isNotEmpty) {
      children.add(
        Text(
          ' | Tel: $_emisorTelefono',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      );
    }
    
    if (_emisorEmail != null && _emisorEmail!.isNotEmpty) {
      children.add(
        Text(
          ' | Email: $_emisorEmail',
          style: TextStyle(
            fontSize: 10,
            color: Colors.white.withOpacity(0.7),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
  
  // Construir dirección completa con municipio y provincia
  Widget _buildDireccionCompleta() {
    final List<String> partes = [widget.orden.direccionDestino];
    
    if (widget.orden.municipioDestino != null && widget.orden.municipioDestino!.isNotEmpty) {
      partes.add(widget.orden.municipioDestino!);
    }
    
    if (widget.orden.provinciaDestino != null && widget.orden.provinciaDestino!.isNotEmpty) {
      partes.add(widget.orden.provinciaDestino!);
    }
    
    return Text(
      partes.join(', '),
      style: TextStyle(
        fontSize: 11,
        color: Colors.white.withOpacity(0.8),
      ),
    );
  }
  
  // Construir emisor con email y teléfono para PDF
  String _buildEmisorConContactoPdf(String nombreEmisor) {
    final List<String> partes = [nombreEmisor];
    
    if (_emisorTelefono != null && _emisorTelefono!.isNotEmpty) {
      partes.add('Tel: $_emisorTelefono');
    }
    
    if (_emisorEmail != null && _emisorEmail!.isNotEmpty) {
      partes.add('Email: $_emisorEmail');
    }
    
    return partes.join(' | ');
  }
  
  // Construir dirección completa con municipio y provincia para PDF
  String _buildDireccionCompletaPdf() {
    final List<String> partes = [widget.orden.direccionDestino];
    
    if (widget.orden.municipioDestino != null && widget.orden.municipioDestino!.isNotEmpty) {
      partes.add(widget.orden.municipioDestino!);
    }
    
    if (widget.orden.provinciaDestino != null && widget.orden.provinciaDestino!.isNotEmpty) {
      partes.add(widget.orden.provinciaDestino!);
    }
    
    return partes.join(', ');
  }
}

