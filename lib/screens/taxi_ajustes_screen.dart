import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/taxi_tarifas_chofer_service.dart';
import '../services/taxi_vehiculo_catalog.dart';

/// Ajustes de tarifa taxi del socio (distancia + plazas + vehículo).
class TaxiAjustesScreen extends StatefulWidget {
  const TaxiAjustesScreen({super.key});

  @override
  State<TaxiAjustesScreen> createState() => _TaxiAjustesScreenState();
}

class _TaxiAjustesScreenState extends State<TaxiAjustesScreen> {
  final _precioCtrl = TextEditingController();
  final _recargoCtrl = TextEditingController();
  final _modeloCtrl = TextEditingController();
  String _unidad = 'km';
  int _capacidad = 4;
  int _incluidos = 2;
  /// Radio de trabajo en metros (default 150 km).
  int _radioTrabajoM = 150000;
  /// Tope A→B en metros; null = sin límite.
  int? _distanciaMaxViajeM;
  String? _marca;
  int? _anio;
  String? _color;
  bool _loading = true;
  bool _saving = false;

  static const double _ejemploDistancia = 20;
  static const int _maxPlazas = 20;
  static const List<int> _radiosKm = [30, 50, 80, 150, 250];
  static const List<int?> _maxViajeKm = [null, 50, 100, 200, 500];

  String get _avatarKey => TaxiVehiculoCatalog.resolveAvatarKey(
        marca: _marca ?? '',
        anio: _anio,
        capacidad: _capacidad,
      );

  String get _avatarAsset =>
      TaxiVehiculoCatalog.assetForKey(_avatarKey);

  @override
  void initState() {
    super.initState();
    _precioCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _recargoCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _cargar();
  }

  double? get _precioParsed {
    final raw = _precioCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw);
  }

  double get _recargoParsed {
    final raw = _recargoCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  String get _ejemploCobro {
    final p = _precioParsed;
    if (p == null || p < 0.01) {
      return 'Escribe tu tarifa para ver un ejemplo de cobro.';
    }
    final base = p * _ejemploDistancia;
    final rec = _recargoParsed;
    final pax2 = base +
        (2 > _incluidos ? (2 - _incluidos) * rec : 0);
    final paxFull = base +
        (_capacidad > _incluidos ? (_capacidad - _incluidos) * rec : 0);
    return 'Ejemplo trayecto ${_ejemploDistancia.toStringAsFixed(0)} $_unidad:\n'
        '• Base (distancia): \$${base.toStringAsFixed(2)}\n'
        '• Con 2 pasajeros: \$${pax2.toStringAsFixed(2)}\n'
        '• Con $_capacidad pasajeros (lleno): \$${paxFull.toStringAsFixed(2)}';
  }

  Future<void> _cargar() async {
    final t = await TaxiTarifasChoferService.instance.get();
    if (!mounted) return;
    setState(() {
      _unidad = t.unidad;
      _capacidad = t.capacidadPasajeros.clamp(1, _maxPlazas);
      _incluidos = t.pasajerosIncluidos.clamp(1, _capacidad);
      if (t.precioPorUnidadUsd > 0) {
        _precioCtrl.text = t.precioPorUnidadUsd.toStringAsFixed(
          t.precioPorUnidadUsd == t.precioPorUnidadUsd.roundToDouble() ? 0 : 2,
        );
      }
      if (t.recargoPorPasajeroUsd > 0) {
        _recargoCtrl.text = t.recargoPorPasajeroUsd.toStringAsFixed(
          t.recargoPorPasajeroUsd == t.recargoPorPasajeroUsd.roundToDouble()
              ? 0
              : 2,
        );
      } else {
        _recargoCtrl.text = '0';
      }
      _radioTrabajoM = t.radioTrabajoM.clamp(5000, 500000);
      _distanciaMaxViajeM = t.distanciaMaxViajeM;
      _marca = t.vehiculoMarca.isNotEmpty ? t.vehiculoMarca : null;
      _modeloCtrl.text = t.vehiculoModelo;
      _anio = t.vehiculoAnio;
      _color = t.vehiculoColor.isNotEmpty ? t.vehiculoColor : null;
      _loading = false;
    });
  }

  int get _radioKm => (_radioTrabajoM / 1000).round();

  String get _maxViajeLabel {
    final m = _distanciaMaxViajeM;
    if (m == null || m <= 0) return 'Sin límite';
    return '${(m / 1000).round()} km';
  }

  Future<void> _guardar() async {
    final raw = _precioCtrl.text.trim().replaceAll(',', '.');
    final precio = double.tryParse(raw);
    if (precio == null || precio < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tarifa válida (mínimo 0.01).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final recargo = _recargoParsed;
    if (recargo < 0 || recargo > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El recargo por pasajero debe estar entre 0 y 500.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Importante sobre tu tarifa',
          style: TextStyle(
            color: AppColors.darkText,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'Cobrarás \$${precio.toStringAsFixed(2)} USD por $_unidad '
            '(precio base del trayecto).\n\n'
            'Plazas: $_capacidad. Incluidos en la base: $_incluidos. '
            'Recargo por persona extra: \$${recargo.toStringAsFixed(2)}.\n\n'
            'Radio de trabajo: $_radioKm km. '
            'Viaje máximo: $_maxViajeLabel.\n\n'
            'Si tu precio queda muy alto frente a otros socios, '
            'recibirás menos viajes.',
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              height: 1.4,
              fontSize: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Revisar',
              style: TextStyle(color: AppColors.darkTextMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Guardar tarifa',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _saving = true);
    final res = await TaxiTarifasChoferService.instance.guardar(
      unidad: _unidad,
      precioPorUnidadUsd: precio,
      capacidadPasajeros: _capacidad,
      pasajerosIncluidos: _incluidos,
      recargoPorPasajeroUsd: recargo,
      radioTrabajoM: _radioTrabajoM,
      distanciaMaxViajeM: _distanciaMaxViajeM,
      vehiculoMarca: _marca,
      vehiculoModelo: _modeloCtrl.text.trim(),
      vehiculoAnio: _anio,
      vehiculoColor: _color,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok
              ? 'Tarifa guardada: \$${precio.toStringAsFixed(2)} / $_unidad'
              : (res.err ?? 'Error al guardar'),
        ),
        backgroundColor: res.ok ? AppColors.exito : AppColors.error,
      ),
    );
    if (res.ok) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    _recargoCtrl.dispose();
    _modeloCtrl.dispose();
    super.dispose();
  }

  Widget _numChip({
    required int n,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.header : AppColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            color: selected ? Colors.white : AppColors.darkText,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _labelChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.header : AppColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.darkText,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.darkTextMuted.withValues(alpha: 0.6),
      ),
      prefixText: '\$ ',
      prefixStyle: const TextStyle(color: AppColors.darkText),
      filled: true,
      fillColor: AppColors.darkElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF9CA3AF)),
      ),
    );
  }

  /// Campos de texto/listas (marca, modelo, etc.) — sin símbolo \$.
  InputDecoration _textoFieldDeco(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.darkTextMuted.withValues(alpha: 0.6),
      ),
      filled: true,
      fillColor: AppColors.darkElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF9CA3AF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text('Ajustes de taxis'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 16, 20, 96 + keyboard),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.darkElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_taxi,
                                    color: Color(0xFF9CA3AF), size: 22),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tu tarifa de viaje',
                                    style: TextStyle(
                                      color: AppColors.darkText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Precio base = distancia × tu tarifa. '
                              'Si van más personas de las incluidas, se suma tu '
                              'recargo por pasajero. Así un viaje lleno paga más '
                              'que uno de 1–2 personas.',
                              style: TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Unidad',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _unidadChip('Por kilómetro', 'km')),
                          const SizedBox(width: 10),
                          Expanded(child: _unidadChip('Por milla', 'mi')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _precioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _fieldDeco(
                          'Precio por $_unidad (USD)',
                          hint: 'Ej. 1.50',
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Plazas máximas del vehículo',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Sin contar al conductor. Sedán típico: 4. Minivan: 6–20.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_maxPlazas, (i) {
                          final n = i + 1;
                          return _numChip(
                            n: n,
                            selected: _capacidad == n,
                            onTap: () => setState(() {
                              _capacidad = n;
                              if (_incluidos > n) _incluidos = n;
                            }),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Pasajeros incluidos en el precio base',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hasta este número no hay recargo (recomendado: 2).',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_capacidad, (i) {
                          final n = i + 1;
                          return _numChip(
                            n: n,
                            selected: _incluidos == n,
                            onTap: () => setState(() => _incluidos = n),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _recargoCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _fieldDeco(
                          'Recargo por pasajero extra (USD)',
                          hint: 'Ej. 10',
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Si pones \$0, el precio no cambia con más personas '
                        '(solo limita quién cabe). Para una minivan llena, '
                        'usa un recargo alto.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.darkElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          _ejemploCobro,
                          style: const TextStyle(
                            color: Color(0xFFECEFF1),
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Zona de trabajo',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hasta qué lejos del pasajero aceptas ir a recogerlo. '
                        'Si el origen está más lejos, no te mostrarán el viaje.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _radiosKm.map((km) {
                          final selected = _radioKm == km;
                          return _labelChip(
                            label: '$km km',
                            selected: selected,
                            onTap: () => setState(
                              () => _radioTrabajoM = km * 1000,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Distancia máxima del viaje (A → B)',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tope del trayecto completo. Útil si no quieres '
                        'viajes muy largos (ej. entre ciudades).',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _maxViajeKm.map((km) {
                          final selected = km == null
                              ? (_distanciaMaxViajeM == null ||
                                  _distanciaMaxViajeM! <= 0)
                              : (_distanciaMaxViajeM != null &&
                                  (_distanciaMaxViajeM! / 1000).round() == km);
                          return _labelChip(
                            label: km == null ? 'Sin límite' : '$km km',
                            selected: selected,
                            onTap: () => setState(() {
                              _distanciaMaxViajeM =
                                  km == null ? null : km * 1000;
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Tu vehículo',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Marca, modelo, año y color. En las ofertas el cliente '
                        've una silueta similar; cuando aceptes un viaje verá '
                        'tu foto real y estos datos.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 180,
                          height: 100,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.darkBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            _avatarAsset,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.directions_car,
                              color: Color(0xFF9CA3AF),
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _avatarKey == 'clasico'
                            ? 'Silueta clásica'
                            : _avatarKey == 'van'
                                ? 'Silueta van / muchas plazas'
                                : 'Silueta moderna',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _marca != null &&
                                TaxiVehiculoCatalog.marcas.contains(_marca)
                            ? _marca
                            : null,
                        dropdownColor: AppColors.darkElevated,
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _textoFieldDeco('Marca'),
                        items: TaxiVehiculoCatalog.marcas
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _marca = v),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modeloCtrl,
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _textoFieldDeco('Modelo'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _anio != null &&
                                TaxiVehiculoCatalog.aniosDisponibles()
                                    .contains(_anio)
                            ? _anio
                            : null,
                        dropdownColor: AppColors.darkElevated,
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _textoFieldDeco('Año'),
                        items: TaxiVehiculoCatalog.aniosDisponibles()
                            .map(
                              (y) => DropdownMenuItem(
                                value: y,
                                child: Text('$y'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _anio = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _color != null &&
                                TaxiVehiculoCatalog.colores.contains(_color)
                            ? _color
                            : null,
                        dropdownColor: AppColors.darkElevated,
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: _textoFieldDeco('Color'),
                        items: TaxiVehiculoCatalog.colores
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _color = v),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _saving ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.header,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Guardar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _unidadChip(String label, String value) {
    final selected = _unidad == value;
    return InkWell(
      onTap: () => setState(() => _unidad = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.header : AppColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.darkText,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
