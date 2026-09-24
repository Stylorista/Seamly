import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';

class FashionNewsScreen extends StatefulWidget {
  const FashionNewsScreen({super.key, required this.api, this.active = true});

  final SeamlyApi api;
  final bool active;

  @override
  State<FashionNewsScreen> createState() => _FashionNewsScreenState();
}

class _FashionNewsScreenState extends State<FashionNewsScreen> {
  static const _categories = [
    _NewsCategory('All', 'all', Icons.auto_awesome_rounded),
    _NewsCategory('Y2K', 'y2k', Icons.star_rounded),
    _NewsCategory('Gothic', 'gothic', Icons.dark_mode_rounded),
    _NewsCategory('Alternative', 'alternative', Icons.bolt_rounded),
    _NewsCategory('Formal', 'formal', Icons.business_center_rounded),
    _NewsCategory('Casual', 'casual', Icons.weekend_rounded),
    _NewsCategory('Wedding', 'wedding', Icons.diamond_rounded),
    _NewsCategory('Streetwear', 'streetwear', Icons.directions_walk_rounded),
    _NewsCategory('Vintage', 'vintage', Icons.history_rounded),
  ];

  _NewsCategory _selectedCategory = _categories.first;
  List<FashionNewsPost> _posts = const [];
  List<NewsSourceStatus> _sources = const [];
  final Set<String> _likedPosts = {};
  String _searchQuery = '';
  String? _error;
  DateTime? _fetchedAt;
  bool _loading = false;
  bool _hasLoaded = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _loadFeed();
    }
  }

  @override
  void didUpdateWidget(covariant FashionNewsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_hasLoaded) {
      _loadFeed();
    }
  }

  Future<void> _loadFeed() async {
    final requestSerial = ++_requestSerial;
    setState(() {
      _hasLoaded = true;
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.fetchFashionNews(
        category: _selectedCategory.id,
      );
      final items = (result['items'] as List<dynamic>? ?? const [])
          .map((item) => FashionNewsPost.fromJson(item as Map<String, dynamic>))
          .where(
            (item) =>
                item.publisher.toLowerCase() != 'seamly discovery' &&
                !item.summary.toLowerCase().contains(
                  'live sources are temporarily unavailable',
                ),
          )
          .toList();
      final sources = (result['sources'] as List<dynamic>? ?? const [])
          .map(
            (item) => NewsSourceStatus.fromJson(item as Map<String, dynamic>),
          )
          .toList();
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _posts = items;
        _sources = sources;
        _fetchedAt = items.isEmpty
            ? null
            : DateTime.tryParse(result['fetched_at'] as String? ?? '');
        if (items.isEmpty) {
          _error = 'No live stories were returned. Pull down to try again.';
        }
      });
    } on ApiException catch (error) {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _posts = const [];
        _sources = const [
          NewsSourceStatus(
            name: 'Live service',
            connected: false,
            note: 'Reconnect to load current stories',
          ),
        ];
        _error = error.message;
      });
    } on Exception {
      if (!mounted || requestSerial != _requestSerial) return;
      setState(() {
        _posts = const [];
        _sources = const [
          NewsSourceStatus(
            name: 'Live service',
            connected: false,
            note: 'Reconnect to load current stories',
          ),
        ];
        _error = 'The live fashion feed could not be read.';
      });
    } finally {
      if (mounted && requestSerial == _requestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  void _selectCategory(_NewsCategory category) {
    if (category == _selectedCategory) return;
    setState(() => _selectedCategory = category);
    _loadFeed();
  }

  List<FashionNewsPost> get _visiblePosts {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _posts;
    return _posts.where((post) {
      return post.title.toLowerCase().contains(query) ||
          post.summary.toLowerCase().contains(query) ||
          post.publisher.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openStory(FashionNewsPost post) async {
    try {
      final opened = await launchUrl(
        Uri.parse(post.url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) _showMessage('This story could not be opened.');
    } on Exception {
      if (mounted) _showMessage('This story could not be opened.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openPlatform(_NewsPlatform platform) async {
    final category = _selectedCategory.id == 'all'
        ? 'fashion'
        : _selectedCategory.id;
    final query = '$category fashion';
    final tag = '${category.replaceAll(RegExp(r'[^a-z0-9]'), '')}fashion';
    final uri = switch (platform) {
      _NewsPlatform.google => Uri.https('news.google.com', '/search', {
        'q': query,
        'hl': 'en-PH',
        'gl': 'PH',
        'ceid': 'PH:en',
      }),
      _NewsPlatform.reddit => Uri.https('www.reddit.com', '/search/', {
        'q': query,
        'sort': 'new',
      }),
      _NewsPlatform.instagram => Uri.https(
        'www.instagram.com',
        '/explore/tags/$tag/',
      ),
      _NewsPlatform.facebook => Uri.https(
        'www.facebook.com',
        '/search/posts/',
        {'q': query},
      ),
    };
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!opened && mounted) {
        _showMessage('That platform could not be opened.');
      }
    } on Exception {
      if (mounted) _showMessage('That platform could not be opened.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _visiblePosts;
    return Material(
      color: const Color(0xFFF2F3F5),
      child: RefreshIndicator(
        onRefresh: _loadFeed,
        color: SeamlyColors.sandText,
        child: CustomScrollView(
          key: const ValueKey('fashion-feed'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _FeedHeader(
                fetchedAt: _fetchedAt,
                onSearchChanged: (value) =>
                    setState(() => _searchQuery = value),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: SeamlyColors.sandText,
                ),
              ),
            SliverToBoxAdapter(
              child: _CategoryStrip(
                categories: _categories,
                selected: _selectedCategory,
                onSelected: _selectCategory,
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              sliver: SliverToBoxAdapter(
                child: _PlatformDiscovery(onOpen: _openPlatform),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              sliver: SliverToBoxAdapter(
                child: _SourcesCard(sources: _sources),
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                sliver: SliverToBoxAdapter(
                  child: _OfflineNotice(message: _error!, onRetry: _loadFeed),
                ),
              ),
            if (!_loading && visiblePosts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No matching fashion stories.')),
              )
            else
              SliverList.builder(
                itemCount: visiblePosts.length,
                itemBuilder: (context, index) {
                  final post = visiblePosts[index];
                  final liked = _likedPosts.contains(post.id);
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    child: _FeedPostCard(
                      post: post,
                      liked: liked,
                      onLike: () => setState(() {
                        if (liked) {
                          _likedPosts.remove(post.id);
                        } else {
                          _likedPosts.add(post.id);
                        }
                      }),
                      onComment: () => _showMessage(
                        'Comments are available on the original story.',
                      ),
                      onShare: () => _showMessage(
                        'Open the story to share it from the original source.',
                      ),
                      onOpen: () => _openStory(post),
                    ),
                  );
                },
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({required this.onSearchChanged, required this.fetchedAt});

  final ValueChanged<String> onSearchChanged;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 21,
                  backgroundColor: SeamlyColors.sand,
                  child: Icon(Icons.newspaper_rounded, color: Colors.white),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fashion Feed',
                        style: TextStyle(
                          fontSize: 25,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fetchedAt == null
                            ? 'Pull down for live fashion stories'
                            : 'Live • updated ${_relativeTime(fetchedAt!)}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.notifications_none_rounded),
              ],
            ),
            const SizedBox(height: 13),
            TextField(
              key: const ValueKey('fashion-news-search'),
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search fashion stories',
                prefixIcon: const Icon(Icons.search_rounded),
                fillColor: const Color(0xFFF0F2F5),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformDiscovery extends StatelessWidget {
  const _PlatformDiscovery({required this.onOpen});

  final ValueChanged<_NewsPlatform> onOpen;

  @override
  Widget build(BuildContext context) {
    const platforms = [
      (_NewsPlatform.google, 'Google', Icons.public_rounded),
      (_NewsPlatform.reddit, 'Reddit', Icons.forum_rounded),
      (_NewsPlatform.instagram, 'Instagram', Icons.camera_alt_outlined),
      (_NewsPlatform.facebook, 'Facebook', Icons.people_alt_outlined),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: Color(0xFF2E7D32)),
              SizedBox(width: 6),
              Text(
                'OPEN LIVE SOURCES',
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final platform in platforms)
                ActionChip(
                  avatar: Icon(platform.$3, size: 16),
                  label: Text(platform.$2),
                  onPressed: () => onOpen(platform.$1),
                  side: BorderSide(
                    color: SeamlyColors.sand.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Google and global publishers load inside the feed. Social buttons open the newest public results on their original platform; sign-in rules belong to that platform.',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.black54,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<_NewsCategory> categories;
  final _NewsCategory selected;
  final ValueChanged<_NewsCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = category == selected;
          return ChoiceChip(
            key: ValueKey('news-category-${category.id}'),
            selected: isSelected,
            onSelected: (_) => onSelected(category),
            avatar: Icon(
              category.icon,
              size: 17,
              color: isSelected ? Colors.white : SeamlyColors.sandText,
            ),
            label: Text(category.label),
            selectedColor: const Color(0xFF513225),
            checkmarkColor: Colors.white,
            showCheckmark: false,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
            ),
            side: BorderSide(
              color: isSelected ? const Color(0xFF513225) : Colors.black12,
            ),
          );
        },
      ),
    );
  }
}

class _SourcesCard extends StatelessWidget {
  const _SourcesCard({required this.sources});

  final List<NewsSourceStatus> sources;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FEED SOURCES',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final source in sources)
                Tooltip(
                  message: source.note,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: source.connected
                          ? const Color(0xFFEAF5EC)
                          : const Color(0xFFF3F0ED),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          source.connected
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 14,
                          color: source.connected
                              ? const Color(0xFF2E7D32)
                              : Colors.black45,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          source.name,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFF9A5A21)),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.liked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onOpen,
  });

  final FashionNewsPost post;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 10, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: _platformColor(post.platform),
                  child: Text(
                    post.publisher.isEmpty
                        ? 'F'
                        : post.publisher[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.publisher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${post.platform}  •  ${_relativeTime(post.publishedAt)}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz_rounded, color: Colors.black54),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 3, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  post.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              ],
            ),
          ),
          if (post.imageUrl != null)
            SizedBox(
              height: 235,
              width: double.infinity,
              child: Image.network(
                post.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PublisherImageUnavailable(),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ColoredBox(
                        color: Color(0xFFE7DED6),
                        child: Center(child: CircularProgressIndicator()),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: SeamlyColors.sand.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '#${post.category}',
                    style: const TextStyle(
                      color: Color(0xFF8A5A40),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.thumb_up_rounded,
                  color: liked ? const Color(0xFF1877F2) : Colors.black45,
                  size: 17,
                ),
                const SizedBox(width: 4),
                Text(
                  '${post.likeCount + (liked ? 1 : 0)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(width: 12),
                Text(
                  '${post.commentCount} comments',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: _FeedAction(
                  icon: liked
                      ? Icons.thumb_up_rounded
                      : Icons.thumb_up_outlined,
                  label: 'Like',
                  color: liked ? const Color(0xFF1877F2) : Colors.black54,
                  onPressed: onLike,
                ),
              ),
              Expanded(
                child: _FeedAction(
                  icon: Icons.mode_comment_outlined,
                  label: 'Comment',
                  onPressed: onComment,
                ),
              ),
              Expanded(
                child: _FeedAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onPressed: onShare,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpen,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF513225),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Read original story'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedAction extends StatelessWidget {
  const _FeedAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = Colors.black54,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
    );
  }
}

class _PublisherImageUnavailable extends StatelessWidget {
  const _PublisherImageUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE7DED6),
      child: Center(
        child: Text(
          'Publisher image unavailable',
          style: TextStyle(
            color: Color(0xFF70584A),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Color _platformColor(String platform) {
  if (platform.toLowerCase().contains('reddit')) {
    return const Color(0xFFFF4500);
  }
  if (platform.toLowerCase().contains('google')) {
    return const Color(0xFF4285F4);
  }
  return SeamlyColors.sand;
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inDays < 1) return '${difference.inHours}h';
  if (difference.inDays < 7) return '${difference.inDays}d';
  return '${value.month}/${value.day}/${value.year}';
}

class FashionNewsPost {
  const FashionNewsPost({
    required this.id,
    required this.title,
    required this.summary,
    required this.url,
    required this.imageUrl,
    required this.publisher,
    required this.platform,
    required this.category,
    required this.publishedAt,
    required this.likeCount,
    required this.commentCount,
  });

  factory FashionNewsPost.fromJson(Map<String, dynamic> json) {
    return FashionNewsPost(
      id: json['id'] as String,
      title: json['title'] as String,
      summary: json['summary'] as String,
      url: json['url'] as String,
      imageUrl: json['image_url'] as String?,
      publisher: json['publisher'] as String,
      platform: json['platform'] as String,
      category: json['category'] as String,
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      likeCount: (json['like_count'] as num).toInt(),
      commentCount: (json['comment_count'] as num).toInt(),
    );
  }

  final String id;
  final String title;
  final String summary;
  final String url;
  final String? imageUrl;
  final String publisher;
  final String platform;
  final String category;
  final DateTime publishedAt;
  final int likeCount;
  final int commentCount;
}

class NewsSourceStatus {
  const NewsSourceStatus({
    required this.name,
    required this.connected,
    required this.note,
  });

  factory NewsSourceStatus.fromJson(Map<String, dynamic> json) {
    return NewsSourceStatus(
      name: json['name'] as String,
      connected: json['connected'] as bool,
      note: json['note'] as String,
    );
  }

  final String name;
  final bool connected;
  final String note;
}

class _NewsCategory {
  const _NewsCategory(this.label, this.id, this.icon);

  final String label;
  final String id;
  final IconData icon;
}

enum _NewsPlatform { google, reddit, instagram, facebook }
