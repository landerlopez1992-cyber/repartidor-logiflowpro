import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_sos_service.dart';

/// Contactos de confianza del socio (SOS en viaje).
class TaxiChoferContactosConfianzaScreen extends StatefulWidget {
  const TaxiChoferContactosConfianzaScreen({super.key});

  @override
  State<TaxiChoferContactosConfianzaScreen> createState() =>
      _TaxiChoferContactosConfianzaScreenState();
}

class _TaxiChoferContactosConfianzaScreenState
    extends State<TaxiChoferContactosConfianzaScreen> {
  bool _loading = true;
  String? _error;
  List<TaxiChoferContactoConfianza> _items = const [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await TaxiChoferSosService.instance.listarContactos();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : r.err;
      _items = r.items;
    });
  }

  Future<void> _editar({TaxiChoferContactoConfianza? existing}) async {
    final nombreCtrl = TextEditingController(text: existing?.nombre ?? '');
    final telCtrl = TextEditingController(text: existing?.telefono ?? '');
    final emailCtrl = TextEditingController(text: existing?.email ?? '');
    final buscarCtrl = TextEditingController();
    String? contactoWebId = existing?.contactoUsuarioWebId;
    String? contactoLabel = existing?.contactoNombreApp;
    var hits = <TaxiChoferUsuarioAppHit>[];
    var buscando = false;
    var busquedaHecha = false;
    Timer? debounce;
    var searchSeq = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void aplicarUsuario(TaxiChoferUsuarioAppHit h) {
            nombreCtrl.text = h.nombre;
            emailCtrl.text = h.email;
            if ((h.telefono ?? '').trim().isNotEmpty) {
              telCtrl.text = h.telefono!.trim();
            }
            contactoWebId = h.id;
            contactoLabel = h.nombre;
            hits = [];
            busquedaHecha = false;
            buscando = false;
            buscarCtrl.clear();
            setLocal(() {});
          }

          void buscar(String q) {
            debounce?.cancel();
            final clean = q.trim();
            if (clean.length < 2) {
              setLocal(() {
                hits = [];
                buscando = false;
                busquedaHecha = false;
              });
              return;
            }
            setLocal(() {
              buscando = true;
              busquedaHecha = false;
            });
            final seq = ++searchSeq;
            debounce = Timer(const Duration(milliseconds: 280), () async {
              final list =
                  await TaxiChoferSosService.instance.buscarUsuariosApp(clean);
              if (!ctx.mounted || seq != searchSeq) return;
              setLocal(() {
                hits = list;
                buscando = false;
                busquedaHecha = true;
              });
            });
          }

          return AlertDialog(
            backgroundColor: AppColors.darkElevated,
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Text(
              existing == null ? 'Nuevo contacto' : 'Editar contacto',
              style: const TextStyle(
                color: AppColors.darkText,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    style: const TextStyle(color: AppColors.darkText),
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      labelStyle: TextStyle(color: AppColors.darkTextMuted),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: telCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: AppColors.darkText),
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (opcional)',
                      labelStyle: TextStyle(color: AppColors.darkTextMuted),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: AppColors.darkText),
                    decoration: const InputDecoration(
                      labelText: 'Email (enviar ubicación)',
                      labelStyle: TextStyle(color: AppColors.darkTextMuted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Usuario de la app (push de emergencia)',
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  TextField(
                    controller: buscarCtrl,
                    style: const TextStyle(color: AppColors.darkText),
                    onChanged: buscar,
                    decoration: InputDecoration(
                      labelText: 'Buscar por nombre, email o teléfono',
                      labelStyle:
                          const TextStyle(color: AppColors.darkTextMuted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.darkTextMuted,
                      ),
                      suffixIcon: buscando
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.darkTextMuted,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (contactoWebId != null)
                    Chip(
                      label: Text(
                        'App: ${contactoLabel ?? 'usuario'}',
                        style: const TextStyle(color: AppColors.darkText),
                      ),
                      onDeleted: () => setLocal(() {
                        contactoWebId = null;
                        contactoLabel = null;
                      }),
                    ),
                  if (buscando)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Buscando coincidencias…',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (busquedaHecha && hits.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Sin coincidencias.',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else if (hits.isNotEmpty)
                    ...hits.take(6).map(
                      (h) => ListTile(
                        dense: true,
                        title: Text(
                          h.nombre,
                          style: const TextStyle(
                            color: AppColors.darkText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          [
                            h.email,
                            if ((h.telefono ?? '').trim().isNotEmpty)
                              h.telefono!.trim(),
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => aplicarUsuario(h),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: AppColors.darkTextMuted),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.header,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    debounce?.cancel();
    if (ok != true || !mounted) return;
    final r = await TaxiChoferSosService.instance.upsertContacto(
      nombre: nombreCtrl.text,
      telefono: telCtrl.text.trim().isEmpty ? null : telCtrl.text,
      email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text,
      contactoUsuarioWebId: contactoWebId,
      id: existing?.id,
    );
    if (!mounted) return;
    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.err ?? 'Error')),
      );
      return;
    }
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text(
          'Contactos de confianza',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _items.length >= 5 ? null : () => _editar(),
        backgroundColor: AppColors.header,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.darkTextMuted),
            )
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.darkTextMuted),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    const Text(
                      'En SOS se avisa por email, push (usuarios de la app) '
                      'y SMS a estos contactos.',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text(
                            'Sin contactos aún.',
                            style: TextStyle(color: AppColors.darkTextMuted),
                          ),
                        ),
                      )
                    else
                      ..._items.map(
                        (c) => Card(
                          color: AppColors.darkElevated,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text(
                              c.nombre,
                              style: const TextStyle(
                                color: AppColors.darkText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              c.subtitulo,
                              style: const TextStyle(
                                color: AppColors.darkTextMuted,
                              ),
                            ),
                            trailing: IconButton(
                              onPressed: () => _editar(existing: c),
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: AppColors.darkTextMuted,
                              ),
                            ),
                            onLongPress: () async {
                              await TaxiChoferSosService.instance
                                  .eliminarContacto(c.id);
                              await _cargar();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
