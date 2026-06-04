import 'package:flutter/material.dart';
import '../main.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

class HistorialPagosCompletoScreen extends StatefulWidget {
  final String repartidorId;
  final String repartidorNombre;

  const HistorialPagosCompletoScreen({
    super.key,
    required this.repartidorId,
    required this.repartidorNombre,
  });

  @override
  State<HistorialPagosCompletoScreen> createState() => _HistorialPagosCompletoScreenState();
}

class _HistorialPagosCompletoScreenState extends State<HistorialPagosCompletoScreen> {
  List<Map<String, dynamic>> _historialPagos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Obtener historial del último mes
      final fechaLimite = DateTime.now().subtract(const Duration(days: 30));
      
      final historialResponse = await supabase
          .from('solicitudes_pago_repartidores')
          .select('*')
          .eq('repartidor_id', widget.repartidorId)
          .gte('fecha_solicitud', fechaLimite.toIso8601String())
          .order('fecha_solicitud', ascending: false);

      setState(() {
        _historialPagos = List<Map<String, dynamic>>.from(historialResponse);
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error cargando historial completo: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar historial: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondoGeneral,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text(
          'Historial de Pagos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historialPagos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.payment_outlined,
                        size: 64,
                        color: AppColors.darkTextMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay pagos en el último mes',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarHistorial,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppLayout.cardMaxWidth),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _historialPagos.length,
                        itemBuilder: (context, index) {
                          final pago = _historialPagos[index];
                          return _buildItemPago(pago);
                        },
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildItemPago(Map<String, dynamic> pago) {
    final estado = pago['estado']?.toString() ?? 'PENDIENTE';
    final monto = (pago['monto'] ?? 0.0).toDouble();
    final moneda = pago['moneda']?.toString() ?? 'CUP';
    final fechaSolicitud = pago['fecha_solicitud'] != null
        ? DateTime.parse(pago['fecha_solicitud'])
        : null;
    final fechaAceptacion = pago['fecha_aceptacion'] != null
        ? DateTime.parse(pago['fecha_aceptacion'])
        : null;
    final aceptadoPor = pago['aceptado_por_nombre']?.toString();
    final totalOrdenes = pago['total_ordenes_entregadas'] ?? 0;

    Color colorEstado;
    IconData iconoEstado;
    String textoEstado;

    switch (estado) {
      case 'PENDIENTE':
        colorEstado = const Color(0xFFFF9800);
        iconoEstado = Icons.pending;
        textoEstado = 'Pendiente';
        break;
      case 'ACEPTADO':
        colorEstado = const Color(0xFF4CAF50);
        iconoEstado = Icons.check_circle;
        textoEstado = 'Aceptado';
        break;
      case 'RECHAZADO':
        colorEstado = const Color(0xFFDC2626);
        iconoEstado = Icons.cancel;
        textoEstado = 'Rechazado';
        break;
      default:
        colorEstado = const Color(0xFF666666);
        iconoEstado = Icons.help;
        textoEstado = estado;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorEstado.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorEstado.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconoEstado, color: colorEstado, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        textoEstado,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorEstado,
                        ),
                      ),
                      if (totalOrdenes > 0)
                        Text(
                          '$totalOrdenes orden${totalOrdenes != 1 ? 'es' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF666666),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${monto.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorEstado,
                    ),
                  ),
                  Text(
                    moneda,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorEstado.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),
          if (fechaSolicitud != null)
            _buildInfoRow(
              Icons.calendar_today,
              'Solicitado',
              _formatearFecha(fechaSolicitud),
            ),
          if (fechaAceptacion != null && estado == 'ACEPTADO') ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.check_circle_outline,
              'Aceptado',
              _formatearFecha(fechaAceptacion),
            ),
          ],
          if (aceptadoPor != null && estado == 'ACEPTADO') ...[
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.person_outline,
              'Por',
              aceptadoPor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF666666)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF666666),
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF2C2C2C),
            ),
          ),
        ),
      ],
    );
  }
}

