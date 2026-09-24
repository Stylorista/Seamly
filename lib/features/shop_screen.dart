import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({
    super.key,
    required this.api,
    required this.measurements,
    required this.sizeLabel,
    required this.colorSeason,
    required this.onOpenScanner,
    required this.onOpenMeasurements,
  });

  final SeamlyApi api;
  final Map<String, double>? measurements;
  final String? sizeLabel;
  final String? colorSeason;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenMeasurements;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String _query = '';
  String _category = 'All';
  bool _loading = true;
  String? _loadError;
  String _disclosure = '';
  List<_ShopProduct> _products = const [];
  List<_SourceStatus> _sources = const [];

  static const _categories = [
    'All',
    'Tops',
    'Bottoms',
    'Dresses',
    'Outerwear',
    'Accessories',
  ];

  static const _searchIdeas = [
    _SearchIdea(
      title: 'Relaxed linen blouse',
      category: 'Tops',
      searchTerms: 'women relaxed linen blouse',
      fitReason: 'Easy shoulder and sleeve fit',
      icon: Icons.checkroom_rounded,
    ),
    _SearchIdea(
      title: 'High-rise wide-leg trousers',
      category: 'Bottoms',
      searchTerms: 'women high waist wide leg trousers',
      fitReason: 'Waist-to-hip friendly cut',
      icon: Icons.dry_cleaning_rounded,
    ),
    _SearchIdea(
      title: 'Adjustable wrap midi dress',
      category: 'Dresses',
      searchTerms: 'women adjustable wrap midi dress',
      fitReason: 'Adjustable natural waist',
      icon: Icons.woman_2_rounded,
    ),
    _SearchIdea(
      title: 'Lightweight tailored blazer',
      category: 'Outerwear',
      searchTerms: 'women lightweight tailored blazer',
      fitReason: 'Balanced shoulder structure',
      icon: Icons.business_center_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final payload = await widget.api.fetchShopProducts();
      final products = (payload['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_ShopProduct.fromJson)
          .toList();
      final sources = (payload['sources'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_SourceStatus.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _products = products;
        _sources = sources;
        _disclosure = payload['disclosure']?.toString() ?? '';
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message;
        _loading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loadError = 'The source-linked product feed could not be loaded.';
        _loading = false;
      });
    }
  }

  bool get _hasProfile =>
      widget.measurements != null ||
      (widget.sizeLabel != null && widget.sizeLabel!.trim().isNotEmpty);

  String get _recommendedSize {
    final savedSize = widget.sizeLabel?.trim();
    if (savedSize != null && savedSize.isNotEmpty) return savedSize;
    final values = widget.measurements;
    if (values == null) return '—';
    final chest = values['chest'] ?? 0;
    final hip = values['hip'] ?? 0;
    final largest = chest > hip ? chest : hip;
    if (largest < 84) return 'XS';
    if (largest < 92) return 'S';
    if (largest < 100) return 'M';
    if (largest < 110) return 'L';
    if (largest < 120) return 'XL';
    return '2XL';
  }

  String get _colorCue {
    final season = widget.colorSeason?.toLowerCase();
    if (season == null || season.isEmpty) return 'neutral colors';
    if (season.contains('spring')) return 'warm spring colors';
    if (season.contains('summer')) return 'soft summer colors';
    if (season.contains('autumn')) return 'earthy autumn colors';
    if (season.contains('winter')) return 'clear winter colors';
    return '$season colors';
  }

  List<_ShopProduct> get _visibleProducts {
    final normalized = _query.trim().toLowerCase();
    final items = _products.where((item) {
      final categoryMatches = _category == 'All' || item.category == _category;
      final queryMatches =
          normalized.isEmpty ||
          item.title.toLowerCase().contains(normalized) ||
          item.marketplace.toLowerCase().contains(normalized) ||
          (item.seller?.toLowerCase().contains(normalized) ?? false);
      return categoryMatches && queryMatches;
    }).toList();
    items.sort((left, right) => _fitScore(right).compareTo(_fitScore(left)));
    return items;
  }

  List<_SearchIdea> get _visibleSearchIdeas {
    final normalized = _query.trim().toLowerCase();
    return _searchIdeas.where((item) {
      final categoryMatches = _category == 'All' || item.category == _category;
      final queryMatches =
          normalized.isEmpty ||
          item.title.toLowerCase().contains(normalized) ||
          item.category.toLowerCase().contains(normalized);
      return categoryMatches && queryMatches;
    }).toList();
  }

  int _fitScore(_ShopProduct item) {
    var score = 0;
    if (_hasProfile && item.sizes.contains(_recommendedSize.toUpperCase())) {
      score += 8;
    }
    final season = widget.colorSeason;
    if (season != null && item.colorSeasons.contains(season)) score += 5;
    final measurements = widget.measurements;
    if (measurements != null) {
      final chest = measurements['chest'] ?? 0;
      final waist = measurements['waist'] ?? 0;
      final hip = measurements['hip'] ?? 0;
      if ((hip - waist).abs() > 14 && item.category == 'Dresses') score += 3;
      if (hip > chest * 1.06 && item.category == 'Tops') score += 2;
      if (chest > hip * 1.06 && item.category == 'Bottoms') score += 2;
    }
    return score;
  }

  Future<void> _openUrl(Uri uri, {required String errorMessage}) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) _showLinkError(errorMessage);
    } on Exception {
      if (mounted) _showLinkError(errorMessage);
    }
  }

  Future<void> _openProduct(_ShopProduct item) {
    return _openUrl(
      Uri.parse(item.productUrl),
      errorMessage:
          'The exact ${item.marketplace} listing could not be opened.',
    );
  }

  Future<void> _openMarketplace(_Marketplace marketplace, _SearchIdea item) {
    final sizeTerm = _hasProfile ? ' size $_recommendedSize' : '';
    final query = '${item.searchTerms}$sizeTerm $_colorCue philippines';
    final uri = switch (marketplace) {
      _Marketplace.shopee => Uri.https('shopee.ph', '/search', {
        'keyword': query,
      }),
      _Marketplace.lazada => Uri.https('www.lazada.com.ph', '/catalog/', {
        'q': query,
      }),
      _Marketplace.temu => Uri.https('www.temu.com', '/search_result.html', {
        'search_key': query,
      }),
    };
    return _openUrl(
      uri,
      errorMessage: 'The marketplace search could not be opened.',
    );
  }

  void _showLinkError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    final searchIdeas = _visibleSearchIdeas;
    return Material(
      color: const Color(0xFFF7F4EF),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _ShopHeader(
              onSearchChanged: (value) => setState(() => _query = value),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _AiFitBanner(
                hasProfile: _hasProfile,
                size: _recommendedSize,
                measurements: widget.measurements,
                colorSeason: widget.colorSeason,
                onOpenScanner: widget.onOpenScanner,
                onOpenMeasurements: widget.onOpenMeasurements,
              ),
            ),
          ),
          if (_sources.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _SourceStrip(sources: _sources),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 72,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = _category == category;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) => setState(() => _category = category),
                    selectedColor: SeamlyColors.sand,
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : SeamlyColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide(
                      color: SeamlyColors.sand.withValues(alpha: 0.35),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_loading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 30),
              sliver: SliverToBoxAdapter(child: _LoadingCatalog()),
            )
          else ...[
            if (_loadError != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                sliver: SliverToBoxAdapter(
                  child: _CatalogNotice(
                    message: _loadError!,
                    onRetry: _loadProducts,
                  ),
                ),
              ),
            if (_products.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: _SectionHeading(
                    title: 'Source-linked picks',
                    detail: '${products.length} exact listings',
                  ),
                ),
              ),
              if (products.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, 26, 20, 38),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Text('No source-linked matches found.'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent >= 920
                          ? 4
                          : constraints.crossAxisExtent >= 620
                          ? 3
                          : 2;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 11,
                          mainAxisSpacing: 12,
                          childAspectRatio: columns == 2 ? 0.56 : 0.62,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final item = products[index];
                          return _ProductCard(
                            item: item,
                            size: _recommendedSize,
                            hasProfile: _hasProfile,
                            colorSeason: widget.colorSeason,
                            onOpen: () => _openProduct(item),
                          );
                        }, childCount: products.length),
                      );
                    },
                  ),
                ),
            ] else if (_loadError == null)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 18),
                sliver: SliverToBoxAdapter(child: _CatalogSetupNotice()),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _SectionHeading(
                  title: _products.isEmpty
                      ? 'Search current marketplaces'
                      : 'Explore more styles',
                  detail: 'Search results, not product listings',
                ),
              ),
            ),
            if (searchIdeas.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 36),
                sliver: SliverToBoxAdapter(
                  child: Center(child: Text('No style searches found.')),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                sliver: SliverList.separated(
                  itemCount: searchIdeas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = searchIdeas[index];
                    return _SearchIdeaCard(
                      item: item,
                      size: _recommendedSize,
                      hasProfile: _hasProfile,
                      onShopee: () =>
                          _openMarketplace(_Marketplace.shopee, item),
                      onLazada: () =>
                          _openMarketplace(_Marketplace.lazada, item),
                      onTemu: () => _openMarketplace(_Marketplace.temu, item),
                    );
                  },
                ),
              ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
            sliver: SliverToBoxAdapter(
              child: Text(
                _disclosure.isNotEmpty
                    ? '$_disclosure Always confirm the seller’s price, stock, return policy, and size chart.'
                    : 'Product photos appear only when Seamly receives the exact image and listing link from an approved source feed. Search cards contain no borrowed product photos.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.onSearchChanged});

  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SeamlyColors.cream,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_bag_rounded, color: SeamlyColors.plum, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shop',
                  style: TextStyle(
                    color: SeamlyColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    'FROM THE SOURCE',
                    style: TextStyle(
                      color: SeamlyColors.plum,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('shop-search'),
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search products, sellers, or sources',
              prefixIcon: const Icon(Icons.search_rounded),
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiFitBanner extends StatelessWidget {
  const _AiFitBanner({
    required this.hasProfile,
    required this.size,
    required this.measurements,
    required this.colorSeason,
    required this.onOpenScanner,
    required this.onOpenMeasurements,
  });

  final bool hasProfile;
  final String size;
  final Map<String, double>? measurements;
  final String? colorSeason;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenMeasurements;

  @override
  Widget build(BuildContext context) {
    final waist = measurements?['waist'];
    final hip = measurements?['hip'];
    final profileDetails = waist != null && hip != null
        ? 'Waist ${waist.toStringAsFixed(0)} cm  •  Hip ${hip.toStringAsFixed(0)} cm'
        : 'Add measurements for more accurate ranking';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF573326), Color(0xFF8A5A40)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white,
                child: Icon(
                  hasProfile
                      ? Icons.auto_awesome_rounded
                      : Icons.photo_camera_rounded,
                  color: SeamlyColors.sandText,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasProfile
                          ? 'Your AI fit ranking is ready'
                          : 'Unlock AI fit ranking',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasProfile
                          ? 'Suggested size $size  •  ${colorSeason ?? 'Color profile not set'}\n$profileDetails\nExact listings rank higher when their source data includes your size and palette.'
                          : 'Add a body profile so Seamly can rank source-linked listings for your proportions and palette.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('shop-open-scan'),
                  onPressed: onOpenScanner,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF573326),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.photo_camera_outlined, size: 19),
                  label: Text(hasProfile ? 'Update scan' : 'Take photo'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenMeasurements,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white60),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.straighten_rounded, size: 19),
                  label: const Text('Measurements'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceStrip extends StatelessWidget {
  const _SourceStrip({required this.sources});

  final List<_SourceStatus> sources;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DED5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_outlined, size: 18, color: Color(0xFF2E7D32)),
              SizedBox(width: 7),
              Text(
                'Product source status',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: sources.map((source) {
              return Tooltip(
                message: source.note,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: source.connected
                        ? const Color(0xFFEAF5EC)
                        : const Color(0xFFF2EFEB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        source.connected
                            ? Icons.check_circle_rounded
                            : Icons.link_off_rounded,
                        size: 14,
                        color: source.connected
                            ? const Color(0xFF2E7D32)
                            : Colors.black45,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        source.connected
                            ? '${source.name} ${source.itemCount}'
                            : source.name,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.item,
    required this.size,
    required this.hasProfile,
    required this.colorSeason,
    required this.onOpen,
  });

  final _ShopProduct item;
  final String size;
  final bool hasProfile;
  final String? colorSeason;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final sizeMatch = hasProfile && item.sizes.contains(size.toUpperCase());
    final colorMatch =
        colorSeason != null && item.colorSeasons.contains(colorSeason);
    return Material(
      key: ValueKey('shop-product-${item.id}'),
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 54,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  semanticLabel:
                      '${item.title} product photo from ${item.marketplace}',
                  errorBuilder: (_, _, _) => const _ImageUnavailable(),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _SourceBadge(marketplace: item.marketplace),
                ),
                if (sizeMatch || colorMatch)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF513225).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Text(
                          sizeMatch
                              ? 'For your size $size'
                              : '$colorSeason palette',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 46,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.seller != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.seller!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    item.priceLabel ?? 'See current price',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF573326),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Row(
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 13,
                        color: Colors.black45,
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Photo from exact listing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: FilledButton.icon(
                      onPressed: onOpen,
                      style: FilledButton.styleFrom(
                        backgroundColor: _marketColor(item.marketplace),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text(
                        'Open exact listing',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchIdeaCard extends StatelessWidget {
  const _SearchIdeaCard({
    required this.item,
    required this.size,
    required this.hasProfile,
    required this.onShopee,
    required this.onLazada,
    required this.onTemu,
  });

  final _SearchIdea item;
  final String size;
  final bool hasProfile;
  final VoidCallback onShopee;
  final VoidCallback onLazada;
  final VoidCallback onTemu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5DED5)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFF0E7DE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: SeamlyColors.sandText, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasProfile
                      ? '${item.fitReason} • Search size $size'
                      : item.fitReason,
                  style: const TextStyle(color: Colors.black54, fontSize: 10.5),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _MarketButton(
                        label: 'Shopee',
                        color: _marketColor('Shopee'),
                        onPressed: onShopee,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MarketButton(
                        label: 'Lazada',
                        color: _marketColor('Lazada'),
                        onPressed: onLazada,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _MarketButton(
                        label: 'Temu',
                        color: _marketColor('Temu'),
                        onPressed: onTemu,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketButton extends StatelessWidget {
  const _MarketButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFECE7E1),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.black38, size: 34),
            SizedBox(height: 6),
            Text(
              'Source image unavailable',
              style: TextStyle(color: Colors.black45, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.marketplace});

  final String marketplace;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _marketColor(marketplace).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_rounded, color: Colors.white, size: 12),
            const SizedBox(width: 4),
            Text(
              marketplace,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCatalog extends StatelessWidget {
  const _LoadingCatalog();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 130,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading source-linked products…'),
          ],
        ),
      ),
    );
  }
}

class _CatalogNotice extends StatelessWidget {
  const _CatalogNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2DF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFF8A5A40)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CatalogSetupNotice extends StatelessWidget {
  const _CatalogSetupNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC5DDC9)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: Color(0xFF2E7D32)),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for approved product sources',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'Seamly will not fill this space with unrelated photos. Exact product images, titles, and links appear after a seller or affiliate feed is connected.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            detail,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.black54, fontSize: 10.5),
          ),
        ),
      ],
    );
  }
}

class _ShopProduct {
  const _ShopProduct({
    required this.id,
    required this.title,
    required this.category,
    required this.marketplace,
    required this.seller,
    required this.productUrl,
    required this.imageUrl,
    required this.priceLabel,
    required this.sizes,
    required this.colorSeasons,
  });

  factory _ShopProduct.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList();
    return _ShopProduct(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled product',
      category: json['category']?.toString() ?? 'Accessories',
      marketplace: json['marketplace']?.toString() ?? 'Marketplace',
      seller: json['seller']?.toString(),
      productUrl: json['product_url']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      priceLabel: json['price_label']?.toString(),
      sizes: strings('sizes').map((value) => value.toUpperCase()).toList(),
      colorSeasons: strings('color_seasons'),
    );
  }

  final String id;
  final String title;
  final String category;
  final String marketplace;
  final String? seller;
  final String productUrl;
  final String imageUrl;
  final String? priceLabel;
  final List<String> sizes;
  final List<String> colorSeasons;
}

class _SourceStatus {
  const _SourceStatus({
    required this.name,
    required this.connected,
    required this.itemCount,
    required this.note,
  });

  factory _SourceStatus.fromJson(Map<String, dynamic> json) {
    return _SourceStatus(
      name: json['name']?.toString() ?? 'Source',
      connected: json['connected'] == true,
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString() ?? '',
    );
  }

  final String name;
  final bool connected;
  final int itemCount;
  final String note;
}

class _SearchIdea {
  const _SearchIdea({
    required this.title,
    required this.category,
    required this.searchTerms,
    required this.fitReason,
    required this.icon,
  });

  final String title;
  final String category;
  final String searchTerms;
  final String fitReason;
  final IconData icon;
}

Color _marketColor(String marketplace) => switch (marketplace) {
  'Shopee' => const Color(0xFFEE4D2D),
  'Lazada' => const Color(0xFF1A2E8E),
  'Temu' => const Color(0xFFFF6A00),
  _ => const Color(0xFF573326),
};

enum _Marketplace { shopee, lazada, temu }
