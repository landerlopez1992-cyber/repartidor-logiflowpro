import 'package:supabase_flutter/supabase_flutter.dart';

/// Órdenes con entrega por vendedor no deben aparecer en la app del repartidor.
class EntregaVendedorFiltro {
  EntregaVendedorFiltro._();

  static const String _orNoEntregaVendedor =
      'entrega_por_vendedor.is.null,entrega_por_vendedor.eq.false';

  static PostgrestFilterBuilder<T> excluirEnConsulta<T>(
    PostgrestFilterBuilder<T> query,
  ) {
    return query.or(_orNoEntregaVendedor);
  }

  static bool incluirFila(Map<String, dynamic> row) {
    return row['entrega_por_vendedor'] != true;
  }
}
