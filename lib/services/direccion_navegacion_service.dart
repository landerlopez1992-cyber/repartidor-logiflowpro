import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/orden.dart';
import '../utils/orden_recogida_colaborador_ui.dart';
import 'paises_service.dart';

/// Resultado de armar la dirección postal para navegación (Google Maps, geocoding).
class DireccionNavegacionResultado {
  final String direccionCompleta;
  final String tipoDestino;

  const DireccionNavegacionResultado({
    required this.direccionCompleta,
    required this.tipoDestino,
  });

  bool get esValida {
    final t = direccionCompleta.trim();
    return t.isNotEmpty &&
        t.toLowerCase() != 'dirección no especificada' &&
        t.toLowerCase() != 'direccion no especificada';
  }
}

/// Construye direcciones completas y abre Google Maps sin errores por campos incompletos.
class DireccionNavegacionService {
  DireccionNavegacionService._();

  static bool _esVacio(String? v) {
    if (v == null) return true;
    final t = v.trim();
    return t.isEmpty || t.toUpperCase() == 'N/A';
  }

  static bool _textoContiene(String haystack, String needle) {
    return haystack.toLowerCase().contains(needle.trim().toLowerCase());
  }

  static bool _contieneAlgunPais(String texto) {
    const claves = [
      'cuba',
      'usa',
      'united states',
      'estados unidos',
      'méxico',
      'mexico',
      'canada',
      'canadá',
      'españa',
      'spain',
      'colombia',
      'venezuela',
      'republica dominicana',
      'república dominicana',
      'puerto rico',
    ];
    final lower = texto.toLowerCase();
    return claves.any((k) => lower.contains(k));
  }

  static String _normalizarPais(String pais) {
    final p = pais.trim();
    if (p.length == 2) {
      switch (p.toUpperCase()) {
        case 'CU':
          return 'Cuba';
        case 'US':
          return 'Estados Unidos';
        case 'MX':
          return 'México';
        case 'ES':
          return 'España';
        default:
          return p;
      }
    }
    return p;
  }

  static void _agregarParte(List<String> partes, String? valor) {
    if (_esVacio(valor)) return;
    final v = valor!.trim();
    final unido = partes.join(', ');
    if (unido.isNotEmpty && _textoContiene(unido, v)) return;
    partes.add(v);
  }

  static bool _navegarASucursal(Orden orden) {
    if (!orden.recogerEnSucursal) return false;
    final e = orden.estado.trim().toUpperCase();
    return e == 'POR ENVIAR' ||
        e == 'LISTO PARA RECOGER' ||
        e == 'ENTREGADO EN SUCURSAL';
  }

  static bool _navegarAColaborador(Orden orden) {
    return OrdenRecogidaColaboradorUi.esRecogidaColaborador(orden) &&
        OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(orden);
  }

  static DireccionNavegacionResultado resolver({
    required Orden orden,
    Map<String, dynamic>? sucursal,
    String? paisOperacion,
  }) {
    final pais = _esVacio(paisOperacion) ? null : _normalizarPais(paisOperacion!);

    if (_navegarASucursal(orden) && sucursal != null && sucursal.isNotEmpty) {
      return _desdeSucursal(sucursal, pais, tipo: 'sucursal');
    }

    if (_navegarAColaborador(orden)) {
      return _desdeCamposOrden(orden, pais, tipo: 'colaborador');
    }

    if ((orden.tipoOrden ?? '').toUpperCase() == 'RECOGIDA') {
      return _desdeCamposOrden(orden, pais, tipo: 'recogida_cliente');
    }

    if (orden.recogerEnSucursal && sucursal != null && sucursal.isNotEmpty) {
      return _desdeSucursal(sucursal, pais, tipo: 'sucursal');
    }

    return _desdeCamposOrden(orden, pais, tipo: 'destinatario');
  }

  static DireccionNavegacionResultado _desdeSucursal(
    Map<String, dynamic> sucursal,
    String? pais, {
    required String tipo,
  }) {
    final partes = <String>[];
    _agregarParte(partes, sucursal['direccion']?.toString());
    _agregarParte(partes, sucursal['municipio']?.toString());
    _agregarParte(partes, sucursal['provincia']?.toString());
    final paisSuc = sucursal['pais']?.toString();
    if (!_esVacio(paisSuc)) {
      _agregarParte(partes, _normalizarPais(paisSuc!));
    } else if (pais != null) {
      _agregarParte(partes, pais);
    }
    return DireccionNavegacionResultado(
      direccionCompleta: partes.isEmpty ? 'Dirección no especificada' : partes.join(', '),
      tipoDestino: tipo,
    );
  }

  static DireccionNavegacionResultado _desdeCamposOrden(
    Orden orden,
    String? pais, {
    required String tipo,
  }) {
    final partes = <String>[];

    _agregarParte(partes, orden.direccionDestino);
    _agregarParte(partes, orden.consejoPopularBatey);

    if (!_esVacio(orden.municipioDestino)) {
      _agregarParte(partes, orden.municipioDestino);
    }

    if (!_esVacio(orden.provinciaDestino)) {
      _agregarParte(partes, orden.provinciaDestino);
    } else if (!_esVacio(orden.ciudadDestino)) {
      _agregarParte(partes, orden.ciudadDestino);
    }

    final sinPais = partes.join(', ');
    if (sinPais.isNotEmpty && !_contieneAlgunPais(sinPais) && pais != null) {
      _agregarParte(partes, pais);
    }

    return DireccionNavegacionResultado(
      direccionCompleta: partes.isEmpty ? 'Dirección no especificada' : partes.join(', '),
      tipoDestino: tipo,
    );
  }

  static Future<Map<String, dynamic>?> cargarSucursalOrden(Orden orden) async {
    if (!orden.recogerEnSucursal) return null;
    if (orden.sucursalId == null || orden.sucursalId!.isEmpty) return null;

    try {
      final row = await supabase
          .from('sucursales')
          .select('nombre, direccion, municipio, provincia, pais, es_principal')
          .eq('id', orden.sucursalId!)
          .maybeSingle();
      return row;
    } catch (e) {
      print('⚠️ Error cargando sucursal para navegación: $e');
      return null;
    }
  }

  static Future<String?> _paisParaOrden(Orden orden) async {
    if (orden.tenantId != null) {
      final p = await PaisesService.obtenerPaisOperacion(orden.tenantId!);
      if (!_esVacio(p)) return _normalizarPais(p!);
    }
    final actual = await PaisesService.obtenerPaisOperacionActual();
    if (!_esVacio(actual)) return _normalizarPais(actual!);
    return null;
  }

  static Future<bool> abrirDestinoEnGoogleMaps({
    required Orden orden,
    Map<String, dynamic>? sucursal,
    String? paisOperacion,
    double? latitudFallback,
    double? longitudFallback,
  }) async {
    try {
      final pais = _esVacio(paisOperacion)
          ? await _paisParaOrden(orden)
          : _normalizarPais(paisOperacion!);

      Map<String, dynamic>? suc = sucursal;
      if (suc == null && orden.recogerEnSucursal) {
        suc = await cargarSucursalOrden(orden);
      }

      final res = resolver(
        orden: orden,
        sucursal: suc,
        paisOperacion: pais,
      );

      String destino;
      if (res.esValida) {
        destino = res.direccionCompleta;
        print('🗺️ Navegación (${res.tipoDestino}): $destino');
      } else if (latitudFallback != null && longitudFallback != null) {
        destino = '$latitudFallback,$longitudFallback';
        print('🗺️ Navegación (coordenadas): $destino');
      } else {
        return false;
      }

      return _lanzarMapaExterno(destino);
    } catch (e) {
      print('❌ abrirDestinoEnGoogleMaps: $e');
      return false;
    }
  }

  /// Intenta abrir mapa sin depender de [canLaunchUrl] (falla en Android 11+ sin queries).
  static Future<bool> _lanzarMapaExterno(String destino) async {
    final q = Uri.encodeQueryComponent(destino);
    final uris = <Uri>[];

    if (Platform.isIOS) {
      uris.add(Uri.parse('comgooglemaps://?q=$q&directionsmode=driving'));
      uris.add(Uri.parse('maps://?q=$q'));
      uris.add(Uri.parse('https://maps.apple.com/?q=$q'));
    } else {
      uris.add(Uri.parse('google.navigation:q=$q'));
      uris.add(Uri.parse('comgooglemaps://?q=$q&directionsmode=driving'));
      uris.add(
        Uri.parse(
          'intent://maps.google.com/maps?q=$q#Intent;scheme=https;package=com.google.android.apps.maps;end',
        ),
      );
    }

    uris.add(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
    );
    uris.add(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': destino,
        'travelmode': 'driving',
      }),
    );
    uris.add(Uri.parse('geo:0,0?q=$q'));

    for (final uri in uris) {
      try {
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) {
          print('✅ Mapa abierto con: $uri');
          return true;
        }
      } catch (e) {
        print('⚠️ launchUrl falló ($uri): $e');
      }
    }

    return false;
  }

  static Future<DireccionNavegacionResultado> resolverConPaisOrden(
    Orden orden, {
    Map<String, dynamic>? sucursal,
  }) async {
    final pais = await _paisParaOrden(orden);
    Map<String, dynamic>? suc = sucursal;
    if (suc == null && orden.recogerEnSucursal) {
      suc = await cargarSucursalOrden(orden);
    }
    return resolver(orden: orden, sucursal: suc, paisOperacion: pais);
  }
}
