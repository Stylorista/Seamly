import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.measurements,
    this.onOpenAccount,
    this.avatarBase64,
    this.showHeader = true,
  });

  final SeamlyApi api;
  final ValueChanged<int> onSelectFeature;
  final String? sizeLabel;
  final String? colorSeason;
  final Map<String, double>? measurements;
  final VoidCallback? onOpenAccount;
  final String? avatarBase64;
  final bool showHeader;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _cityKey = 'seamly.city';

  String _city = 'Manila';
  HomeWeather? _weather;
  String? _error;
  bool _loading = false;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _restoreCity();
  }

  Future<void> _restoreCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_cityKey);
      if (saved != null && saved.trim().length >= 2) {
        _city = saved.trim();
      }
    } on Exception {
      // Defaults to Manila when preferences are unavailable.
    }
    if (!mounted) return;
    await _loadWeather();
  }

  Future<void> _persistCity(String city) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cityKey, city);
    } on Exception {
      // Persistence is best-effort; weather still works without it.
    }
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
    } on ApiException catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        if (_weather == null) {
          _error = error.message;
        } else {
          _error = 'Could not refresh. Showing the last forecast.';
        }
      });
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
    setState(() {
      _city = city;
      _weather = null;
      _error = null;
      _loading = true;
    });
    await _persistCity(city);
    await _loadWeather();
  }

  bool _matchesCity(String resolved) {
    final requested = _city.toLowerCase();
    final parts = resolved
        .split(',')
        .map((part) => part.trim().toLowerCase())
        .where((part) => part.isNotEmpty)
        .toList();
    return requested == resolved.toLowerCase() || parts.contains(requested);
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
                      _EventOutfitCard(
                        api: widget.api,
                        city: _city,
                        sizeLabel: widget.sizeLabel,
                        colorSeason: widget.colorSeason,
                        measurements: widget.measurements,
                        hasScan: widget.sizeLabel != null,
                        onOpenScanner: () => widget.onSelectFeature(2),
                        onOpenStyle: () => widget.onSelectFeature(7),
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
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _city,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (weather != null &&
                                          !_matchesCity(
                                            weather.displayLocation,
                                          ))
                                        Text(
                                          'Forecast for ${weather.displayLocation}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                    ],
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
                                    outfit?.title ??
                                        (_loading
                                            ? 'Checking $_city weather…'
                                            : 'Find your everyday look'),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    outfit?.reason ??
                                        (_loading
                                            ? 'Pulling in today’s forecast for $_city.'
                                            : 'Explore outfit ideas for your day.'),
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

class _EventOutfitCard extends StatefulWidget {
  const _EventOutfitCard({
    required this.api,
    required this.city,
    required this.sizeLabel,
    required this.colorSeason,
    required this.measurements,
    required this.hasScan,
    required this.onOpenScanner,
    required this.onOpenStyle,
  });

  final SeamlyApi api;
  final String city;
  final String? sizeLabel;
  final String? colorSeason;
  final Map<String, double>? measurements;
  final bool hasScan;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenStyle;

  static const eventSuggestions = [
    'Business Casual Mixer',
    'Office Holiday Party',
    'Alumni Networking Event',
    'Conference / Seminar',
    'Cocktail Party',
    'High-End Daytime Brunch',
    'Milestone Birthday Dinner',
    'Engagement Party',
    'Outdoor / Garden Wedding',
    'Winter Holiday Gathering',
    'Music Festival',
    'Beach Party / Cruise Night',
    'Themed Bachelorette Party',
    'First Date',
    'Funeral / Celebration of Life',
    'Birthday',
    'Wedding',
    'Office',
    'Church',
    'Beach',
    'Graduation',
  ];

  static const styleOptions = {
    'minimal': 'Minimal',
    'classic': 'Classic',
    'street': 'Street',
    'romantic': 'Romantic',
  };

  @override
  State<_EventOutfitCard> createState() => _EventOutfitCardState();
}

class _EventOutfitCardState extends State<_EventOutfitCard> {
  final _eventController = TextEditingController();
  final _styleController = TextEditingController();
  String? _selectedStyle;
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _restoreInputs();
  }

  @override
  void dispose() {
    _eventController.dispose();
    _styleController.dispose();
    super.dispose();
  }

  Future<void> _restoreInputs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString('seamly.event.text');
      final dateIso = prefs.getString('seamly.event.date');
      final timeText = prefs.getString('seamly.event.time');
      final style = prefs.getString('seamly.event.style');
      if (!mounted) return;
      setState(() {
        if (text != null) _eventController.text = text;
        if (dateIso != null) _date = DateTime.tryParse(dateIso);
        if (timeText != null) {
          final parts = timeText.split(':');
          if (parts.length == 2) {
            _time = TimeOfDay(
              hour: int.tryParse(parts[0]) ?? 18,
              minute: int.tryParse(parts[1]) ?? 0,
            );
          }
        }
        if (style != null && _EventOutfitCard.styleOptions.containsKey(style)) {
          _selectedStyle = style;
        } else if (style != null && style.isNotEmpty) {
          _styleController.text = style;
        }
      });
    } on Exception {
      // Inputs stay empty when preferences are unavailable.
    }
  }

  Future<void> _persistInputs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('seamly.event.text', _eventController.text.trim());
      if (_date != null) {
        await prefs.setString('seamly.event.date', _date!.toIso8601String());
      }
      await prefs.setString(
        'seamly.event.time',
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      );
      final style = _selectedStyle ?? _styleController.text.trim();
      await prefs.setString('seamly.event.style', style);
    } on Exception {
      // Persistence is best-effort.
    }
  }

  String get _effectiveStyle => _selectedStyle ?? _styleController.text.trim();

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, now.month, now.day),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _plan() async {
    final eventText = _eventController.text.trim();
    if (eventText.length < 2) {
      setState(() => _error = 'Tell us the event first (2+ characters).');
      return;
    }
    if (_date == null) {
      setState(() => _error = 'Pick the date of your event.');
      return;
    }
    final today = DateTime.now();
    final pickedDay = DateTime(_date!.year, _date!.month, _date!.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    if (pickedDay.isBefore(todayDay)) {
      setState(() => _error = 'Pick a future date for your event.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_persistInputs());
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _attemptPlan(eventText);
        if (!mounted) return;
        setState(() {
          _result = result;
          _loading = false;
        });
        return;
      } on ApiException catch (error) {
        final transient = error.message.contains('temporarily unavailable');
        if (transient && attempt == 0) {
          // Brief provider blip: wait, then try once more on our own.
          await Future<void>.delayed(const Duration(seconds: 5));
          if (!mounted) return;
          continue;
        }
        if (!mounted) return;
        setState(() {
          _error = error.message;
          _loading = false;
        });
        return;
      } on Exception {
        if (!mounted) return;
        setState(() {
          _error = 'Could not plan your outfit. Check your connection.';
          _loading = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<Map<String, dynamic>> _attemptPlan(String eventText) {
    return widget.api.planEventOutfit(
      eventText: eventText,
      city: widget.city,
      eventDate:
          '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}',
      eventTime:
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      style: _effectiveStyle.isEmpty ? null : _effectiveStyle,
      sizeLabel: widget.sizeLabel,
      colorSeason: widget.colorSeason,
      measurements: widget.measurements,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey('event-outfit-card'),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Plan your outfit',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tell us the event and moment — we check the forecast and your style.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('event-outfit-field'),
              controller: _eventController,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: "What's the event?",
                hintText: 'e.g. garden wedding',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _EventOutfitCard.eventSuggestions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final suggestion =
                      _EventOutfitCard.eventSuggestions[index];
                  final selected =
                      _eventController.text.trim() == suggestion;
                  return ChoiceChip(
                    label: Text(suggestion),
                    selected: selected,
                    onSelected: (_) => setState(
                      () => _eventController.text = suggestion,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('event-outfit-date'),
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(
                    _date == null
                        ? 'Pick date'
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(_date!),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('event-outfit-time'),
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_time.format(context)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Style',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final entry
                    in _EventOutfitCard.styleOptions.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _selectedStyle == entry.key,
                    onSelected: (value) => setState(
                      () => _selectedStyle = value ? entry.key : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('event-outfit-style-field'),
              controller: _styleController,
              maxLength: 40,
              onChanged: (_) {
                if (_selectedStyle != null) {
                  setState(() => _selectedStyle = null);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Or type your own style',
                hintText: 'e.g. elegant, sporty',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('event-outfit-plan'),
              onPressed: _loading ? null : _plan,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Get outfit'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              _EventOutfitResult(
                result: _result!,
                hasScan: widget.hasScan,
                sizeLabel: widget.sizeLabel,
                onOpenScanner: widget.onOpenScanner,
                onOpenStyle: widget.onOpenStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EventOutfitResult extends StatelessWidget {
  const _EventOutfitResult({
    required this.result,
    required this.hasScan,
    required this.sizeLabel,
    required this.onOpenScanner,
    required this.onOpenStyle,
  });

  final Map<String, dynamic> result;
  final bool hasScan;
  final String? sizeLabel;
  final VoidCallback onOpenScanner;
  final VoidCallback onOpenStyle;

  @override
  Widget build(BuildContext context) {
    final weather = result['weather'] as Map<String, dynamic>? ?? {};
    final pieces = (result['pieces'] as List?)?.cast<String>() ?? [];
    final reasons = (result['reasons'] as List?)?.cast<String>() ?? [];
    final notes =
        (result['styling_notes'] as List?)?.cast<String>() ?? [];
    final fitNotes =
        (result['fit_notes'] as List?)?.cast<String>() ?? [];
    final palette = (result['palette'] as List?)?.cast<String>() ?? [];
    final inspiration =
        (result['inspiration_images'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final isForecast = weather['is_forecast'] == true;
    final temp = weather['temperature_c'];
    final feels = weather['feels_like_c'];
    final condition = weather['condition']?.toString() ?? '';
    return Container(
      key: const ValueKey('event-outfit-result'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F0E9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            result['title']?.toString() ?? 'Your event look',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${result['event_datetime']?.toString() ?? ''} · '
            '${temp != null ? '${(temp as num).round()}°' : '—'} $condition'
            '${feels != null ? ' · feels ${(feels as num).round()}°' : ''}',
            style: const TextStyle(color: Colors.black54),
          ),
          if (!isForecast)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Seasonal estimate — beyond the 16-day forecast.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final piece in pieces)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(piece)),
                ],
              ),
            ),
          if (sizeLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Sized from your scan: $sizeLabel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text('No scan yet — sizes are generic.'),
                  TextButton(
                    onPressed: onOpenScanner,
                    child: const Text('Scan to refine'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Why this works',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✓  '),
                  Expanded(child: Text(reason)),
                ],
              ),
            ),
          if (palette.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final hex in palette.take(4))
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _colorFromHex(hex),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black12),
                    ),
                  ),
              ],
            ),
          ],
          if (notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                notes.first,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          if (inspiration.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Style inspiration',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'Photos for ideas — not actual products.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            SizedBox(
              key: const ValueKey('event-outfit-inspiration'),
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: inspiration.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = inspiration[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      image['image_url']?.toString() ?? '',
                      width: 110,
                      height: 140,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 110,
                        height: 140,
                        color: Colors.black12,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Photos by ${_photoCredits(inspiration)} · Pexels',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
          if (fitNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                fitNotes.first,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onOpenStyle,
            child: const Text('Refine in Style studio'),
          ),
          Text(
            result['disclaimer']?.toString() ?? '',
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

String _photoCredits(List<Map<String, dynamic>> images) {
  final names = images
      .map((image) => image['photographer']?.toString().trim())
      .where((name) => name != null && name.isNotEmpty)
      .cast<String>()
      .take(3)
      .toList();
  return names.isEmpty ? 'Pexels artists' : names.join(', ');
}

Color _colorFromHex(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return Colors.grey;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return Colors.grey;
  return Color(0xFF000000 | value);
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
