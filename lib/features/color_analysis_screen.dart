import 'package:flutter/material.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/common.dart';

class ColorAnalysisScreen extends StatefulWidget {
  const ColorAnalysisScreen({
    super.key,
    required this.api,
    required this.onSeasonAnalyzed,
  });

  final SeamlyApi api;
  final ValueChanged<String> onSeasonAnalyzed;

  @override
  State<ColorAnalysisScreen> createState() => _ColorAnalysisScreenState();
}

class _ColorAnalysisScreenState extends State<ColorAnalysisScreen> {
  static const _skinOptions = [
    _ColorOption('Porcelain neutral', '#E8C5B0'),
    _ColorOption('Light warm', '#E0AD8B'),
    _ColorOption('Medium golden', '#C98F70'),
    _ColorOption('Medium olive', '#A97658'),
    _ColorOption('Deep warm', '#7B4B38'),
    _ColorOption('Deep cool', '#56382F'),
  ];
  static const _hairOptions = [
    _ColorOption('Soft blonde', '#C6A56C'),
    _ColorOption('Ash brown', '#76665C'),
    _ColorOption('Warm brown', '#684331'),
    _ColorOption('Deep brown', '#3D2A22'),
    _ColorOption('Soft black', '#242326'),
    _ColorOption('Silver', '#A7A7A8'),
  ];
  static const _eyeOptions = [
    _ColorOption('Light blue', '#7698B3'),
    _ColorOption('Cool gray', '#70777B'),
    _ColorOption('Green', '#65745B'),
    _ColorOption('Hazel', '#806540'),
    _ColorOption('Warm brown', '#65483A'),
    _ColorOption('Deep brown', '#2E211D'),
  ];

  _ColorOption _skin = _skinOptions[2];
  _ColorOption _hair = _hairOptions[3];
  _ColorOption _eyes = _eyeOptions[4];
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.analyzeColor(
        skinHex: _skin.hex,
        hairHex: _hair.hex,
        eyeHex: _eyes.hex,
      );
      if (!mounted) return;
      setState(() => _result = result);
      widget.onSeasonAnalyzed(result['season'] as String);
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
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageIntro(
                eyebrow: 'My colors · Step 2',
                title: 'Build a palette around your natural contrast',
                description:
                    'Choose the closest colors under indirect daylight, without a filter. The model estimates one of four styling palettes—it does not infer ethnicity, health or identity.',
              ),
              const SizedBox(height: 20),
              const NoticeCard(
                icon: Icons.light_mode_outlined,
                text:
                    'For a steadier result, compare your skin at the jaw or neck, use your natural root color, and remove colored contact lenses.',
                color: SeamlyColors.gold,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select your closest colors',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 18),
                      _SwatchSelector(
                        label: 'Skin at jaw / neck',
                        options: _skinOptions,
                        selected: _skin,
                        onChanged: (value) => setState(() => _skin = value),
                      ),
                      const SizedBox(height: 18),
                      _SwatchSelector(
                        label: 'Natural hair root',
                        options: _hairOptions,
                        selected: _hair,
                        onChanged: (value) => setState(() => _hair = value),
                      ),
                      const SizedBox(height: 18),
                      _SwatchSelector(
                        label: 'Iris color',
                        options: _eyeOptions,
                        selected: _eyes,
                        onChanged: (value) => setState(() => _eyes = value),
                      ),
                      const SizedBox(height: 24),
                      LoadingButton(
                        loading: _loading,
                        label: 'Analyze my color direction',
                        icon: Icons.palette_outlined,
                        onPressed: _analyze,
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(message: _error!),
              ],
              if (_result != null) ...[
                const SizedBox(height: 20),
                _ColorResult(result: _result!),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorOption {
  const _ColorOption(this.label, this.hex);

  final String label;
  final String hex;
}

class _SwatchSelector extends StatelessWidget {
  const _SwatchSelector({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<_ColorOption> options;
  final _ColorOption selected;
  final ValueChanged<_ColorOption> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final isSelected = option == selected;
            return Semantics(
              selected: isSelected,
              label: option.label,
              button: true,
              child: InkWell(
                onTap: () => onChanged(option),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 132,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? SeamlyColors.plum.withValues(alpha: 0.08)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSelected
                          ? SeamlyColors.plum
                          : SeamlyColors.ink.withValues(alpha: 0.11),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorFromHex(option.hex),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.label,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ColorResult extends StatelessWidget {
  const _ColorResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final palette = (result['palette'] as List).cast<String>();
    final neutrals = (result['neutrals'] as List).cast<String>();
    final metals = (result['metals'] as List).cast<String>();
    final guidance = (result['guidance'] as List).cast<String>();
    final confidence = ((result['confidence'] as num) * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR COLOR DIRECTION',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: SeamlyColors.plum,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(
                  result['season'] as String,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '$confidence% model confidence',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result['description'] as String,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _PaletteStrip(colors: palette),
            const SizedBox(height: 18),
            Text(
              'Best neutrals',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _PaletteStrip(colors: neutrals),
            const SizedBox(height: 16),
            Text(
              'Metals: ${metals.join(' · ')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...guidance.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text('•  $item'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              result['disclaimer'] as String,
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteStrip extends StatelessWidget {
  const _PaletteStrip({required this.colors});

  final List<String> colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: colors
          .map(
            (hex) => Tooltip(
              message: hex,
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colorFromHex(hex),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black12),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
