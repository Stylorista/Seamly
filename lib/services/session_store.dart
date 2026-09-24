import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AccountSession {
  const AccountSession({
    required this.token,
    required this.email,
    required this.heightCm,
    this.name,
    this.avatarBase64,
    this.measurements,
    this.sizeLabel,
  });

  factory AccountSession.fromApi(Map<String, dynamic> response) {
    final profile = response['profile'] as Map<String, dynamic>;
    final rawMeasurements = profile['latest_measurements'];
    return AccountSession(
      token: response['token'] as String,
      email: profile['email'] as String,
      heightCm: (profile['height_cm'] as num).toDouble(),
      name: profile['name'] as String?,
      avatarBase64: profile['avatar_base64'] as String?,
      measurements: rawMeasurements is Map<String, dynamic>
          ? rawMeasurements.map(
              (key, value) => MapEntry(key, (value as num).toDouble()),
            )
          : null,
      sizeLabel: profile['size_label'] as String?,
    );
  }

  final String token;
  final String email;
  final double heightCm;
  final String? name;
  final String? avatarBase64;
  final Map<String, double>? measurements;
  final String? sizeLabel;
}

class SessionState {
  const SessionState({
    required this.authenticated,
    required this.welcomeCompleted,
    this.token,
    this.email,
    this.heightCm,
    this.name,
    this.avatarBase64,
    this.measurements,
    this.sizeLabel,
  });

  const SessionState.signedOut()
    : authenticated = false,
      welcomeCompleted = false,
      token = null,
      email = null,
      heightCm = null,
      name = null,
      avatarBase64 = null,
      measurements = null,
      sizeLabel = null;

  final bool authenticated;
  final bool welcomeCompleted;
  final String? token;
  final String? email;
  final double? heightCm;
  final String? name;
  final String? avatarBase64;
  final Map<String, double>? measurements;
  final String? sizeLabel;
}

abstract interface class SessionStore {
  Future<SessionState> read();

  Future<void> setAuthenticated(bool value);

  Future<void> saveAccountSession(AccountSession session);

  Future<void> saveMeasurementProfile(
    Map<String, double> measurements,
    String? sizeLabel,
  );

  Future<void> setWelcomeCompleted(bool value);
}

class PreferencesSessionStore implements SessionStore {
  PreferencesSessionStore({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _authenticatedKey = 'seamly.authenticated';
  static const _welcomeCompletedKey = 'seamly.welcome_completed';
  static const _tokenKey = 'seamly.account_token';
  static const _emailKey = 'seamly.account_email';
  static const _heightKey = 'seamly.height_cm';
  static const _nameKey = 'seamly.account_name';
  static const _avatarKey = 'seamly.account_avatar';
  static const _measurementsKey = 'seamly.measurements';
  static const _sizeLabelKey = 'seamly.size_label';

  final Future<SharedPreferences> _preferences;

  @override
  Future<SessionState> read() async {
    final preferences = await _preferences;
    final encodedMeasurements = preferences.getString(_measurementsKey);
    Map<String, double>? measurements;
    if (encodedMeasurements != null) {
      try {
        final decoded = jsonDecode(encodedMeasurements) as Map<String, dynamic>;
        measurements = decoded.map(
          (key, value) => MapEntry(key, (value as num).toDouble()),
        );
      } on Exception {
        measurements = null;
      }
    }
    final token = preferences.getString(_tokenKey);
    return SessionState(
      authenticated: preferences.getBool(_authenticatedKey) ?? false,
      welcomeCompleted: preferences.getBool(_welcomeCompletedKey) ?? false,
      token: token,
      email: preferences.getString(_emailKey),
      heightCm: preferences.getDouble(_heightKey),
      name: preferences.getString(_nameKey),
      avatarBase64: preferences.getString(_avatarKey),
      measurements: measurements,
      sizeLabel: preferences.getString(_sizeLabelKey),
    );
  }

  @override
  Future<void> setAuthenticated(bool value) async {
    final preferences = await _preferences;
    await preferences.setBool(_authenticatedKey, value);
    if (!value) {
      await preferences.remove(_tokenKey);
      await preferences.remove(_emailKey);
      await preferences.remove(_heightKey);
      await preferences.remove(_nameKey);
      await preferences.remove(_avatarKey);
      await preferences.remove(_welcomeCompletedKey);
      await preferences.remove(_measurementsKey);
      await preferences.remove(_sizeLabelKey);
    }
  }

  @override
  Future<void> saveAccountSession(AccountSession session) async {
    final preferences = await _preferences;
    await preferences.setBool(_authenticatedKey, true);
    await preferences.setString(_tokenKey, session.token);
    await preferences.setString(_emailKey, session.email);
    await preferences.setDouble(_heightKey, session.heightCm);
    for (final entry in {
      _nameKey: session.name,
      _avatarKey: session.avatarBase64,
    }.entries) {
      if (entry.value == null) {
        await preferences.remove(entry.key);
      } else {
        await preferences.setString(entry.key, entry.value!);
      }
    }
    await saveMeasurementProfile(
      session.measurements ?? const {},
      session.sizeLabel,
    );
  }

  @override
  Future<void> saveMeasurementProfile(
    Map<String, double> measurements,
    String? sizeLabel,
  ) async {
    final preferences = await _preferences;
    if (measurements.isEmpty) {
      await preferences.remove(_measurementsKey);
    } else {
      await preferences.setString(_measurementsKey, jsonEncode(measurements));
    }
    if (sizeLabel == null || sizeLabel.isEmpty) {
      await preferences.remove(_sizeLabelKey);
    } else {
      await preferences.setString(_sizeLabelKey, sizeLabel);
    }
  }

  @override
  Future<void> setWelcomeCompleted(bool value) async {
    final preferences = await _preferences;
    await preferences.setBool(_welcomeCompletedKey, value);
  }
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({
    SessionState initialState = const SessionState.signedOut(),
  }) : _authenticated = initialState.authenticated,
       _welcomeCompleted = initialState.welcomeCompleted,
       _token = initialState.token,
       _email = initialState.email,
       _heightCm = initialState.heightCm,
       _name = initialState.name,
       _avatarBase64 = initialState.avatarBase64,
       _measurements = initialState.measurements,
       _sizeLabel = initialState.sizeLabel;

  bool _authenticated;
  bool _welcomeCompleted;
  String? _token;
  String? _email;
  double? _heightCm;
  String? _name;
  String? _avatarBase64;
  Map<String, double>? _measurements;
  String? _sizeLabel;

  @override
  Future<SessionState> read() async {
    return SessionState(
      authenticated: _authenticated,
      welcomeCompleted: _welcomeCompleted,
      token: _token,
      email: _email,
      heightCm: _heightCm,
      name: _name,
      avatarBase64: _avatarBase64,
      measurements: _measurements,
      sizeLabel: _sizeLabel,
    );
  }

  @override
  Future<void> setAuthenticated(bool value) async {
    _authenticated = value;
    if (!value) {
      _token = null;
      _email = null;
      _heightCm = null;
      _name = null;
      _avatarBase64 = null;
      _welcomeCompleted = false;
      _measurements = null;
      _sizeLabel = null;
    }
  }

  @override
  Future<void> saveAccountSession(AccountSession session) async {
    _authenticated = true;
    _token = session.token;
    _email = session.email;
    _heightCm = session.heightCm;
    _name = session.name;
    _avatarBase64 = session.avatarBase64;
    _measurements = session.measurements;
    _sizeLabel = session.sizeLabel;
  }

  @override
  Future<void> saveMeasurementProfile(
    Map<String, double> measurements,
    String? sizeLabel,
  ) async {
    _measurements = Map<String, double>.from(measurements);
    _sizeLabel = sizeLabel;
  }

  @override
  Future<void> setWelcomeCompleted(bool value) async {
    _welcomeCompleted = value;
  }
}
