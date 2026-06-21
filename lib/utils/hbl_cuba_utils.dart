import 'dart:math' show max;

import '../data/codigos_cuba_cubatrans.dart';

/// Código HBL de 14 caracteres (Anexo 6 / reglamento TRANSCARGO):
/// [3 letras corresponsal] + [4 dígitos provincia/municipio] + [7 dígitos consecutivo]
String buildHbl14Caracteres({
  required String codigoCorresponsal,
  required String? provinciaDestino,
  required String? municipioDestino,
  required String numeroOrden,
}) {
  var corr = codigoCorresponsal.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (corr.length < 3) {
    corr = '${corr}XXX'.substring(0, 3);
  } else {
    corr = corr.substring(0, 3);
  }

  final codigoMunicipio = CodigosCubaCubatrans.getCodigoSafe(
    provinciaDestino,
    municipioDestino,
  );

  final rawNum = numeroOrden.replaceAll(RegExp(r'[^0-9]'), '');
  final consecutivo = rawNum.isEmpty
      ? '0000001'
      : rawNum.padLeft(7, '0').substring(max(0, rawNum.length - 7));

  return '$corr$codigoMunicipio$consecutivo';
}

/// Texto para Code-93 en etiqueta: HBL + '-' + número de bulto.
String buildHblBarcodeData(String hbl14, int bultoNum) => '$hbl14-$bultoNum';
