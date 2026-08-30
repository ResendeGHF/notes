// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:saber/components/home/home_toolbar_chrome.dart';
import 'package:saber/services/function_plotter.dart';

enum PlotMode {
  cartesian2d,
  polar2d,
  surface3d,
  surfaceSpherical,
  vector2d,
  vector3d,
}

class FunctionPlotterDialog extends StatefulWidget {
  const FunctionPlotterDialog({super.key, required this.onPlotGenerated});

  final void Function(Uint8List imageBytes) onPlotGenerated;

  @override
  State<FunctionPlotterDialog> createState() => _FunctionPlotterDialogState();
}

class _FunctionPlotterDialogState extends State<FunctionPlotterDialog> {
  final _functionController = TextEditingController(text: 'sin(x)');
  final _xMinController = TextEditingController(text: '-10');
  final _xMaxController = TextEditingController(text: '10');
  final _yMinController = TextEditingController(text: '-10');
  final _yMaxController = TextEditingController(text: '10');
  final _thetaMinController = TextEditingController(text: '0');
  final _thetaMaxController = TextEditingController(text: '${2 * math.pi}');
  final _phiMinController = TextEditingController(text: '0');
  final _phiMaxController = TextEditingController(text: '${2 * math.pi}');
  final _vectorFxController = TextEditingController(text: '-y');
  final _vectorFyController = TextEditingController(text: 'x');
  final _vectorFzController = TextEditingController(text: '0');
  final _zSliceController = TextEditingController(text: '0');

  PlotMode _mode = PlotMode.cartesian2d;
  bool _isPlotting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _functionController.dispose();
    _xMinController.dispose();
    _xMaxController.dispose();
    _yMinController.dispose();
    _yMaxController.dispose();
    _thetaMinController.dispose();
    _thetaMaxController.dispose();
    _phiMinController.dispose();
    _phiMaxController.dispose();
    _vectorFxController.dispose();
    _vectorFyController.dispose();
    _vectorFzController.dispose();
    _zSliceController.dispose();
    super.dispose();
  }

  Future<void> _plotFunction() async {
    if (_functionController.text.trim().isEmpty &&
        _mode == PlotMode.cartesian2d) {
      setState(() {
        _errorMessage = 'Please enter a function';
      });
      return;
    }

    setState(() {
      _isPlotting = true;
      _errorMessage = null;
    });

    try {
      Uint8List? imageBytes;

      switch (_mode) {
        case PlotMode.cartesian2d:
          {
            final xMin = double.tryParse(_xMinController.text) ?? -10;
            final xMax = double.tryParse(_xMaxController.text) ?? 10;
            String function = _functionController.text.trim().replaceAll(
              '^',
              '**',
            );
            imageBytes = await FunctionPlotter.plotFunction(
              function: function,
              xMin: xMin,
              xMax: xMax,
            );
            break;
          }
        case PlotMode.polar2d:
          {
            final thetaMin = double.tryParse(_thetaMinController.text) ?? 0;
            final thetaMax =
                double.tryParse(_thetaMaxController.text) ?? 2 * math.pi;
            String function = _functionController.text
                .trim()
                .replaceAll('^', '**')
                .replaceAll('theta', 'x');
            imageBytes = await FunctionPlotter.plotPolar(
              function: function,
              thetaMin: thetaMin,
              thetaMax: thetaMax,
            );
            break;
          }
        case PlotMode.surface3d:
          {
            final xMin = double.tryParse(_xMinController.text) ?? -5;
            final xMax = double.tryParse(_xMaxController.text) ?? 5;
            final yMin = double.tryParse(_yMinController.text) ?? -5;
            final yMax = double.tryParse(_yMaxController.text) ?? 5;
            String function = _functionController.text.trim().replaceAll(
              '^',
              '**',
            );
            imageBytes = await FunctionPlotter.plotSurface(
              function: function,
              xMin: xMin,
              xMax: xMax,
              yMin: yMin,
              yMax: yMax,
            );
            break;
          }
        case PlotMode.surfaceSpherical:
          {
            final thetaMin = double.tryParse(_thetaMinController.text) ?? 0;
            final thetaMax =
                double.tryParse(_thetaMaxController.text) ?? math.pi;
            final phiMin = double.tryParse(_phiMinController.text) ?? 0;
            final phiMax =
                double.tryParse(_phiMaxController.text) ?? 2 * math.pi;
            String function = _functionController.text
                .trim()
                .replaceAll('^', '**')
                .replaceAll('theta', 'x')
                .replaceAll('phi', 'y');
            imageBytes = await FunctionPlotter.plotSurfaceSpherical(
              function: function,
              thetaMin: thetaMin,
              thetaMax: thetaMax,
              phiMin: phiMin,
              phiMax: phiMax,
            );
            break;
          }
        case PlotMode.vector2d:
          {
            final xMin = double.tryParse(_xMinController.text) ?? -5;
            final xMax = double.tryParse(_xMaxController.text) ?? 5;
            final yMin = double.tryParse(_yMinController.text) ?? -5;
            final yMax = double.tryParse(_yMaxController.text) ?? 5;
            final fx = _vectorFxController.text.trim().replaceAll('^', '**');
            final fy = _vectorFyController.text.trim().replaceAll('^', '**');
            imageBytes = await FunctionPlotter.plotVectorField2D(
              fx: fx,
              fy: fy,
              xMin: xMin,
              xMax: xMax,
              yMin: yMin,
              yMax: yMax,
            );
            break;
          }
        case PlotMode.vector3d:
          {
            final xMin = double.tryParse(_xMinController.text) ?? -5;
            final xMax = double.tryParse(_xMaxController.text) ?? 5;
            final yMin = double.tryParse(_yMinController.text) ?? -5;
            final yMax = double.tryParse(_yMaxController.text) ?? 5;
            final z0 = double.tryParse(_zSliceController.text) ?? 0;
            final fx = _vectorFxController.text.trim().replaceAll('^', '**');
            final fy = _vectorFyController.text.trim().replaceAll('^', '**');
            final fz = _vectorFzController.text.trim().replaceAll('^', '**');
            imageBytes = await FunctionPlotter.plotVectorField3D(
              fx: fx,
              fy: fy,
              fz: fz,
              xMin: xMin,
              xMax: xMax,
              yMin: yMin,
              yMax: yMax,
              z0: z0,
            );
            break;
          }
      }

      if (imageBytes != null) {
        widget.onPlotGenerated(imageBytes);
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _errorMessage =
              'Failed to generate plot. Please check your function syntax.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPlotting = false;
        });
      }
    }
  }

  Widget _styledTextField(
    TextEditingController controller,
    String label, {
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.withOpacity(0.1),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        signed: true,
        decimal: true,
      ),
      enabled: !_isPlotting,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: RuggedDialogShell(
        maxWidth: 520,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Plot function',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '2D, 3D, polar, and vector plots rendered to the canvas.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<PlotMode>(
                  value: _mode,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.withOpacity(0.1),
                  ),
                  onChanged: _isPlotting
                      ? null
                      : (m) => setState(() => _mode = m ?? _mode),
                  items: const [
                    DropdownMenuItem(
                      value: PlotMode.cartesian2d,
                      child: Text('2D (Cartesian)'),
                    ),
                    DropdownMenuItem(
                      value: PlotMode.polar2d,
                      child: Text('2D (Polar)'),
                    ),
                    DropdownMenuItem(
                      value: PlotMode.surface3d,
                      child: Text('3D Surface (Cartesian)'),
                    ),
                    DropdownMenuItem(
                      value: PlotMode.surfaceSpherical,
                      child: Text('3D Surface (Spherical)'),
                    ),
                    DropdownMenuItem(
                      value: PlotMode.vector2d,
                      child: Text('Vector Field 2D'),
                    ),
                    DropdownMenuItem(
                      value: PlotMode.vector3d,
                      child: Text('Vector Field 3D (slice)'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _styledTextField(
                  _functionController,
                  () {
                    switch (_mode) {
                      case PlotMode.cartesian2d:
                        return 'f(x)';
                      case PlotMode.polar2d:
                        return 'r(θ)  (use x or theta)';
                      case PlotMode.surface3d:
                        return 'z = f(x,y)';
                      case PlotMode.surfaceSpherical:
                        return 'r(θ,φ)  (use theta, phi)';
                      case PlotMode.vector2d:
                      case PlotMode.vector3d:
                        return 'Scalar field';
                    }
                  }(),
                  hintText: _mode == PlotMode.surfaceSpherical
                      ? 'e.g., 2+sin(theta)*cos(phi)'
                      : 'e.g., sin(x), x^2, x^2+2*x+1',
                ),
                const SizedBox(height: 16),
                _buildRangeInputs(),
                const SizedBox(height: 8),
                _buildVectorInputs(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isPlotting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(
                        MaterialLocalizations.of(context).cancelButtonLabel,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isPlotting ? null : _plotFunction,
                      child: _isPlotting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Plot'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildRangeInputs() {
    switch (_mode) {
      case PlotMode.cartesian2d:
        return Row(
          children: [
            Expanded(child: _styledTextField(_xMinController, 'x min')),
            const SizedBox(width: 12),
            Expanded(child: _styledTextField(_xMaxController, 'x max')),
          ],
        );
      case PlotMode.polar2d:
        return Row(
          children: [
            Expanded(child: _styledTextField(_thetaMinController, 'θ min')),
            const SizedBox(width: 12),
            Expanded(child: _styledTextField(_thetaMaxController, 'θ max')),
          ],
        );
      case PlotMode.surface3d:
      case PlotMode.vector2d:
      case PlotMode.vector3d:
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _styledTextField(_xMinController, 'x min')),
                const SizedBox(width: 12),
                Expanded(child: _styledTextField(_xMaxController, 'x max')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _styledTextField(_yMinController, 'y min')),
                const SizedBox(width: 12),
                Expanded(child: _styledTextField(_yMaxController, 'y max')),
              ],
            ),
            if (_mode == PlotMode.vector3d) ...[
              const SizedBox(height: 8),
              _styledTextField(_zSliceController, 'z slice (projection)'),
            ],
          ],
        );
      case PlotMode.surfaceSpherical:
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: _styledTextField(_thetaMinController, 'θ min')),
                const SizedBox(width: 12),
                Expanded(child: _styledTextField(_thetaMaxController, 'θ max')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _styledTextField(_phiMinController, 'φ min')),
                const SizedBox(width: 12),
                Expanded(child: _styledTextField(_phiMaxController, 'φ max')),
              ],
            ),
          ],
        );
    }
  }

  Widget _buildVectorInputs() {
    if (_mode == PlotMode.vector2d) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _styledTextField(_vectorFxController, 'F_x(x,y)', hintText: '-y'),
          const SizedBox(height: 8),
          _styledTextField(_vectorFyController, 'F_y(x,y)', hintText: 'x'),
        ],
      );
    }
    if (_mode == PlotMode.vector3d) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _styledTextField(_vectorFxController, 'F_x(x,y,z)', hintText: '-y'),
          const SizedBox(height: 8),
          _styledTextField(_vectorFyController, 'F_y(x,y,z)', hintText: 'x'),
          const SizedBox(height: 8),
          _styledTextField(_vectorFzController, 'F_z(x,y,z)', hintText: '0'),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
