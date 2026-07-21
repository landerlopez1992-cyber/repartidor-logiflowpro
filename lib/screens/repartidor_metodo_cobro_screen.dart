import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../main.dart' show supabase;

/// Métodos de cobro de nómina (cómo la empresa te paga).
class RepartidorMetodoCobroScreen extends StatefulWidget {
  const RepartidorMetodoCobroScreen({super.key});

  @override
  State<RepartidorMetodoCobroScreen> createState() =>
      _RepartidorMetodoCobroScreenState();
}

class _RepartidorMetodoCobroScreenState
    extends State<RepartidorMetodoCobroScreen> {
  static const _metodos = [
    _MetodoDef(
      id: 'efectivo',
      label: 'Efectivo',
      hint: 'Cobro en mano; no necesitas datos bancarios.',
    ),
    _MetodoDef(
      id: 'transferencia_bancaria',
      label: 'Transferencia bancaria',
      hint: 'ACH / cuenta bancaria en EE.UU.',
    ),
    _MetodoDef(
      id: 'zelle',
      label: 'Zelle',
      hint: 'Teléfono o correo registrado en Zelle.',
    ),
    _MetodoDef(
      id: 'western_union',
      label: 'Western Union',
      hint: 'Datos del beneficiario para envío internacional.',
    ),
  ];

  final _activos = <String>{};
  String? _preferido;
  bool _loading = true;
  bool _saving = false;

  // Transferencia
  final _titular = TextEditingController();
  final _banco = TextEditingController();
  final _routing = TextEditingController();
  final _cuenta = TextEditingController();
  // Zelle
  final _zelleTel = TextEditingController();
  final _zelleNombre = TextEditingController();
  // Western Union
  final _wuNombre = TextEditingController();
  final _wuApellidos = TextEditingController();
  final _wuDireccion = TextEditingController();
  final _wuCiudad = TextEditingController();
  final _wuPais = TextEditingController();
  final _wuTel = TextEditingController();
  final _wuDoc = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _titular.dispose();
    _banco.dispose();
    _routing.dispose();
    _cuenta.dispose();
    _zelleTel.dispose();
    _zelleNombre.dispose();
    _wuNombre.dispose();
    _wuApellidos.dispose();
    _wuDireccion.dispose();
    _wuCiudad.dispose();
    _wuPais.dispose();
    _wuTel.dispose();
    _wuDoc.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final authId = supabase.auth.currentUser?.id;
      if (authId == null) return;
      final row = await supabase
          .from('usuarios')
          .select(
            'repartidor_metodo_cobro_preferido, repartidor_metodo_cobro_datos',
          )
          .eq('auth_id', authId)
          .maybeSingle();
      if (!mounted) return;
      final datos = row?['repartidor_metodo_cobro_datos'];
      final map = datos is Map
          ? Map<String, dynamic>.from(datos)
          : <String, dynamic>{};
      _activos
        ..clear()
        ..addAll(
          _metodos.map((m) => m.id).where((id) => map[id] != null),
        );
      _preferido = row?['repartidor_metodo_cobro_preferido']?.toString();

      final t = _asMap(map['transferencia_bancaria']);
      _titular.text = t['nombre_titular']?.toString() ?? '';
      _banco.text = t['banco']?.toString() ?? '';
      _routing.text = t['routing']?.toString() ?? '';
      _cuenta.text = t['cuenta']?.toString() ?? '';

      final z = _asMap(map['zelle']);
      _zelleTel.text = z['telefono']?.toString() ?? '';
      _zelleNombre.text = z['nombre_registro']?.toString() ?? '';

      final w = _asMap(map['western_union']);
      _wuNombre.text = w['nombre']?.toString() ?? '';
      _wuApellidos.text = w['apellidos']?.toString() ?? '';
      _wuDireccion.text = w['direccion']?.toString() ?? '';
      _wuCiudad.text = w['ciudad']?.toString() ?? '';
      _wuPais.text = w['pais']?.toString() ?? '';
      _wuTel.text = w['telefono']?.toString() ?? '';
      _wuDoc.text = w['documento_identidad']?.toString() ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cargar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return {};
  }

  Map<String, dynamic> _payload() {
    final out = <String, dynamic>{};
    if (_activos.contains('efectivo')) {
      out['efectivo'] = {'activo': true};
    }
    if (_activos.contains('transferencia_bancaria')) {
      out['transferencia_bancaria'] = {
        'nombre_titular': _titular.text.trim(),
        'banco': _banco.text.trim(),
        'routing': _routing.text.trim(),
        'cuenta': _cuenta.text.trim(),
      };
    }
    if (_activos.contains('zelle')) {
      out['zelle'] = {
        'telefono': _zelleTel.text.trim(),
        'nombre_registro': _zelleNombre.text.trim(),
      };
    }
    if (_activos.contains('western_union')) {
      out['western_union'] = {
        'nombre': _wuNombre.text.trim(),
        'apellidos': _wuApellidos.text.trim(),
        'direccion': _wuDireccion.text.trim(),
        'ciudad': _wuCiudad.text.trim(),
        'pais': _wuPais.text.trim(),
        'telefono': _wuTel.text.trim(),
        'documento_identidad': _wuDoc.text.trim(),
      };
    }
    return out;
  }

  Future<void> _guardar() async {
    if (_activos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activa al menos un método de cobro'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    var preferido = _preferido;
    if (preferido == null || !_activos.contains(preferido)) {
      preferido = _activos.first;
    }
    setState(() => _saving = true);
    try {
      final res = await supabase.rpc(
        'guardar_repartidor_metodos_cobro',
        params: {
          'p_preferido': preferido,
          'p_metodos': _payload(),
        },
      );
      if (!mounted) return;
      if (res is! Map || res['ok'] != true) {
        final err = res is Map ? res['error']?.toString() : 'error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_msgError(err)),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() {
        _preferido = res['preferido']?.toString() ?? preferido;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Métodos de cobro guardados'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _msgError(String? err) {
    switch (err) {
      case 'faltan_datos_transferencia':
        return 'Completa routing y número de cuenta.';
      case 'faltan_datos_zelle':
        return 'Completa teléfono/correo y nombre en Zelle.';
      case 'faltan_datos_western_union':
        return 'Completa nombre, apellidos, país y documento.';
      case 'sin_metodos_activos':
        return 'Activa al menos un método.';
      default:
        return 'No se pudo guardar (${err ?? 'error'}).';
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF1E232E),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF9CA3AF)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  static const _fieldStyle = TextStyle(color: Color(0xFFECEFF1), fontSize: 14);

  Widget _campo(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        style: _fieldStyle,
        decoration: _dec(label),
      ),
    );
  }

  Widget _bloqueMetodo(_MetodoDef m) {
    final on = _activos.contains(m.id);
    final esPref = _preferido == m.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: on
              ? const Color(0xFF37474F)
              : AppColors.darkBorder,
          width: on ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label,
                      style: const TextStyle(
                        color: AppColors.darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.hint,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                activeTrackColor: const Color(0xFF546E7A),
                activeThumbColor: const Color(0xFFECEFF1),
                onChanged: (v) {
                  setState(() {
                    if (v) {
                      _activos.add(m.id);
                      _preferido ??= m.id;
                    } else {
                      _activos.remove(m.id);
                      if (_preferido == m.id) {
                        _preferido =
                            _activos.isEmpty ? null : _activos.first;
                      }
                    }
                  });
                },
              ),
            ],
          ),
          if (on) ...[
            const SizedBox(height: 8),
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                esPref ? 'Método preferido (activo)' : 'Usar como preferido',
                style: const TextStyle(
                  color: Color(0xFFECEFF1),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              value: m.id,
              groupValue: _preferido,
              activeColor: const Color(0xFFFF9800),
              onChanged: (v) => setState(() => _preferido = v),
            ),
            if (m.id == 'transferencia_bancaria') ...[
              _campo(_titular, 'Nombre del titular'),
              _campo(_banco, 'Banco'),
              _campo(_routing, 'Routing (ABA) *'),
              _campo(_cuenta, 'Número de cuenta *'),
            ],
            if (m.id == 'zelle') ...[
              _campo(_zelleTel, 'Teléfono o correo Zelle *'),
              _campo(_zelleNombre, 'Nombre registrado en Zelle *'),
            ],
            if (m.id == 'western_union') ...[
              _campo(_wuNombre, 'Nombre *'),
              _campo(_wuApellidos, 'Apellidos *'),
              _campo(_wuDireccion, 'Dirección'),
              _campo(_wuCiudad, 'Ciudad'),
              _campo(_wuPais, 'País *'),
              _campo(_wuTel, 'Teléfono'),
              _campo(_wuDoc, 'Documento de identidad *'),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        title: const Text('Método de cobro'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      const Text(
                        'Configura cómo quieres que la empresa te pague '
                        'tu nómina. Puedes activar varios y elegir uno '
                        'como preferido.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final m in _metodos) _bloqueMetodo(m),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF37474F),
                          foregroundColor: Colors.white,
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
                                'Guardar métodos de cobro',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MetodoDef {
  const _MetodoDef({
    required this.id,
    required this.label,
    required this.hint,
  });
  final String id;
  final String label;
  final String hint;
}
