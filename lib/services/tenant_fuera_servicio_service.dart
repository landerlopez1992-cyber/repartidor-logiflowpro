import '../main.dart';

/// Empresa (tenant) fuera de servicio: Super Admin bloqueó o sin suscripción.
class TenantFueraServicioEstado {
  const TenantFueraServicioEstado({
    required this.bloqueada,
    this.motivo,
    this.nombreEmpresa = 'la empresa',
    this.emailContacto,
    this.telefono,
  });

  final bool bloqueada;
  final String? motivo;
  final String nombreEmpresa;
  final String? emailContacto;
  final String? telefono;
}

class TenantFueraServicioService {
  TenantFueraServicioService._();

  static TenantFueraServicioEstado? _cache;
  static DateTime? _cacheAt;
  static const _ttl = Duration(seconds: 25);

  static Future<TenantFueraServicioEstado?> fetch({
    required String tenantId,
    bool forceRefresh = false,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;

    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < _ttl) {
      return _cache;
    }

    try {
      final raw = await supabase.rpc(
        'get_tenant_fuera_servicio',
        params: {'p_tenant_id': tid},
      );
      final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final estado = TenantFueraServicioEstado(
        bloqueada: map['bloqueada'] == true,
        motivo: map['motivo']?.toString(),
        nombreEmpresa: map['nombre_empresa']?.toString().trim().isNotEmpty == true
            ? map['nombre_empresa'].toString().trim()
            : 'la empresa',
        emailContacto: map['email_contacto']?.toString(),
        telefono: map['telefono']?.toString(),
      );
      _cache = estado;
      _cacheAt = now;
      return estado;
    } catch (e) {
      print('⚠️ TenantFueraServicioService: $e');
      return _cache;
    }
  }

  static void invalidateCache() {
    _cache = null;
    _cacheAt = null;
  }
}
