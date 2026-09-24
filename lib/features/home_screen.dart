import 'package:flutter/material.dart';

import '../services/seamly_api.dart';
import '../theme/seamly_theme.dart';
import '../widgets/seamly_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.onSelectFeature,
    required this.sizeLabel,
    required this.colorSeason,
    this.onOpenAccount,
    this.avatarBase64,
    this.showHeader = true,
  });

  final SeamlyApi api;
  final ValueChanged<int> onSelectFeature;
  final String? sizeLabel;
  final String? colorSeason;
  final VoidCallback? onOpenAccount;
  final String? avatarBase64;
  final bool showHeader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _city = 'Manila';
  HomeWeather? _weather;
  String? _error;
  bool _loading = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _loadWeather();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sizeLabel != widget.sizeLabel ||
        oldWidget.colorSeason != widget.colorSeason) {
      _loadWeather();
    }
  }

  Future<void> _loadWeather() async {
    final serial = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.fetchHomeWeather(
        city: _city,
        sizeLabel: widget.sizeLabel,
        colorSeason: widget.colorSeason,
      );
      if (!mounted || serial != _requestSerial) return;
      setState(() => _weather = HomeWeather.fromJson(response));
    } on Exception {
      if (!mounted || serial != _requestSerial) return;
      setState(
        () => _error = _weather == null
            ? 'Weather is unavailable right now.'
            : 'Could not refresh. Showing the last forecast.',
      );
    } finally {
      if (mounted && serial == _requestSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _changeCity() async {
    final city = await showDialog<String>(
      context: context,
      builder: (_) => _CityDialog(initialCity: _city),
    );
    if (!mounted || city == null) return;
    setState(() => _city = city);
    await _loadWeather();
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    final outfit = weather?.fashion
        .where((tip) => tip.kind == 'outfit')
        .firstOrNull;
    return ColoredBox(
      color: SeamlyColors.cream,
      child: SafeArea(
        top: widget.showHeader,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadWeather,
          child: ListView(
            key: const ValueKey('home-content'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.showHeader) ...[
                        SeamlyHeader(
                          onOpenAccount: widget.onOpenAccount ??
                              () => widget.onSelectFeature(4),
                          avatarBase64: widget.avatarBase64,
                        ),
                        const SizedBox(height: 20),
                      ],
                      Material(
                        color: const Color(0xFF513225),
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey('home-start-scan'),
                          onTap: () => widget.onSelectFeature(2),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Scan your fit',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        widget.sizeLabel == null
                                            ? 'Your measurements and personal colors.'
                                            : 'Size ${widget.sizeLabel} saved · Update your scan',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 12,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    weather?.location ?? _city,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _loading ? null : _changeCity,
                                    child: const Text('Change city'),
                                  ),
                                ],
                              ),
                              if (_loading)
                                const LinearProgressIndicator(minHeight: 2),
                              if (weather != null) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Icon(
                                      _weatherIcon(weather.current.weatherCode),
                                      color: SeamlyColors.moss,
                                      size: 36,
                                    ),
                                    Text(
                                      '${weather.current.temperature.round()}°',
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      'Today · ${weather.current.condition}',
                                      style: const TextStyle(fontSize: 16),
                                    ),
                                  ],
                                ),
                              ] else if (_error == null)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Getting today’s weather…'),
                                ),
                              if (_error != null)
                                Row(
                                  children: [
                                    Expanded(child: Text(_error!)),
                                    TextButton(
                                      onPressed: _loading ? null : _loadWeather,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              if (weather != null)
                                Theme(
                                  data: Theme.of(
                                    context,
                                  ).copyWith(dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    key: const ValueKey('home-weather-details'),
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: const EdgeInsets.only(
                                      bottom: 10,
                                    ),
                                    title: const Text(
                                      'Forecast details',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Feels like ${weather.current.apparent.round()}° · '
                                          '${weather.current.humidity}% humidity · '
                                          '${weather.current.wind.round()} km/h wind',
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Tomorrow · ${weather.tomorrow.condition}\n'
                                          '${weather.tomorrow.high.round()}° / ${weather.tomorrow.low.round()}° · '
                                          '${weather.tomorrow.rainChance}% rain · '
                                          'UV ${weather.tomorrow.uv.toStringAsFixed(1)}',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          weather.source,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'What to wear',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Image.asset(
                              'assets/images/home_hero.png',
                              height: 140,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    outfit?.title ?? 'Find your everyday look',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    outfit?.reason ??
                                        'Explore outfit ideas for your day.',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    key: const ValueKey(
                                      'home-full-weather-look',
                                    ),
                                    onPressed: () => widget.onSelectFeature(7),
                                    child: const Text('Explore outfits'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CityDialog extends StatefulWidget {
  const _CityDialog({required this.initialCity});
  final String initialCity;

  @override
  State<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends State<_CityDialog> {
  late final _controller = TextEditingController(text: widget.initialCity);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length < 2) {
      setState(() => _error = 'Enter at least two letters.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your city'),
      content: TextField(
        key: const ValueKey('home-city-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'City or city, country',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('home-weather-search'),
          onPressed: _submit,
          child: const Text('Update'),
        ),
      ],
    );
  }
}

IconData _weatherIcon(int code) {
  if (code == 0 || code == 1) return Icons.wb_sunny_rounded;
  if (code == 2 || code == 3 || code == 45 || code == 48) {
    return Icons.cloud_rounded;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return Icons.ac_unit_rounded;
  }
  if (code >= 95) return Icons.thunderstorm_rounded;
  return Icons.water_drop_rounded;
}

class HomeWeather {
  const HomeWeather({
    required this.location,
    required this.region,
    required this.country,
    required this.current,
    required this.tomorrow,
    required this.fashion,
    required this.source,
  });

  factory HomeWeather.fromJson(Map<String, dynamic> json) {
    return HomeWeather(
      location: json['location'] as String,
      region: json['region'] as String?,
      country: json['country'] as String?,
      current: CurrentWeather.fromJson(json['current'] as Map<String, dynamic>),
      tomorrow: TomorrowWeather.fromJson(
        json['tomorrow'] as Map<String, dynamic>,
      ),
      fashion: (json['fashion'] as List<dynamic>)
          .map(
            (item) => FashionWeatherTip.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      source: json['source'] as String,
    );
  }

  final String location;
  final String? region;
  final String? country;
  final CurrentWeather current;
  final TomorrowWeather tomorrow;
  final List<FashionWeatherTip> fashion;
  final String source;

  String get displayLocation => [
    location,
    if (region != null && region!.isNotEmpty && region != location) region!,
    if (country != null && country!.isNotEmpty) country!,
  ].join(', ');
}

class CurrentWeather {
  const CurrentWeather({
    required this.temperature,
    required this.apparent,
    required this.humidity,
    required this.wind,
    required this.weatherCode,
    required this.condition,
  });

  factory CurrentWeather.fromJson(Map<String, dynamic> json) {
    return CurrentWeather(
      temperature: (json['temperature_c'] as num).toDouble(),
      apparent: (json['apparent_temperature_c'] as num).toDouble(),
      humidity: (json['humidity_percent'] as num).round(),
      wind: (json['wind_kmh'] as num).toDouble(),
      weatherCode: (json['weather_code'] as num).round(),
      condition: json['condition'] as String,
    );
  }

  final double temperature;
  final double apparent;
  final int humidity;
  final double wind;
  final int weatherCode;
  final String condition;
}

class TomorrowWeather {
  const TomorrowWeather({
    required this.high,
    required this.low,
    required this.rainChance,
    required this.uv,
    required this.weatherCode,
    required this.condition,
  });

  factory TomorrowWeather.fromJson(Map<String, dynamic> json) {
    return TomorrowWeather(
      high: (json['temperature_max_c'] as num).toDouble(),
      low: (json['temperature_min_c'] as num).toDouble(),
      rainChance: (json['precipitation_probability'] as num).round(),
      uv: (json['uv_index_max'] as num).toDouble(),
      weatherCode: (json['weather_code'] as num).round(),
      condition: json['condition'] as String,
    );
  }

  final double high;
  final double low;
  final int rainChance;
  final double uv;
  final int weatherCode;
  final String condition;
}

class FashionWeatherTip {
  const FashionWeatherTip({
    required this.kind,
    required this.title,
    required this.reason,
  });

  factory FashionWeatherTip.fromJson(Map<String, dynamic> json) {
    return FashionWeatherTip(
      kind: json['kind'] as String,
      title: json['title'] as String,
      reason: json['reason'] as String,
    );
  }

  final String kind;
  final String title;
  final String reason;
}
