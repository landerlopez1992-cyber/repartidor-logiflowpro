import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/entrega_progreso.dart';
import '../models/orden.dart';

/// Progreso de entrega por orden (persistente, offline-first).
class EntregaProgresoService {
  static const String _storageKey = 'entrega_progreso_por_orden_v1';

  static Future<Map<String, dynamic>> _leerMapa() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      print('⚠️ entrega_progreso: error leyendo mapa: $e');
    }
    return {};
  }

  static Future<void> _guardarMapa(Map<String, dynamic> mapa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(mapa));
  }

  static Future<EntregaProgreso?> cargar(String ordenId) async {
    if (ordenId.isEmpty) return null;
    final mapa = await _leerMapa();
    final entry = mapa[ordenId];
    if (entry is! Map) return null;
    try {
      final m = Map<String, dynamic>.from(entry as Map);
      return EntregaProgreso.fromJson(m);
    } catch (e) {
      print('⚠️ entrega_progreso: parse orden $ordenId: $e');
      return null;
    }
  }

  static Future<EntregaProgreso> cargarOMaterializar(String ordenId) async {
    return (await cargar(ordenId)) ?? EntregaProgreso.vacio(ordenId);
  }

  static Future<void> guardar(EntregaProgreso progreso) async {
    if (progreso.ordenId.isEmpty) return;
    final mapa = await _leerMapa();
    mapa[progreso.ordenId] = progreso.toJson();
    await _guardarMapa(mapa);
    print('💾 Progreso entrega guardado: ${progreso.ordenId}');
  }

  static Future<void> marcarPaso(
    String ordenId,
    EntregaPaso paso, {
    String? etiquetaMonto,
  }) async {
    var p = await cargarOMaterializar(ordenId);
    final now = DateTime.now().toUtc();
    switch (paso) {
      case EntregaPaso.cobro:
        p = p.copyWith(
          cobroConfirmado: true,
          cobroAt: now,
          cobroMontoEtiqueta: etiquetaMonto,
          updatedAt: now,
        );
        break;
      case EntregaPaso.remesa:
        p = p.copyWith(
          remesaConfirmada: true,
          remesaAt: now,
          remesaMontoEtiqueta: etiquetaMonto,
          updatedAt: now,
        );
        break;
      case EntregaPaso.foto:
        p = p.copyWith(fotoConfirmada: true, fotoAt: now, updatedAt: now);
        break;
      case EntregaPaso.firma:
        p = p.copyWith(firmaConfirmada: true, firmaAt: now, updatedAt: now);
        break;
      case EntregaPaso.bultos:
        p = p.copyWith(bultosConfirmados: true, bultosAt: now, updatedAt: now);
        break;
    }
    await guardar(p);
  }

  static Future<void> limpiar(String ordenId) async {
    if (ordenId.isEmpty) return;
    final mapa = await _leerMapa();
    mapa.remove(ordenId);
    await _guardarMapa(mapa);
  }

  static Future<void> limpiarTodo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Alinea progreso local con datos ya en caché/orden (tras reinicio).
  static EntregaProgreso sincronizarConOrden({
    required EntregaProgreso base,
    required Orden orden,
    required bool tieneFoto,
    String? firmaUrl,
  }) {
    var p = base;
    final now = DateTime.now().toUtc();

    if (orden.requierePago && orden.pagado && !p.cobroConfirmado) {
      final simbolo = orden.moneda == 'USD' ? '\$' : '\$';
      p = p.copyWith(
        cobroConfirmado: true,
        cobroAt: orden.fechaPago ?? now,
        cobroMontoEtiqueta:
            '$simbolo${orden.montoCobrar.toStringAsFixed(2)} ${orden.moneda}',
        updatedAt: now,
      );
    }

    if (tieneFoto && !p.fotoConfirmada) {
      p = p.copyWith(fotoConfirmada: true, fotoAt: now, updatedAt: now);
    }

    final firma = firmaUrl ?? orden.firmaUrl;
    if (firma != null && firma.isNotEmpty && !p.firmaConfirmada) {
      p = p.copyWith(firmaConfirmada: true, firmaAt: now, updatedAt: now);
    }

    return p;
  }

  static List<EntregaPaso> pasosRequeridosParaOrden({
    required Orden orden,
    required bool fotoObligatoria,
    required bool exigeFirma,
    required bool exigeFoto,
  }) {
    final pasos = <EntregaPaso>[];
    if (orden.requierePago && !orden.pagado) {
      pasos.add(EntregaPaso.cobro);
    }
    if (orden.tieneRemesa) {
      pasos.add(EntregaPaso.remesa);
    }
    if (exigeFoto && fotoObligatoria) {
      pasos.add(EntregaPaso.foto);
    }
    if (exigeFirma) {
      pasos.add(EntregaPaso.firma);
    }
    if (orden.cantidadBultos > 1) {
      pasos.add(EntregaPaso.bultos);
    }
    return pasos;
  }

  static EntregaPaso? siguientePasoPendiente({
    required EntregaProgreso progreso,
    required List<EntregaPaso> requeridos,
  }) {
    for (final paso in requeridos) {
      if (!progreso.pasoCompleto(paso)) return paso;
    }
    return null;
  }
}
