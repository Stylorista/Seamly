import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/session_store.dart';
import '../services/seamly_api.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
    this.notice,
  });

  final SeamlyApi api;
  final String? notice;
  final Future<void> Function(AccountSession session, bool isNewAccount)
  onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { signIn, register }

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _heightController = TextEditingController();
  final _passwordController = TextEditingController();

  _AuthMode _mode = _AuthMode.signIn;
  bool _obscurePassword = true;
  bool _acceptTerms = false;
  bool _loading = false;

  bool get _signingIn => _mode == _AuthMode.signIn;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _heightController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _mode = _signingIn ? _AuthMode.register : _AuthMode.signIn;
      _acceptTerms = false;
    });
    _formKey.currentState?.reset();
  }

  Future<void> _submit() async {
    if (_loading || !(_formKey.currentState?.validate() ?? false)) return;
    if (!_signingIn && !_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms to continue.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final response = _signingIn
          ? await widget.api.loginAccount(
              email: _emailController.text,
              password: _passwordController.text,
            )
          : await widget.api.registerAccount(
              name: _nameController.text,
              email: _emailController.text,
              password: _passwordController.text,
              // Height is completed from Profile/Body scan after registration.
              heightCm: 165,
              location: _locationController.text,
            );
      if (!mounted) return;
      await widget.onAuthenticated(
        AccountSession.fromApi(response),
        response['is_new_account'] == true,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      setState(() => _loading = false);
    }
  }

  void _forgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password recovery is coming in the secure account build.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _FashionBackdrop(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 30, 26, 30),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 60,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _AuthLogo(),
                            if (_signingIn) ...[
                              const SizedBox(height: 24),
                              const Text(
                                'See Your Size.\nKnow Your Style.\nShop With Confidence.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  height: 1.36,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x55000000),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (widget.notice != null) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    widget.notice!,
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: _AuthCard(
                                key: ValueKey(_mode),
                                formKey: _formKey,
                                signingIn: _signingIn,
                                nameController: _nameController,
                                emailController: _emailController,
                                locationController: _locationController,
                                passwordController: _passwordController,
                                obscurePassword: _obscurePassword,
                                acceptTerms: _acceptTerms,
                                loading: _loading,
                                onTogglePassword: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                onAcceptTerms: (value) => setState(
                                  () => _acceptTerms = value ?? false,
                                ),
                                onForgotPassword: _forgotPassword,
                                onSubmit: _submit,
                                onSwitchMode: _switchMode,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FashionBackdrop extends StatelessWidget {
  const _FashionBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF9F7D69),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Transform.scale(
              scale: 1.08,
              child: Image.asset(
                'assets/images/home_hero.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        const ColoredBox(color: Color(0x4D543424)),
      ],
    );
  }
}

class _AuthLogo extends StatelessWidget {
  const _AuthLogo();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/seamly_logo.png',
      key: const ValueKey('auth-logo'),
      width: 240,
      height: 240,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Seamly logo',
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    super.key,
    required this.formKey,
    required this.signingIn,
    required this.nameController,
    required this.emailController,
    required this.locationController,
    required this.passwordController,
    required this.obscurePassword,
    required this.acceptTerms,
    required this.loading,
    required this.onTogglePassword,
    required this.onAcceptTerms,
    required this.onForgotPassword,
    required this.onSubmit,
    required this.onSwitchMode,
  });

  final GlobalKey<FormState> formKey;
  final bool signingIn;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController locationController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool acceptTerms;
  final bool loading;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool?> onAcceptTerms;
  final VoidCallback onForgotPassword;
  final VoidCallback onSubmit;
  final VoidCallback onSwitchMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!signingIn) ...[
              const Text(
                'Create your profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              _LabeledField(
                label: 'Full name:',
                controller: nameController,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').trim().length < 2) return 'Enter your name';
                  return null;
                },
              ),
              const SizedBox(height: 17),
            ],
            _LabeledField(
              label: 'Email:',
              controller: emailController,
              hintText: 'hello@reallygreatsite.com',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return 'Enter a valid email';
                }
                return null;
              },
            ),
            if (!signingIn) ...[
              _LabeledField(
                label: 'City or region · optional:',
                controller: locationController,
                textInputAction: TextInputAction.next,
              ),
            ],
            const SizedBox(height: 17),
            _LabeledField(
              label: 'Password:',
              controller: passwordController,
              hintText: 'Enter your password',
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              autofillHints: signingIn
                  ? const [AutofillHints.password]
                  : const [AutofillHints.newPassword],
              suffixIcon: IconButton(
                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                onPressed: onTogglePassword,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: Colors.black,
                  size: 22,
                ),
              ),
              onFieldSubmitted: (_) => onSubmit(),
              validator: (value) {
                if ((value ?? '').length < 8) {
                  return 'Use at least 8 characters';
                }
                return null;
              },
            ),
            if (signingIn)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Forgot Password ?',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    TextButton(
                      onPressed: onForgotPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB36D35),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Reset here',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Material(
                color: Colors.transparent,
                child: CheckboxListTile(
                  value: acceptTerms,
                  onChanged: onAcceptTerms,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: const Text(
                    'I agree to the terms and privacy policy.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('terms-conditions-button'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Terms & Conditions'),
                    content: const SingleChildScrollView(
                      child: Text(
                        'Seamly provides estimated styling, color, and body-measurement guidance. Results are not medical or tailoring advice. You control the photos you submit and should confirm measurements with a tape and the seller’s size chart before buying.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Read Terms & Conditions'),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: ValueKey(signingIn ? 'sign-in-button' : 'create-button'),
                onPressed: loading ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE85E00),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFED965D),
                  minimumSize: const Size.fromHeight(56),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 15,
                  ),
                  shape: const StadiumBorder(),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(signingIn ? 'Sign in' : 'Create account'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('switch-auth-mode-button'),
                onPressed: loading ? null : onSwitchMode,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9D6033),
                  minimumSize: const Size.fromHeight(52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  side: const BorderSide(color: Color(0xFFC9824B), width: 1.4),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(signingIn ? 'Create new account' : 'Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          obscureText: obscureText,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: Color(0xFF44404B), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF0F0F0),
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(
                color: Color(0xFFC9824B),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
