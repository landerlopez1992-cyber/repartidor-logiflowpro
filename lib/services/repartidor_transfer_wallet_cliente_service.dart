import '../main.dart';

/// Destino detectado: cuenta cliente del mismo email + tenant.
class RepartidorWalletClienteDestino {
  const RepartidorWalletClienteDestino({
    required this.tieneCuentaCliente,
    required this.nombreEmpresa,
    required this.saldoRepartidor,
    required this.moneda,
    required this.solicitudPagoPendiente,
    this.usuarioWebId,
    this.emailCliente,
    this.saldoCliente,
    this.emailRepartidor,
  });

  final bool tieneCuentaCliente;
  final String nombreEmpresa;
  final double saldoRepartidor;
  final String moneda;
  final bool solicitudPagoPendiente;
  final String? usuarioWebId;
  final String? emailCliente;
  final double? saldoCliente;
  final String? emailRepartidor;

  factory RepartidorWalletClienteDestino.fromMap(Map<String, dynamic> m) {
    double? n(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    return RepartidorWalletClienteDestino(
      tieneCuentaCliente: m['tiene_cuenta_cliente'] == true,
      nombreEmpresa: (m['nombre_empresa']?.toString().trim().isNotEmpty == true)
          ? m['nombre_empresa'].toString().trim()
          : 'tu empresa',
      saldoRepartidor: n(m['saldo_repartidor']) ?? 0,
      moneda: (m['moneda']?.toString().trim().isNotEmpty == true)
          ? m['moneda'].toString().trim().toUpperCase()
          : 'USD',
      solicitudPagoPendiente: m['solicitud_pago_pendiente'] == true,
      usuarioWebId: m['usuario_web_id']?.toString(),
      emailCliente: m['email_cliente']?.toString(),
      saldoCliente: n(m['saldo_cliente']),
      emailRepartidor: m['email_repartidor']?.toString(),
    );
  }
}

class RepartidorTransferWalletClienteService {
  RepartidorTransferWalletClienteService._();

  static Future<RepartidorWalletClienteDestino?> detectarDestino() async {
    try {
      final res = await supabase.rpc('repartidor_wallet_cliente_destino');
      if (res is! Map) return null;
      final map = Map<String, dynamic>.from(res);
      if (map['ok'] != true) return null;
      return RepartidorWalletClienteDestino.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  /// Retorna mapa de respuesta RPC (`ok`, `mensaje`, saldos…).
  static Future<Map<String, dynamic>> transferir(double monto) async {
    try {
      final res = await supabase.rpc(
        'repartidor_transferir_saldo_a_wallet_cliente',
        params: {'p_monto': monto},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return {'ok': false, 'error': 'respuesta_invalida', 'mensaje': 'Respuesta inválida.'};
    } catch (e) {
      return {
        'ok': false,
        'error': 'excepcion',
        'mensaje': e.toString(),
      };
    }
  }
}
