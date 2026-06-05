import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/repartidor_historial_pago_service.dart';
import '../services/repartidor_perfil_cache_service.dart';
import '../services/repartidor_solicitud_pago_offline_service.dart';
import '../services/sync_service.dart';
import '../widgets/historial_pago_detalle_card.dart';
import '../widgets/volonex_dialog.dart';
import '../widgets/volonex_ui.dart';

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
  List<HistorialNominaItem> _nominas = [];
  List<Map<String, dynamic>> _acreditaciones = [];
  bool _isLoading = true;
  String _filtroEstado = 'TODOS';
  bool _verAcreditaciones = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (!SyncService().isOnline) {
        final cache =
            await RepartidorSolicitudPagoOfflineService.historialConLocales(
          widget.repartidorId,
        );
        setState(() {
          _nominas = cache.map((s) => HistorialNominaItem(solicitud: s)).toList();
          _acreditaciones = [];
          _isLoading = false;
        });
        return;
      }

      final nominas = await RepartidorHistorialPagoService.cargarHistorial(widget.repartidorId);
      final acreditaciones =
          await RepartidorHistorialPagoService.cargarAcreditacionesSaldo(widget.repartidorId);

      await RepartidorPerfilCacheService.cacheHistorialPagos(
        nominas.map((n) => n.solicitud).toList(),
      );

      if (!mounted) return;
      setState(() {
        _nominas = nominas;
        _acreditaciones = acreditaciones;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error historial pagos: $e');
      if (!mounted) return;
      final cache =
          await RepartidorSolicitudPagoOfflineService.historialConLocales(
        widget.repartidorId,
      );
      if (cache.isNotEmpty) {
        setState(() {
          _nominas = cache.map((s) => HistorialNominaItem(solicitud: s)).toList();
          _acreditaciones = [];
          _error = null;
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _error = 'Sin conexión. No hay historial guardado en el dispositivo.';
        _isLoading = false;
      });
    }
  }

  List<HistorialNominaItem> get _nominasFiltradas {
    if (_filtroEstado == 'TODOS') return _nominas;
    return _nominas.where((n) => n.estado == _filtroEstado).toList();
  }

  double get _totalAceptado {
    return _nominas
        .where((n) => n.estado == 'ACEPTADO')
        .fold(0.0, (s, n) => s + n.monto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text(
          'Historial de nóminas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.botonPrincipal))
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: AppColors.botonPrincipal,
                  onRefresh: _cargarHistorial,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: AppLayout.cardMaxWidth),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildResumen(),
                          const SizedBox(height: 16),
                          _buildFiltros(),
                          const SizedBox(height: 12),
                          if (_verAcreditaciones) ...[
                            _buildSeccionTitulo('Acreditaciones de saldo (entregas)'),
                            if (_acreditaciones.isEmpty)
                              _emptyHint('No hay acreditaciones recientes en el saldo.'),
                            ..._acreditaciones.map((m) => HistorialAcreditacionCard(movimiento: m)),
                            const SizedBox(height: 20),
                          ],
                          _buildSeccionTitulo('Solicitudes de nómina'),
                          if (_nominasFiltradas.isEmpty)
                            _emptyHint(
                              _nominas.isEmpty
                                  ? 'Aún no hay solicitudes de pago. Cuando solicites y la empresa apruebe una nómina, aparecerá aquí con todo el detalle.'
                                  : 'No hay solicitudes con el filtro seleccionado.',
                            )
                          else
                            ..._nominasFiltradas.map(
                              (item) => HistorialPagoDetalleCard(item: item, expanded: _nominasFiltradas.length <= 3),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.darkText)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _cargarHistorial,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.botonPrincipal),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResumen() {
    final aceptadas = _nominas.where((n) => n.estado == 'ACEPTADO').length;
    final pendientes = _nominas.where((n) => n.estado == 'PENDIENTE').length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.repartidorNombre,
            style: const TextStyle(color: AppColors.darkText, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('Cobradas', '$aceptadas', AppColors.exito),
              _stat('Pendientes', '$pendientes', AppColors.botonPrincipal),
              _stat('Total cobrado', '\$${_totalAceptado.toStringAsFixed(0)}', AppColors.darkText),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildFiltros() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chipFiltro('TODOS', 'Todos'),
              _chipFiltro('ACEPTADO', 'Cobradas'),
              _chipFiltro('PENDIENTE', 'Pendientes'),
              _chipFiltro('RECHAZADO', 'Rechazadas'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        VolonexUi.materialFilterChip(
          label: 'Ver acreditaciones de saldo por entrega',
          selected: _verAcreditaciones,
          onSelected: (v) => setState(() => _verAcreditaciones = v),
        ),
      ],
    );
  }

  Widget _chipFiltro(String value, String label) {
    final sel = _filtroEstado == value;
    return VolonexUi.filterChip(
      label: label,
      selected: sel,
      onTap: () => setState(() => _filtroEstado = value),
    );
  }

  Widget _buildSeccionTitulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        t,
        style: const TextStyle(
          color: AppColors.darkText,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _emptyHint(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.history, size: 48, color: AppColors.darkTextMuted),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
