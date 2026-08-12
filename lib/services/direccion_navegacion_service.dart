import 'dart:io' show Platform;

import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/orden.dart';
import '../utils/orden_recogida_colaborador_ui.dart';
import 'paises_service.dart';

/// Resultado de armar la dirección postal para navegación (Google Maps, geocoding).
class DireccionNavegacionResultado {
  /// Texto completo para mostrar al repartidor (incluye calle escrita a mano).
  final String direccionCompleta;

  /// Query preferida para mapa/GPS (poblado/municipio/provincia; calle al final).
  final String direccionMapa;

  /// Candidatos en orden: 1 poblado → 2 municipio → 3 provincia → 4 calle.
  final List<String> candidatosMapa;

  final String tipoDestino;

  /// Provincia elegida en la orden (para descartar geocodes de otro estado).
  final String? provinciaEsperada;

  /// Municipio elegido (ayuda a filtrar resultados ambiguos).
  final String? municipioEsperado;

  const DireccionNavegacionResultado({
    required this.direccionCompleta,
    required this.direccionMapa,
    required this.candidatosMapa,
    required this.tipoDestino,
    this.provinciaEsperada,
    this.municipioEsperado,
  });

  bool get esValida {
    final t = direccionCompleta.trim();
    return t.isNotEmpty &&
        t.toLowerCase() != 'dirección no especificada' &&
        t.toLowerCase() != 'direccion no especificada';
  }

  bool get tieneMapa {
    return direccionMapa.trim().isNotEmpty &&
        direccionMapa.toLowerCase() != 'dirección no especificada';
  }
}

/// Construye direcciones completas y abre Google Maps sin errores por campos incompletos.
///
/// Prioridad GPS (obligatoria):
/// 1) poblado (Real Campiña)  2) municipio  3) provincia  4) calle escrita (último).
/// Así se evita que Google mande a otro estado por una calle homónima
/// (ej. «Calle 22 Calisto» → Matanzas en vez de Cienfuegos).
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

  static String _unirPartes(List<String?> valores) {
    final partes = <String>[];
    for (final v in valores) {
      _agregarParte(partes, v);
    }
    return partes.join(', ');
  }

  /// Deduplica candidatos preservando el orden.
  static List<String> _unicos(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final s in raw) {
      final t = s.trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(t);
    }
    return out;
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
    final pais =
        _esVacio(paisOperacion) ? null : _normalizarPais(paisOperacion!);

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
    final completa =
        partes.isEmpty ? 'Dirección no especificada' : partes.join(', ');
    return DireccionNavegacionResultado(
      direccionCompleta: completa,
      direccionMapa: completa,
      candidatosMapa: completa == 'Dirección no especificada' ? const [] : [completa],
      tipoDestino: tipo,
    );
  }

  static DireccionNavegacionResultado _desdeCamposOrden(
    Orden orden,
    String? pais, {
    required String tipo,
  }) {
    final calle = orden.direccionDestino;
    final poblado = orden.consejoPopularBatey; // Real Campiña, etc.
    final municipio = orden.municipioDestino;
    final provincia = !_esVacio(orden.provinciaDestino)
        ? orden.provinciaDestino
        : orden.ciudadDestino;

    String? paisEff = pais;
    final preview = _unirPartes([calle, poblado, municipio, provincia]);
    if (preview.isNotEmpty &&
        !_contieneAlgunPais(preview) &&
        paisEff == null) {
      // sin país conocido
    }

    // Pantalla del repartidor: calle + desplegables (siempre completa).
    final display = _unirPartes([calle, poblado, municipio, provincia, paisEff]);

    // Orden obligatorio GPS (evita «Calle 22 Calisto» → Matanzas u otro estado):
    // 1) poblado  2) municipio  3) provincia  4) calle escrita (último).
    final conPoblado = _unirPartes([poblado, municipio, provincia, paisEff]);
    final pobladoProv = _unirPartes([poblado, provincia, paisEff]);
    final conMunicipio = _unirPartes([municipio, provincia, paisEff]);
    final soloProvincia = _unirPartes([provincia, paisEff]);
    // Calle al final, pero SIEMPRE anclada a municipio/provincia/país
    // para que Google no “adivine” otro estado.
    final conCalle = _unirPartes([calle, poblado, municipio, provincia, paisEff]);

    final candidatos = _unicos([
      conPoblado,
      pobladoProv,
      conMunicipio,
      soloProvincia,
      conCalle, // último recurso
    ]);

    final mapa = candidatos.isNotEmpty
        ? candidatos.first
        : (display.isEmpty ? 'Dirección no especificada' : display);

    return DireccionNavegacionResultado(
      direccionCompleta:
          display.isEmpty ? 'Dirección no especificada' : display,
      direccionMapa: mapa.isEmpty ? 'Dirección no especificada' : mapa,
      candidatosMapa: candidatos,
      tipoDestino: tipo,
      provinciaEsperada: provincia?.trim(),
      municipioEsperado: municipio?.trim(),
    );
  }

  /// True si el placemark coincide con provincia elegida en la orden.
  /// Si el reverse no trae datos útiles, no rechaza (evita dejar la orden sin pin).
  static bool _coincideZonaEsperada(
    Placemark place, {
    String? provinciaEsperada,
    String? municipioEsperado,
  }) {
    final hayProv = !_esVacio(provinciaEsperada);
    if (!hayProv) return true;

    final blob = [
      place.administrativeArea,
      place.subAdministrativeArea,
      place.locality,
      place.subLocality,
      place.name,
      place.thoroughfare,
    ].whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');

    // Reverse vacío / genérico: no descartar (señal mala o platform sin datos).
    if (blob.isEmpty) return true;

    final p = provinciaEsperada!.trim().toLowerCase();
    final lower = blob.toLowerCase();
    if (_textoContiene(lower, p)) return true;

    // Variantes cortas: "Cienfuegos" vs "Provincia de Cienfuegos".
    final tokens = p.split(RegExp(r'\s+')).where((t) => t.length >= 4);
    if (tokens.any((t) => lower.contains(t))) return true;

    // Si el reverse nombra OTRA provincia cubana conocida, sí rechazar.
    const provinciasCu = [
      'pinar del río',
      'pinar del rio',
      'artemisa',
      'la habana',
      'habana',
      'mayabeque',
      'matanzas',
      'villa clara',
      'cienfuegos',
      'sancti spíritus',
      'sancti spiritus',
      'ciego de ávila',
      'ciego de avila',
      'camagüey',
      'camaguey',
      'las tunas',
      'holguín',
      'holguin',
      'granma',
      'santiago de cuba',
      'guantánamo',
      'guantanamo',
      'isla de la juventud',
    ];
    for (final otra in provinciasCu) {
      if (otra == p || p.contains(otra) || otra.contains(p)) continue;
      if (lower.contains(otra)) return false;
    }
    // No está claro → aceptar (mejor pin en zona aproximada que ningún pin).
    return true;
  }

  /// Geocodifica: poblado → municipio → provincia → calle (última).
  /// Tolera señal mala: timeouts cortos, no bloquea si reverse falla.
  static Future<({double lat, double lon, String queryUsada})?>
      geocodificarConFallback(
    DireccionNavegacionResultado res, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final queries = res.candidatosMapa.isNotEmpty
        ? res.candidatosMapa
        : (res.tieneMapa ? [res.direccionMapa] : <String>[]);
    if (queries.isEmpty) return null;

    // Tope global: no colgar la UI con N candidatos × reverse en red mala.
    final deadline = DateTime.now().add(const Duration(seconds: 12));

    for (final q in queries) {
      if (DateTime.now().isAfter(deadline)) break;
      try {
        print('📍 Geocode intento: $q');
        final locations = await locationFromAddress(q).timeout(timeout);
        if (locations.isEmpty) continue;

        for (final loc in locations.take(2)) {
          var aceptado = true;
          final queryYaAnclaProvincia = !_esVacio(res.provinciaEsperada) &&
              _textoContiene(q, res.provinciaEsperada!);

          if (!_esVacio(res.provinciaEsperada) && !queryYaAnclaProvincia) {
            try {
              final marks = await placemarkFromCoordinates(
                loc.latitude,
                loc.longitude,
              ).timeout(const Duration(seconds: 3));
              if (marks.isNotEmpty) {
                aceptado = _coincideZonaEsperada(
                  marks.first,
                  provinciaEsperada: res.provinciaEsperada,
                  municipioEsperado: res.municipioEsperado,
                );
                if (!aceptado) {
                  print(
                    '🚫 Geocode descartado (fuera de ${res.provinciaEsperada}): '
                    '${loc.latitude}, ${loc.longitude} ← "$q"',
                  );
                }
              }
            } catch (_) {
              // Sin reverse: aceptar si la query lleva municipio/poblado.
              aceptado = true;
            }
          }

          if (!aceptado) continue;

          print(
            '✅ Geocode OK ($q) → ${loc.latitude}, ${loc.longitude}',
          );
          return (
            lat: loc.latitude,
            lon: loc.longitude,
            queryUsada: q,
          );
        }
      } catch (e) {
        print('⚠️ Geocode falló ($q): $e');
      }
    }
    return null;
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

      // Preferir query de mapa (sin calle confusa en Cuba).
      // Si no hay texto útil, usar coordenadas ya guardadas.
      String destino;
      if (res.tieneMapa) {
        destino = res.direccionMapa;
        print(
          '🗺️ Navegación (${res.tipoDestino}) mapa="$destino" '
          '(display="${res.direccionCompleta}")',
        );
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
