import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/session_store.dart';
import '../services/seamly_api.dart';
import '../widgets/account_avatar.dart';
import '../widgets/seamly_header.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.api,
    required this.account,
    required this.onSaved,
    required this.onLogout,
  });

  final SeamlyApi api;
  final AccountSession account;
  final Future<void> Function(AccountSession) onSaved;
  // Returns whether the remote session was successfully revoked.
  final Future<bool> Function() onLogout;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account.name ?? '');
  late final _height = TextEditingController(
    text: _formatHeight(widget.account.heightCm),
  );
  late String? _avatar = widget.account.avatarBase64;
  late double _savedHeight = widget.account.heightCm;
  bool _avatarChanged = false;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  static String _formatHeight(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (photo == null) return;
      if (await photo.length() > 2 * 1024 * 1024) {
        throw const ApiException('Choose a profile picture smaller than 2 MB.');
      }
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatar = base64Encode(bytes);
        _avatarChanged = true;
        _dirty = true;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error =
              'Could not open that photo. Please choose another picture.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final height = double.parse(_height.text.trim());
    final changedHeight = height != _savedHeight;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final profile = await widget.api.updateAccountProfile(
        token: widget.account.token,
        name: _name.text,
        heightCm: height,
        avatarBase64: _avatar,
        updateAvatar: _avatarChanged,
      );
      final account = AccountSession.fromApi({
        'token': widget.account.token,
        'profile': profile,
      });
      await widget.onSaved(account);
      if (!mounted) return;
      setState(() {
        _avatar = account.avatarBase64;
        _name.text = account.name ?? '';
        _height.text = _formatHeight(account.heightCm);
        _savedHeight = account.heightCm;
        _avatarChanged = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            changedHeight
                ? 'Height updated. Scan again for new measurements.'
                : 'Profile saved.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Exception {
      if (mounted) {
        setState(
          () => _error = 'Your profile could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: Text(
          _dirty
              ? 'Unsaved profile changes will be discarded. Your saved account stays available when you sign in again.'
              : 'Your saved account stays available when you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onLogout();
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop();
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not clear this device’s session. Please try logging out again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(68),
          child: SeamlyHeader(
            onBack: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('My account',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 20),
                      Center(
                        child: AccountAvatar(base64Photo: _avatar, radius: 56),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          TextButton.icon(
                            key: const ValueKey('account-change-photo'),
                            onPressed: _busy ? null : _choosePhoto,
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('Change photo'),
                          ),
                          if (_avatar != null)
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _avatar = null;
                                      _avatarChanged = true;
                                      _dirty = true;
                                    }),
                              child: const Text('Remove photo'),
                            ),
                        ],
                      ),
                      const Text(
                        'Your picture is saved privately to your account when you tap Save. It is not used for body or color analysis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const ValueKey('account-name'),
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 100,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                        ),
                        onChanged: (_) => setState(() => _dirty = true),
                        validator: (value) => (value ?? '').trim().length < 2
                            ? 'Enter your full name.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Email',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.account.email,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const ValueKey('account-height'),
                        controller: _height,
                        enabled: !_busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Height',
                          suffixText: 'cm',
                        ),
                        onChanged: (_) => setState(() => _dirty = true),
                        validator: (value) {
                          final height = double.tryParse((value ?? '').trim());
                          return height == null ||
                                  !height.isFinite ||
                                  height < 120 ||
                                  height > 230
                              ? 'Enter your actual height from 120 to 230 cm.'
                              : null;
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Use your actual height to calibrate the camera. Changing it clears saved scan estimates and size recommendations; scan again after saving.',
                        style: TextStyle(fontSize: 14),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('account-save'),
                        onPressed: _busy || !_dirty ? null : _save,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(_busy ? 'Please wait…' : 'Save changes'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        key: const ValueKey('account-logout'),
                        onPressed: _busy ? null : _logout,
                        icon: const Icon(Icons.logout_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Log out'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
