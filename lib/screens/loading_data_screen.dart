import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/repartidor_loading_spinner.dart';
import '../widgets/volonex_dialog.dart';

/// Pantalla de carga que muestra progreso mientras se cargan datos reales
/// (mismo icono sync_rounded que la app móvil + soporte logo offline).
class LoadingDataScreen extends StatefulWidget {
  final String? userName;
  final String? empresaNombre;
  final String? empresaLogoUrl;
  /// Ruta local del logo (caché disco) para modo offline.
  final String? empresaLogoLocalPath;
  final Future<void> Function(
      Function(double progress, String message) updateProgress)? onLoadData;
  final VoidCallback? onComplete;

  const LoadingDataScreen({
    super.key,
    this.userName,
    this.empresaNombre,
    this.empresaLogoUrl,
    this.empresaLogoLocalPath,
    this.onLoadData,
    this.onComplete,
  });

  @override
  State<LoadingDataScreen> createState() => _LoadingDataScreenState();
}

class _LoadingDataScreenState extends State<LoadingDataScreen> {
  double _progress = 0.0;
  String _currentMessage = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _startLoadingProcess();
  }

  Future<void> _startLoadingProcess() async {
    try {
      if (widget.onLoadData != null) {
        await widget.onLoadData!((progress, message) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _currentMessage = message;
            });
          }
        });
      } else {
        await _simulateLoading();
      }

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _currentMessage = 'Completado';
        });

        await Future.delayed(const Duration(milliseconds: 300));

        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    } catch (e) {
      print('❌ Error en proceso de carga: $e');
      if (mounted) {
        setState(() {
          _currentMessage = 'Error: $e';
        });

        await Future.delayed(const Duration(seconds: 2));
        if (widget.onComplete != null) {
          widget.onComplete!();
        }
      }
    }
  }

  /// Logo sin caja de fondo (local → red → letra → asset).
  Widget _buildLogoSinFondo() {
    const size = 140.0;
    const margin = EdgeInsets.only(bottom: 32);

    final local = widget.empresaLogoLocalPath;
    if (!kIsWeb &&
        local != null &&
        local.isNotEmpty &&
        File(local).existsSync()) {
      return Padding(
        padding: margin,
        child: Image.file(
          File(local),
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _logoFromNetworkOrFallback(size, margin),
        ),
      );
    }

    return _logoFromNetworkOrFallback(size, margin);
  }

  Widget _logoFromNetworkOrFallback(double size, EdgeInsets margin) {
    if (widget.empresaLogoUrl != null && widget.empresaLogoUrl!.isNotEmpty) {
      return Padding(
        padding: margin,
        child: Image.network(
          widget.empresaLogoUrl!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) {
            return _logoFallbackLetra(size);
          },
        ),
      );
    }

    if (widget.empresaNombre != null && widget.empresaNombre!.isNotEmpty) {
      return Padding(
        padding: margin,
        child: _logoFallbackLetra(size),
      );
    }

    return Padding(
      padding: margin,
      child: Image.asset(
        'assets/logo_julio.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            Icons.delivery_dining,
            size: 72,
            color: AppColors.botonPrincipal,
          );
        },
      ),
    );
  }

  Widget _logoFallbackLetra(double size) {
    final letra = widget.empresaNombre?.isNotEmpty == true
        ? widget.empresaNombre![0].toUpperCase()
        : 'V';
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          letra,
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.bold,
            color: AppColors.botonPrincipal,
          ),
        ),
      ),
    );
  }

  Future<void> _simulateLoading() async {
    final stages = [
      {'text': 'Inicializando sistema', 'duration': 1.0},
      {'text': 'Cargando configuración', 'duration': 1.0},
      {'text': 'Preparando interfaz', 'duration': 1.0},
      {'text': 'Verificando conexión', 'duration': 1.0},
      {'text': 'Finalizando', 'duration': 1.0},
    ];

    double totalDuration =
        stages.fold(0.0, (sum, stage) => sum + (stage['duration'] as double));
    double accumulatedProgress = 0.0;

    for (var stage in stages) {
      if (!mounted) return;

      setState(() {
        _currentMessage = stage['text'] as String;
      });

      double stageDuration = stage['duration'] as double;
      double stageProgressIncrement = (stageDuration / totalDuration);

      int steps = 20;
      double stepProgress = stageProgressIncrement / steps;
      double stepDuration = stageDuration / steps;

      for (int j = 0; j < steps; j++) {
        await Future.delayed(
            Duration(milliseconds: (stepDuration * 1000).round()));
        if (mounted) {
          setState(() {
            accumulatedProgress += stepProgress;
            _progress = accumulatedProgress;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.header,
              Color(0xFF263238),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxHeight < 420;
              final logoSize = landscape ? 72.0 : 140.0;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.formMaxWidth,
                      ),
                      padding: EdgeInsets.all(landscape ? 20 : 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: logoSize,
                            height: logoSize,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: _buildLogoSinFondo(),
                            ),
                          ),
                          if (widget.empresaNombre != null &&
                              widget.empresaNombre!.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: landscape ? 8 : 16,
                              ),
                              child: Text(
                                widget.empresaNombre!,
                                style: TextStyle(
                                  fontSize: landscape ? 18 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.darkText,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          SizedBox(height: landscape ? 16 : 28),
                          const RepartidorLoadingSpinner.large(
                            color: AppColors.botonPrincipal,
                          ),
                          SizedBox(height: landscape ? 16 : 24),
                          Text(
                            _currentMessage,
                            style: TextStyle(
                              fontSize: landscape ? 15 : 18,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: landscape ? 16 : 24),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _progress,
                              minHeight: 8,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.botonPrincipal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(_progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
