import '../main.dart';

/// Servicio para obtener información de países, provincias y municipios
class PaisesService {
  /// Obtener país de operación de la empresa (tenant)
  static Future<String?> obtenerPaisOperacion(String tenantId) async {
    try {
      final tenant = await supabase
          .from('tenants')
          .select('pais_operacion')
          .eq('id', tenantId)
          .single();
      
      final pais = tenant['pais_operacion'] as String?;
      return pais ?? 'Cuba'; // País por defecto si no está configurado
    } catch (e) {
      print('❌ Error obteniendo país de operación: $e');
      return 'Cuba'; // País por defecto
    }
  }

  /// Obtener país de operación del tenant actual (desde el usuario autenticado)
  static Future<String?> obtenerPaisOperacionActual() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return 'Cuba';
      
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      
      if (userData == null || userData['tenant_id'] == null) {
        return 'Cuba';
      }
      
      return await obtenerPaisOperacion(userData['tenant_id'].toString());
    } catch (e) {
      print('❌ Error obteniendo país de operación actual: $e');
      return 'Cuba';
    }
  }

  /// Obtener provincias/estados por país desde la base de datos
  static Future<List<String>> obtenerProvinciasPorPais(String nombrePais) async {
    try {
      final pais = await supabase
          .from('paises')
          .select('id')
          .eq('nombre', nombrePais)
          .eq('activo', true)
          .single();
      
      final provincias = await supabase
          .from('provincias')
          .select('nombre')
          .eq('pais_id', pais['id'])
          .eq('activo', true)
          .order('nombre');
      
      return provincias.map((p) => p['nombre'] as String).toList();
    } catch (e) {
      print('❌ Error obteniendo provincias para $nombrePais: $e');
      // Fallback a datos estáticos si la base de datos falla
      return _obtenerProvinciasEstaticas(nombrePais);
    }
  }

  /// Obtener municipios/ciudades por provincia desde la base de datos
  static Future<List<String>> obtenerMunicipiosPorProvincia(
    String nombrePais,
    String nombreProvincia,
  ) async {
    try {
      final pais = await supabase
          .from('paises')
          .select('id')
          .eq('nombre', nombrePais)
          .eq('activo', true)
          .single();
      
      final provincia = await supabase
          .from('provincias')
          .select('id')
          .eq('pais_id', pais['id'])
          .eq('nombre', nombreProvincia)
          .eq('activo', true)
          .single();
      
      final municipios = await supabase
          .from('municipios')
          .select('nombre')
          .eq('provincia_id', provincia['id'])
          .eq('activo', true)
          .order('nombre');
      
      return municipios.map((m) => m['nombre'] as String).toList();
    } catch (e) {
      print('❌ Error obteniendo municipios para $nombreProvincia, $nombrePais: $e');
      return [];
    }
  }

  /// Fallback a datos estáticos si falla la base de datos
  static List<String> _obtenerProvinciasEstaticas(String nombrePais) {
    // Importar PaisesProvinciasMunicipios si es necesario
    // Por ahora retornar lista vacía, se puede mejorar después
    return [];
  }

  /// Obtener todos los países disponibles
  static Future<List<Map<String, dynamic>>> obtenerPaisesDisponibles() async {
    try {
      final paises = await supabase
          .from('paises')
          .select('id, codigo, nombre, sancionado, licencia_especial')
          .eq('activo', true)
          .order('nombre');
      
      return List<Map<String, dynamic>>.from(paises);
    } catch (e) {
      print('❌ Error obteniendo países: $e');
      return [];
    }
  }
}

