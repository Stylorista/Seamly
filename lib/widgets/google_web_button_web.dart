import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

import '../services/google_sign_in_service.dart';

/// GIS-rendered Google button for web. Listens to authenticationEvents and
/// forwards the ID token to [onIdToken].
class GoogleWebButton extends StatefulWidget {
  const GoogleWebButton({
    super.key,
    required this.onIdToken,
    required this.onError,
  });

  final ValueChanged<String> onIdToken;
  final ValueChanged<String> onError;

  @override
  State<GoogleWebButton> createState() => _GoogleWebButtonState();
}

class _GoogleWebButtonState extends State<GoogleWebButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  bool _ready = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await GoogleSignInService.ensureInitialized();
      _subscription = GoogleSignIn.instance.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            final idToken = event.user.authentication.idToken;
            if (idToken != null && idToken.isNotEmpty) {
              widget.onIdToken(idToken);
            } else {
              widget.onError(
                'Google did not return a sign-in token. Please try again.',
              );
            }
          }
        },
        onError: (_) => widget.onError(
          'Google sign-in failed. Please try again.',
        ),
      );
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _initError = 'Google sign-in is unavailable right now.',
        );
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) return const SizedBox.shrink();
    if (!_ready) return const SizedBox.shrink();
    return Center(child: web_only.renderButton());
  }
}
