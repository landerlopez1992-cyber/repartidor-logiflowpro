import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Servicio para cachear datos del perfil del repartidor localmente
/// Permite trabajar offline y sincronizar cuando hay conexión
class RepartidorPerfilCacheService {
  static const String _cacheKey = 'cached_repartidor_perfil';
  static const String _estadisticasKey = 'cached_repartidor_estadisticas';
  static const String _saldoKey = 'cached_repartidor_saldo';
  static const String _historialPagosKey = 'cached_repartidor_historial_pagos';

  /// Guardar datos del perfil en caché
  static Future<void> cachePerfilData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode(data));
      print('💾 Datos de perfil guardados en caché');
    } catch (e) {
      print('❌ Error guardando perfil en caché: $e');
    }
  }

  /// Obtener datos del perfil desde caché
  static Future<Map<String, dynamic>?> getCachedPerfilData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString(_cacheKey);
      
      if (dataString == null || dataString.isEmpty) {
        return null;
      }
      
      return jsonDecode(dataString) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error cargando perfil desde caché: $e');
      return null;
    }
  }

  /// Guardar estadísticas en caché
  static Future<void> cacheEstadisticas(Map<String, dynamic> estadisticas) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_estadisticasKey, jsonEncode(estadisticas));
      print('💾 Estadísticas guardadas en caché');
    } catch (e) {
      print('❌ Error guardando estadísticas en caché: $e');
    }
  }

  /// Obtener estadísticas desde caché
  static Future<Map<String, dynamic>?> getCachedEstadisticas() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString(_estadisticasKey);
      
      if (dataString == null || dataString.isEmpty) {
        return null;
      }
      
      return jsonDecode(dataString) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error cargando estadísticas desde caché: $e');
      return null;
    }
  }

  /// Guardar saldo en caché
  static Future<void> cacheSaldo(
    double saldo,
    String moneda, {
    bool solicitudPendiente = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_saldoKey, jsonEncode({
        'saldo': saldo,
        'moneda': moneda,
        'solicitud_pendiente': solicitudPendiente,
      }));
      print('💾 Saldo guardado en caché: \$$saldo $moneda');
    } catch (e) {
      print('❌ Error guardando saldo en caché: $e');
    }
  }

  /// Obtener saldo desde caché
  static Future<Map<String, dynamic>?> getCachedSaldo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString(_saldoKey);
      
      if (dataString == null || dataString.isEmpty) {
        return null;
      }
      
      return jsonDecode(dataString) as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error cargando saldo desde caché: $e');
      return null;
    }
  }

  /// Guardar historial de pagos en caché
  static Future<void> cacheHistorialPagos(List<Map<String, dynamic>> historial) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_historialPagosKey, jsonEncode(historial));
      print('💾 Historial de pagos guardado en caché: ${historial.length} registros');
    } catch (e) {
      print('❌ Error guardando historial de pagos en caché: $e');
    }
  }

  /// Obtener historial de pagos desde caché
  static Future<List<Map<String, dynamic>>> getCachedHistorialPagos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataString = prefs.getString(_historialPagosKey);
      
      if (dataString == null || dataString.isEmpty) {
        return [];
      }
      
      final historialJson = jsonDecode(dataString) as List;
      return historialJson.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      print('❌ Error cargando historial de pagos desde caché: $e');
      return [];
    }
  }

  /// Limpiar todo el caché del perfil
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_estadisticasKey);
      await prefs.remove(_saldoKey);
      await prefs.remove(_historialPagosKey);
      print('🗑️ Caché de perfil limpiado');
    } catch (e) {
      print('❌ Error limpiando caché de perfil: $e');
    }
  }
}

