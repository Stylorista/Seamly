import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../widgets/seamly_header.dart';
import 'package:image_picker/image_picker.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.api,
    required this.sizeLabel,
    required this.colorSeason,
    required this.onOpenFit,
    required this.onOpenWeather,
    required this.onOpenColorAnalysis,
    required this.onColorSeasonAnalyzed,
    this.onOpenAccount,
    this.showHeader = true,
    this.avatarBase64,
  });

  final SeamlyApi api;
  final String? sizeLabel;
  final String? colorSeason;
  final VoidCallback onOpenFit;
  final VoidCallback onOpenWeather;
  final VoidCallback onOpenColorAnalysis;
  final ValueChanged<String> onColorSeasonAnalyzed;
  final VoidCallback? onOpenAccount;
  final bool showHeader;
  final String? avatarBase64;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _portraitBytes;
  Map<String, dynamic>? _analysis;
  String? _error;
  bool _analyzing = false;

  Future<void> _startAccessoryAnalysis() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PhotoConsentSheet(),
    );
    if (source == null || !mounted) return;

    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1600,
      );
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _portraitBytes = bytes;
        _analysis = null;
        _error = null;
        _analyzing = true;
      });
      final result = await widget.api.analyzeAppearancePhoto(imageBytes: bytes);
      if (!mounted) return;
      setState(() => _analysis = result);
      widget.onColorSeasonAnalyzed(result['color_season'] as String);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(() {
          _error =
              'The camera or photo could not be opened. Try choosing an existing portrait.';
        });
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SeamlyColors.cream,
      child: CustomScrollView(
        key: const ValueKey('profile-hub'),
        slivers: [
          if (widget.showHeader)
            SliverToBoxAdapter(
              child: SeamlyHeader(
                onOpenAccount: widget.onOpenAccount,
                avatarBase64: widget.avatarBase64,
              ),
            ),
          SliverToBoxAdapter(
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 172,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFFDFCFB),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
                    child: Column(
                      children: [
                        Card(
                          key: const ValueKey('profile-style-snapshot'),
                          color: const Color(0xFF513225),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Color(0xFFFFC98C),
                                  size: 30,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Your style snapshot',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        widget.sizeLabel == null &&
                                                widget.colorSeason == null
                                            ? 'Scan once to unlock fit, color, and weather-aware suggestions.'
                                            : '${widget.sizeLabel ?? 'Fit not set'} · ${widget.colorSeason ?? 'Color not set'}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Update style snapshot',
                                  onPressed: widget.onOpenFit,
                                  color: Colors.white,
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final desktop = constraints.maxWidth >= 650;
                            final narrow = constraints.maxWidth < 300 ||
                                MediaQuery.textScalerOf(context).scale(16) > 24;
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: narrow ? 1 : desktop ? 4 : 2,
                              crossAxisSpacing: desktop ? 20 : 30,
                              mainAxisSpacing: 22,
                              childAspectRatio: narrow ? 0.95 : desktop ? 0.66 : 0.61,
                              children: [
                                _ProfileFeatureCard(
                                  key: const ValueKey('profile-fit'),
                                  title: 'Will it Fit?',
                                  description: widget.sizeLabel == null
                                      ? 'See if an item matches your size!'
                                      : 'Your starting size is ${widget.sizeLabel}.',
                                  badgeIcon: Icons.photo_camera_outlined,
                                  visual: const _PhotoVisual(
                                    asset: 'assets/images/partner_collage.png',
                                    alignment: Alignment.topLeft,
                                  ),
                                  onTap: widget.onOpenFit,
                                ),
                                _ProfileFeatureCard(
                                  key: const ValueKey('profile-weather'),
                                  title: 'In-the-Weather',
                                  description:
                                      'Find an outfit for today’s climate.',
                                  badgeIcon: Icons.photo_camera_outlined,
                                  visual: const _PhotoVisual(
                                    asset: 'assets/images/home_hero.png',
                                    alignment: Alignment.centerRight,
                                  ),
                                  onTap: widget.onOpenWeather,
                                ),
                                _ProfileFeatureCard(
                                  key: const ValueKey('profile-accessories'),
                                  title: 'Accessories',
                                  description: _analysis == null
                                      ? 'Take a selfie to accessorize your OOTD!'
                                      : 'Your accessory edit is ready.',
                                  badgeIcon: _analysis == null
                                      ? Icons.add_rounded
                                      : Icons.check_rounded,
                                  visual: _portraitBytes == null
                                      ? const _PhotoVisual(
                                          asset:
                                              'assets/images/partner_collage.png',
                                          alignment: Alignment.bottomRight,
                                        )
                                      : Image.memory(
                                          _portraitBytes!,
                                          fit: BoxFit.cover,
                                          alignment: Alignment.topCenter,
                                        ),
                                  onTap: _startAccessoryAnalysis,
                                ),
                                _ProfileFeatureCard(
                                  key: const ValueKey('profile-colors'),
                                  title: 'Color Analysis',
                                  description: widget.colorSeason == null
                                      ? 'Colors that fit your complexion.'
                                      : '${widget.colorSeason} colors are saved.',
                                  badgeIcon: Icons.arrow_forward_rounded,
                                  visual: const _ColorFanVisual(),
                                  onTap: widget.onOpenColorAnalysis,
                                ),
                              ],
                            );
                          },
                        ),
                        if (_analyzing) ...[
                          const SizedBox(height: 24),
                          const _AnalyzingCard(),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 20),
                          ErrorBanner(message: _error!),
                        ],
                        if (_analysis != null && !_analyzing) ...[
                          const SizedBox(height: 24),
                          _AccessoryResult(result: _analysis!),
                        ],
                      ],
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

class _ProfileFeatureCard extends StatelessWidget {
  const _ProfileFeatureCard({
    super.key,
    required this.title,
    required this.description,
    required this.badgeIcon,
    required this.visual,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData badgeIcon;
  final Widget visual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title. $description',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: visual,
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        width: 41,
                        height: 41,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          badgeIcon,
                          color: SeamlyColors.sandText,
                          size: 27,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoVisual extends StatelessWidget {
  const _PhotoVisual({required this.asset, required this.alignment});

  final String asset;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(asset, fit: BoxFit.cover, alignment: alignment);
  }
}

class _ColorFanVisual extends StatelessWidget {
  const _ColorFanVisual();

  static const _colors = [
    Color(0xFFE14D63),
    Color(0xFFF18A4B),
    Color(0xFFE9C84A),
    Color(0xFF6CAC67),
    Color(0xFF55A7AC),
    Color(0xFF4B70B6),
    Color(0xFF8B5AA9),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFDDE1DE),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final swatchWidth = constraints.maxWidth / 4.3;
          return Stack(
            children: [
              for (var index = 0; index < _colors.length; index++)
                Positioned(
                  left: 12 + index * ((constraints.maxWidth - 38) / 8.2),
                  top: 28 + (index.isEven ? 7 : 0),
                  width: swatchWidth,
                  bottom: 13,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _colors[index],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoConsentSheet extends StatefulWidget {
  const _PhotoConsentSheet();

  @override
  State<_PhotoConsentSheet> createState() => _PhotoConsentSheetState();
}

class _PhotoConsentSheetState extends State<_PhotoConsentSheet> {
  bool _consented = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(26),
            topRight: Radius.circular(26),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Create my accessory edit',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use a clear portrait in indirect daylight. The photo is sent to your configured Seamly API, analyzed in memory, and not stored.',
              style: TextStyle(height: 1.4, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consented,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I consent to this photo being processed for aesthetic color and accessory suggestions.',
                style: TextStyle(fontSize: 13),
              ),
              onChanged: (value) => setState(() => _consented = value ?? false),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _consented
                        ? () => Navigator.pop(context, ImageSource.gallery)
                        : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choose photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _consented
                        ? () => Navigator.pop(context, ImageSource.camera)
                        : null,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Take selfie'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyzingCard extends StatelessWidget {
  const _AnalyzingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Creating your complexion palette and accessory edit…',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessoryResult extends StatelessWidget {
  const _AccessoryResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final accessories = (result['accessories'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final palette = (result['palette'] as List<dynamic>).cast<String>();
    final confidence = ((result['confidence'] as num) * 100).round();
    return Card(
      color: const Color(0xFFF7EFE8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: SeamlyColors.sandText,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Your ${result['color_season']} accessory edit',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${result['complexion_direction']} · $confidence% visual confidence',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in palette.take(5))
                  Tooltip(
                    message: hex,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: colorFromHex(hex),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 17),
            for (final item in accessories)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.add_circle, size: 19),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${item['name']}\n',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            TextSpan(
                              text: item['reason'] as String,
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            Text(
              result['disclaimer'] as String,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
