import 'package:flutter/material.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/common.dart';

class MeasurementsScreen extends StatefulWidget {
  const MeasurementsScreen({
    super.key,
    required this.api,
    required this.onMeasurementsSaved,
    this.referenceHeightCm,
    this.initialMeasurements,
  });

  final SeamlyApi api;

  /// Called with the submitted values and the size calculated for them.
  final Future<void> Function(Map<String, double> measurements, String size)
  onMeasurementsSaved;

  /// The account height. Saved measurements must use it, so it is shown
  /// read-only here and changed from the account screen.
  final double? referenceHeightCm;
  final Map<String, double>? initialMeasurements;

  @override
  State<MeasurementsScreen> createState() => _MeasurementsScreenState();
}

class _MeasurementsScreenState extends State<MeasurementsScreen> {
  final _formKey = GlobalKey<FormState>();
  static const _fields = [
    'height',
    'neck',
    'shoulder',
    'chest',
    'underbust',
    'waist',
    'high_hip',
    'hip',
    'sleeve',
    'wrist',
    'inseam',
  ];
  late final Map<String, TextEditingController> _controllers;
  String _fitPreference = 'regular';
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    // Start from the user's real values; never prefill sample numbers.
    _controllers = {
      for (final key in _fields)
        key: TextEditingController(text: _initialText(key)),
    };
  }

  String _initialText(String key) {
    final value = key == 'height' && widget.referenceHeightCm != null
        ? widget.referenceHeightCm
        : widget.initialMeasurements?[key];
    return value?.toStringAsFixed(1) ?? '';
  }

  @override
  void didUpdateWidget(covariant MeasurementsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialMeasurements, widget.initialMeasurements) &&
        widget.initialMeasurements != null) {
      for (final key in _fields) {
        _controllers[key]!.text = _initialText(key);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final measurements = <String, double>{};
    for (final entry in _controllers.entries) {
      final value = double.tryParse(entry.value.text.trim());
      if (value != null) measurements[entry.key] = value;
    }
    try {
      final result = await widget.api.recommendSize(
        measurements: measurements,
        fitPreference: _fitPreference,
      );
      if (!mounted) return;
      setState(() => _result = result);
      await widget.onMeasurementsSaved(
        measurements,
        result['recommended_size'] as String,
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageIntro(
                eyebrow: 'My fit · Step 1',
                title: 'Measurements that fashion actually uses',
                description:
                    'Use a soft tape over close-fitting clothing. Keep it level and comfortably snug—never pull it tight. All values are in centimetres.',
              ),
              const SizedBox(height: 20),
              const NoticeCard(
                icon: Icons.photo_camera_outlined,
                text:
                    'Values from AI body scan appear here automatically. Check every estimate with a soft tape before relying on it for a purchase or alteration.',
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Body profile',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Required fields are marked with an asterisk. Optional measurements improve garment-specific guidance.',
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            _MeasurementField(
                              label: 'Height *',
                              helper: 'Floor to crown',
                              controller: _controllers['height']!,
                              isRequired: true,
                              readOnly: widget.referenceHeightCm != null,
                              min: 120,
                              max: 230,
                            ),
                            _MeasurementField(
                              label: 'Neck',
                              helper: 'Base of neck',
                              controller: _controllers['neck']!,
                              min: 20,
                              max: 70,
                            ),
                            _MeasurementField(
                              label: 'Shoulder',
                              helper: 'Point to point',
                              controller: _controllers['shoulder']!,
                              min: 25,
                              max: 75,
                            ),
                            _MeasurementField(
                              label: 'Chest / bust *',
                              helper: 'Fullest point',
                              controller: _controllers['chest']!,
                              isRequired: true,
                              min: 55,
                              max: 190,
                            ),
                            _MeasurementField(
                              label: 'Underbust',
                              helper: 'Directly below bust',
                              controller: _controllers['underbust']!,
                              min: 50,
                              max: 170,
                            ),
                            _MeasurementField(
                              label: 'Natural waist *',
                              helper: 'Narrowest torso point',
                              controller: _controllers['waist']!,
                              isRequired: true,
                              min: 45,
                              max: 190,
                            ),
                            _MeasurementField(
                              label: 'High hip',
                              helper: 'Upper hip / abdomen',
                              controller: _controllers['high_hip']!,
                              min: 55,
                              max: 200,
                            ),
                            _MeasurementField(
                              label: 'Full hip *',
                              helper: 'Fullest seat point',
                              controller: _controllers['hip']!,
                              isRequired: true,
                              min: 60,
                              max: 210,
                            ),
                            _MeasurementField(
                              label: 'Sleeve',
                              helper: 'Shoulder to wrist',
                              controller: _controllers['sleeve']!,
                              min: 35,
                              max: 90,
                            ),
                            _MeasurementField(
                              label: 'Wrist',
                              helper: 'Around wrist bone',
                              controller: _controllers['wrist']!,
                              min: 10,
                              max: 35,
                            ),
                            _MeasurementField(
                              label: 'Inseam',
                              helper: 'Crotch to ankle',
                              controller: _controllers['inseam']!,
                              min: 45,
                              max: 110,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Fit preference',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 'close', label: Text('Close')),
                            ButtonSegment(
                              value: 'regular',
                              label: Text('Regular'),
                            ),
                            ButtonSegment(
                              value: 'relaxed',
                              label: Text('Relaxed'),
                            ),
                          ],
                          selected: {_fitPreference},
                          onSelectionChanged: (value) =>
                              setState(() => _fitPreference = value.first),
                        ),
                        const SizedBox(height: 24),
                        LoadingButton(
                          loading: _loading,
                          label: 'Save and recommend my size',
                          icon: Icons.straighten,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: _error!),
              ],
              if (_result != null) ...[
                const SizedBox(height: 20),
                _SizeResult(result: _result!),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeasurementField extends StatelessWidget {
  const _MeasurementField({
    required this.label,
    required this.helper,
    required this.controller,
    required this.min,
    required this.max,
    this.isRequired = false,
    this.readOnly = false,
  });

  final String label;
  final String helper;
  final TextEditingController controller;
  final double min;
  final double max;
  final bool isRequired;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: readOnly ? 'From your profile' : helper,
          suffixText: 'cm',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return isRequired ? 'Required' : null;
          }
          final parsed = double.tryParse(value);
          if (parsed == null) return 'Enter a number';
          if (parsed < min || parsed > max) {
            return 'Expected ${min.round()}–${max.round()} cm';
          }
          return null;
        },
      ),
    );
  }
}

class _SizeResult extends StatelessWidget {
  const _SizeResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final confidence = ((result['confidence'] as num) * 100).round();
    final alternatives = (result['alternatives'] as List)
        .cast<Map<String, dynamic>>();
    final notes = (result['fit_notes'] as List).cast<String>();
    return Card(
      color: SeamlyColors.ink,
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YOUR STARTING SIZE',
              style: TextStyle(
                color: Color(0xFFE6B1C5),
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  result['recommended_size'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '$confidence% model confidence',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: alternatives.map((item) {
                final probability = ((item['probability'] as num) * 100)
                    .round();
                return Chip(label: Text('${item['label']} · $probability%'));
              }).toList(),
            ),
            const SizedBox(height: 18),
            ...notes.map(
              (note) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.check,
                        color: Color(0xFFE6B1C5),
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result['disclaimer'] as String,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
