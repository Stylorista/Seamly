import 'package:flutter/material.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/common.dart';

class SeasonStyleScreen extends StatefulWidget {
  const SeasonStyleScreen({
    super.key,
    required this.api,
    required this.sizeLabel,
    required this.colorSeason,
  });

  final SeamlyApi api;
  final String? sizeLabel;
  final String? colorSeason;

  @override
  State<SeasonStyleScreen> createState() => _SeasonStyleScreenState();
}

class _SeasonStyleScreenState extends State<SeasonStyleScreen> {
  String _climate = 'tropical';
  String _hemisphere = 'northern';
  String _occasion = 'everyday';
  String _style = 'minimal';
  String _fallbackColorSeason = 'Autumn';
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  Future<void> _recommend() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.recommendStyle(
        climate: _climate,
        hemisphere: _hemisphere,
        month: DateTime.now().month,
        occasion: _occasion,
        style: _style,
        colorSeason: widget.colorSeason ?? _fallbackColorSeason,
        sizeLabel: widget.sizeLabel,
      );
      if (mounted) setState(() => _result = result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColorSeason = widget.colorSeason ?? _fallbackColorSeason;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PageIntro(
                eyebrow: 'Seasonal style · Step 3',
                title:
                    'Dress for the climate you live in—not a generic calendar',
                description:
                    'Seamly distinguishes tropical wet/dry cycles, arid heat and four-season climates, then matches the result to occasion and style.',
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        runSpacing: 4,
                        spacing: 16,
                        children: [
                          Text(
                            'Today’s context',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            _formatDate(DateTime.now()),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          _SelectField(
                            label: 'Climate',
                            value: _climate,
                            options: const {
                              'tropical': 'Tropical',
                              'temperate': 'Four-season',
                              'arid': 'Arid',
                              'cold': 'Cold',
                            },
                            onChanged: (value) =>
                                setState(() => _climate = value),
                          ),
                          _SelectField(
                            label: 'Hemisphere',
                            value: _hemisphere,
                            options: const {
                              'northern': 'Northern',
                              'southern': 'Southern',
                            },
                            onChanged: (value) =>
                                setState(() => _hemisphere = value),
                          ),
                          _SelectField(
                            label: 'Occasion',
                            value: _occasion,
                            options: const {
                              'everyday': 'Everyday',
                              'work': 'Work',
                              'event': 'Event',
                              'travel': 'Travel',
                            },
                            onChanged: (value) =>
                                setState(() => _occasion = value),
                          ),
                          _SelectField(
                            label: 'Style direction',
                            value: _style,
                            options: const {
                              'minimal': 'Minimal',
                              'classic': 'Classic',
                              'street': 'Street',
                              'romantic': 'Romantic',
                            },
                            onChanged: (value) =>
                                setState(() => _style = value),
                          ),
                          if (widget.colorSeason == null)
                            _SelectField(
                              label: 'Color profile',
                              value: _fallbackColorSeason,
                              options: const {
                                'Spring': 'Spring',
                                'Summer': 'Summer',
                                'Autumn': 'Autumn',
                                'Winter': 'Winter',
                              },
                              onChanged: (value) =>
                                  setState(() => _fallbackColorSeason = value),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Chip(
                            avatar: const Icon(
                              Icons.palette_outlined,
                              size: 18,
                            ),
                            label: Text('$activeColorSeason palette'),
                          ),
                          Chip(
                            avatar: const Icon(Icons.straighten, size: 18),
                            label: Text(
                              widget.sizeLabel == null
                                  ? 'Size profile not set'
                                  : 'Starting size ${widget.sizeLabel}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      LoadingButton(
                        loading: _loading,
                        label: 'Style me for now',
                        icon: Icons.checkroom_outlined,
                        onPressed: _recommend,
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
                _StyleResult(result: _result!),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options.entries
            .map(
              (entry) => DropdownMenuItem(
                value: entry.key,
                child: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (newValue) {
          if (newValue != null) onChanged(newValue);
        },
      ),
    );
  }
}

class _StyleResult extends StatelessWidget {
  const _StyleResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final pieces = (result['pieces'] as List).cast<String>();
    final fabrics = (result['fabrics'] as List).cast<String>();
    final palette = (result['palette'] as List).cast<String>();
    final notes = (result['styling_notes'] as List).cast<String>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [SeamlyColors.moss, Color(0xFF34432F)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result['current_season']} SEASON EDIT',
                  style: const TextStyle(
                    color: Color(0xFFD9E6CE),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  result['title'] as String,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  result['summary'] as String,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The outfit system',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: pieces
                      .asMap()
                      .entries
                      .map(
                        (entry) => Chip(
                          avatar: CircleAvatar(
                            backgroundColor: SeamlyColors.plum,
                            foregroundColor: Colors.white,
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          label: Text(entry.value),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                Text(
                  'Recommended fabrics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(fabrics.join(' · ')),
                const SizedBox(height: 22),
                Text(
                  'Color edit',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  children: palette
                      .map(
                        (hex) => Tooltip(
                          message: hex,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: colorFromHex(hex),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.black12),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 22),
                ...notes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.arrow_right,
                          color: SeamlyColors.moss,
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: Text(note)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
