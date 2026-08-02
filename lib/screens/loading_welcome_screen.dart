import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/repartidor_loading_spinner.dart';
import '../widgets/volonex_dialog.dart';

class LoadingWelcomeScreen extends StatefulWidget {
  final String? userName;
  final String? empresaNombre;
  final String? empresaLogoUrl;

  const LoadingWelcomeScreen({
    super.key,
    this.userName,
    this.empresaNombre,
    this.empresaLogoUrl,
  });

  @override
  State<LoadingWelcomeScreen> createState() => _LoadingWelcomeScreenState();
}

class _LoadingWelcomeScreenState extends State<LoadingWelcomeScreen> {
  double _progress = 0.0;
  String _currentMessage = 'Cargando....';

  final List<Map<String, dynamic>> _processStages = [
    {
      'text': 'Inicializando sistema',
      'duration': 3.0, // 3 segundos
    },
    {
      'text': 'Cargando configuración',
      'duration': 2.5, // 2.5 segundos
    },
    {
      'text': 'Preparando interfaz',
      'duration': 3.0, // 3 segundos
    },
    {
      'text': 'Verificando conexión',
      'duration': 3.0, // 3 segundos
    },
    {
      'text': 'Finalizando',
      'duration': 3.0, // 3 segundos
    },
  ];

  @override
  void initState() {
    super.initState();
    _startLoadingProcess();
  }

  Future<void> _startLoadingProcess() async {
    double totalDuration = 0.0;
    for (var stage in _processStages) {
      totalDuration += stage['duration'] as double;
    }

    double accumulatedProgress = 0.0;

    for (int i = 0; i < _processStages.length; i++) {
      if (mounted) {
        setState(() {
          _currentMessage = _processStages[i]['text'] as String;
        });
      }

      double stageDuration = _processStages[i]['duration'] as double;
      double stageProgressIncrement = (stageDuration / totalDuration) * 100.0;

      int steps = 30; // Actualizar 30 veces por etapa para animación suave
      double stepProgress = stageProgressIncrement / steps;
      double stepDuration = stageDuration / steps;

      for (int j = 0; j < steps; j++) {
        await Future.delayed(Duration(milliseconds: (stepDuration * 1000).round()));
        if (mounted) {
          setState(() {
            accumulatedProgress += stepProgress;
            _progress = accumulatedProgress / 100.0;
          });
        }
      }
    }

    // Asegurar que llegue al 100%
    if (mounted) {
      setState(() {
        _progress = 1.0;
      });
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
              final logoSize = landscape ? 72.0 : 120.0;
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
                          if (widget.empresaLogoUrl != null &&
                              widget.empresaLogoUrl!.isNotEmpty)
                            Container(
                              width: logoSize,
                              height: logoSize,
                              margin: EdgeInsets.only(
                                bottom: landscape ? 16 : 32,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSurface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  widget.empresaLogoUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: AppColors.darkSurface,
                                      child: Center(
                                        child: Text(
                                          widget.empresaNombre?.isNotEmpty ==
                                                  true
                                              ? widget.empresaNombre![0]
                                                  .toUpperCase()
                                              : 'L',
                                          style: TextStyle(
                                            fontSize: landscape ? 28 : 48,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.header,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            )
                          else if (widget.empresaNombre != null &&
                              widget.empresaNombre!.isNotEmpty)
                            Container(
                              width: logoSize,
                              height: logoSize,
                              margin: EdgeInsets.only(
                                bottom: landscape ? 16 : 32,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkSurface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  widget.empresaNombre![0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: landscape ? 28 : 48,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.header,
                                  ),
                                ),
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
                                  color: AppColors.darkSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          SizedBox(height: landscape ? 20 : 48),
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
                                  Colors.white.withOpacity(0.2),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                AppColors.botonPrincipal,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(_progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white.withOpacity(0.8),
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

