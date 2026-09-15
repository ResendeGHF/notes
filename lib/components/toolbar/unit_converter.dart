// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

class UnitConverter extends StatefulWidget {
  final double initialValue;
  final VoidCallback onBack;
  final VoidCallback? onClose;
  final Function(DragUpdateDetails) onDrag;

  const UnitConverter({
    super.key,
    required this.initialValue,
    required this.onBack,
    this.onClose,
    required this.onDrag,
  });

  @override
  State<UnitConverter> createState() => _UnitConverterState();
}

class _UnitConverterState extends State<UnitConverter> {
  late TextEditingController _valueCtrl;
  late _UnitCategory _selectedCategory;
  late _Unit _fromUnit;
  late _Unit _toUnit;
  String _result = '';

  @override
  void initState() {
    super.initState();
    _valueCtrl = TextEditingController(text: _formatValue(widget.initialValue));

    _selectedCategory = _categories.first;
    _fromUnit = _selectedCategory.units[0];
    _toUnit = _selectedCategory.units.length > 1
        ? _selectedCategory.units[1]
        : _selectedCategory.units[0];

    _convert();
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  String _formatValue(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  void _convert() {
    final text = _valueCtrl.text;
    if (text.isEmpty) {
      setState(() => _result = '');
      return;
    }

    final input = double.tryParse(text);
    if (input == null) {
      setState(() => _result = 'Invalid');
      return;
    }

    double output;
    if (_selectedCategory.id == 'temp') {
      output = _convertTemperature(input, _fromUnit.id, _toUnit.id);
    } else {
      output = (input * _fromUnit.factor) / _toUnit.factor;
    }

    setState(() {
      _result = _formatResult(output);
    });
  }

  String _formatResult(double v) {
    if (v.abs() < 1e-10) return '0';
    if (v.abs() > 1e10 || v.abs() < 1e-4) {
      return v.toStringAsExponential(4);
    }
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  double _convertTemperature(double value, String from, String to) {
    if (from == to) return value;
    double celsius;
    if (from == 'c')
      celsius = value;
    else if (from == 'f')
      celsius = (value - 32) * 5 / 9;
    else if (from == 'k')
      celsius = value - 273.15;
    else
      celsius = value;

    if (to == 'c') return celsius;
    if (to == 'f') return (celsius * 9 / 5) + 32;
    if (to == 'k') return celsius + 273.15;

    return celsius;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [

        GestureDetector(
          onPanUpdate: widget.onDrag,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  tooltip: 'Back to Calculator',
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Unit Converter',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose,
                    tooltip: 'Close',
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [

              _SelectorField<_UnitCategory>(
                label: 'Quantity',
                value: _selectedCategory,
                items: _categories,
                displayLabel: (c) => c.name,
                iconBuilder: (c) => c.icon,
                onChanged: (val) {
                  if (val != _selectedCategory) {
                    setState(() {
                      _selectedCategory = val;
                      _fromUnit = val.units.first;
                      _toUnit = val.units.length > 1
                          ? val.units[1]
                          : val.units.first;
                      _convert();
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: _valueCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Value',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      onChanged: (_) => _convert(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _SelectorField<_Unit>(
                      label: 'From',
                      value: _fromUnit,
                      items: _selectedCategory.units,
                      displayLabel: (u) => u.symbol,
                      onChanged: (val) {
                        setState(() {
                          _fromUnit = val;
                          _convert();
                        });
                      },
                    ),
                  ),
                ],
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Icon(Icons.arrow_downward, color: Colors.grey),
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withOpacity(
                          0.5,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _result,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: _SelectorField<_Unit>(
                      label: 'To',
                      value: _toUnit,
                      items: _selectedCategory.units,
                      displayLabel: (u) => u.symbol,
                      onChanged: (val) {
                        setState(() {
                          _toUnit = val;
                          _convert();
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Center(
                child: Text(
                  '${_fromUnit.name} ➔ ${_toUnit.name}',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectorField<T> extends StatefulWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) displayLabel;
  final IconData Function(T)? iconBuilder;
  final ValueChanged<T> onChanged;

  const _SelectorField({
    required this.label,
    required this.value,
    required this.items,
    required this.displayLabel,
    this.iconBuilder,
    required this.onChanged,
  });

  @override
  State<_SelectorField<T>> createState() => _SelectorFieldState<T>();
}

class _SelectorFieldState<T> extends State<_SelectorField<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final theme = Theme.of(context);

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [

          Positioned.fill(
            child: GestureDetector(
              onTap: _closeDropdown,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),

          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0.0, size.height + 4.0),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainer,
                shadowColor: Colors.black54,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: widget.items.map((item) {
                      final isSelected = item == widget.value;
                      return InkWell(
                        onTap: () {
                          widget.onChanged(item);
                          _closeDropdown();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          color: isSelected
                              ? theme.colorScheme.primary.withOpacity(0.1)
                              : null,
                          child: Row(
                            children: [
                              if (widget.iconBuilder != null) ...[
                                Icon(
                                  widget.iconBuilder!(item),
                                  size: 18,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurface,
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  widget.displayLabel(item),
                                  style: TextStyle(
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        onTap: _toggleDropdown,
        child: InputDecorator(
          isFocused: _isOpen,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
            suffixIcon: Icon(
              _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            ),
          ),
          child: Row(
            children: [
              if (widget.iconBuilder != null) ...[
                Icon(
                  widget.iconBuilder!(widget.value),
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.displayLabel(widget.value),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitCategory {
  final String id;
  final String name;
  final IconData icon;
  final List<_Unit> units;
  const _UnitCategory(this.id, this.name, this.icon, this.units);
}

class _Unit {
  final String id;
  final String name;
  final String symbol;
  final double factor;
  const _Unit(this.id, this.name, this.symbol, this.factor);
}

final List<_UnitCategory> _categories = [
  _UnitCategory('len', 'Length', Icons.straighten, [
    _Unit('m', 'Meter', 'm', 1.0),
    _Unit('km', 'Kilometer', 'km', 1000.0),
    _Unit('cm', 'Centimeter', 'cm', 0.01),
    _Unit('mm', 'Millimeter', 'mm', 0.001),
    _Unit('mi', 'Mile', 'mi', 1609.344),
    _Unit('yd', 'Yard', 'yd', 0.9144),
    _Unit('ft', 'Foot', 'ft', 0.3048),
    _Unit('in', 'Inch', 'in', 0.0254),
    _Unit('nm', 'Nanometer', 'nm', 1e-9),
    _Unit('au', 'Astronomical Unit', 'AU', 1.496e11),
    _Unit('ly', 'Light Year', 'ly', 9.461e15),
  ]),
  _UnitCategory('mass', 'Mass', Icons.scale, [
    _Unit('kg', 'Kilogram', 'kg', 1.0),
    _Unit('g', 'Gram', 'g', 0.001),
    _Unit('mg', 'Milligram', 'mg', 1e-6),
    _Unit('t', 'Metric Ton', 't', 1000.0),
    _Unit('lb', 'Pound', 'lb', 0.453592),
    _Unit('oz', 'Ounce', 'oz', 0.0283495),
  ]),
  _UnitCategory('time', 'Time', Icons.timer, [
    _Unit('s', 'Second', 's', 1.0),
    _Unit('ms', 'Millisecond', 'ms', 0.001),
    _Unit('min', 'Minute', 'min', 60.0),
    _Unit('h', 'Hour', 'h', 3600.0),
    _Unit('d', 'Day', 'd', 86400.0),
    _Unit('wk', 'Week', 'wk', 604800.0),
    _Unit('y', 'Year', 'yr', 31536000.0),
  ]),
  _UnitCategory('speed', 'Speed', Icons.speed, [
    _Unit('ms', 'Meters/Second', 'm/s', 1.0),
    _Unit('kmh', 'Kilometers/Hour', 'km/h', 0.277778),
    _Unit('mph', 'Miles/Hour', 'mph', 0.44704),
    _Unit('kn', 'Knot', 'kn', 0.514444),
    _Unit('c', 'Speed of Light', 'c', 299792458),
  ]),
  _UnitCategory('area', 'Area', Icons.crop_square, [
    _Unit('m2', 'Square Meter', 'm²', 1.0),
    _Unit('km2', 'Square Kilometer', 'km²', 1e6),
    _Unit('cm2', 'Square Centimeter', 'cm²', 1e-4),
    _Unit('ha', 'Hectare', 'ha', 10000.0),
    _Unit('ac', 'Acre', 'ac', 4046.86),
    _Unit('ft2', 'Square Foot', 'ft²', 0.092903),
  ]),
  _UnitCategory('vol', 'Volume', Icons.opacity, [
    _Unit('m3', 'Cubic Meter', 'm³', 1.0),
    _Unit('l', 'Liter', 'L', 0.001),
    _Unit('ml', 'Milliliter', 'mL', 1e-6),
    _Unit('gal', 'Gallon (US)', 'gal', 0.00378541),
    _Unit('floz', 'Fluid Ounce (US)', 'fl oz', 2.9574e-5),
  ]),
  _UnitCategory('temp', 'Temperature', Icons.thermostat, [
    _Unit('c', 'Celsius', '°C', 1.0),
    _Unit('f', 'Fahrenheit', '°F', 1.0),
    _Unit('k', 'Kelvin', 'K', 1.0),
  ]),
  _UnitCategory('press', 'Pressure', Icons.compress, [
    _Unit('pa', 'Pascal', 'Pa', 1.0),
    _Unit('bar', 'Bar', 'bar', 100000.0),
    _Unit('atm', 'Atmosphere', 'atm', 101325.0),
    _Unit('psi', 'PSI', 'psi', 6894.76),
    _Unit('mmhg', 'mmHg', 'mmHg', 133.322),
  ]),
  _UnitCategory('energy', 'Energy', Icons.bolt, [
    _Unit('j', 'Joule', 'J', 1.0),
    _Unit('kj', 'Kilojoule', 'kJ', 1000.0),
    _Unit('cal', 'Calorie', 'cal', 4.184),
    _Unit('kcal', 'Kilocalorie', 'kcal', 4184.0),
    _Unit('kwh', 'Kilowatt-hour', 'kWh', 3.6e6),
    _Unit('ev', 'Electronvolt', 'eV', 1.60218e-19),
  ]),
  _UnitCategory('power', 'Power', Icons.electric_bolt, [
    _Unit('w', 'Watt', 'W', 1.0),
    _Unit('kw', 'Kilowatt', 'kW', 1000.0),
    _Unit('mw', 'Megawatt', 'MW', 1e6),
    _Unit('hp', 'Horsepower', 'hp', 745.7),
  ]),
  _UnitCategory('force', 'Force', Icons.fitness_center, [
    _Unit('n', 'Newton', 'N', 1.0),
    _Unit('kn', 'Kilonewton', 'kN', 1000.0),
    _Unit('lbf', 'Pound-force', 'lbf', 4.44822),
    _Unit('dyn', 'Dyne', 'dyn', 1e-5),
  ]),
  _UnitCategory('angle', 'Angle', Icons.rotate_right, [
    _Unit('deg', 'Degree', '°', 1.0),
    _Unit('rad', 'Radian', 'rad', 57.2958),
    _Unit('grad', 'Gradian', 'grad', 0.9),
  ]),
  _UnitCategory('curr', 'Current', Icons.flash_on, [
    _Unit('a', 'Ampere', 'A', 1.0),
    _Unit('ma', 'Milliampere', 'mA', 0.001),
    _Unit('ka', 'Kiloampere', 'kA', 1000.0),
  ]),
  _UnitCategory('volt', 'Voltage', Icons.electrical_services, [
    _Unit('v', 'Volt', 'V', 1.0),
    _Unit('mv', 'Millivolt', 'mV', 0.001),
    _Unit('kv', 'Kilovolt', 'kV', 1000.0),
  ]),
];
