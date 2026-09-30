import 'package:flutter/widgets.dart';

/// Fallback used on mobile/desktop where the GIS web button is unavailable.
class GoogleWebButton extends StatelessWidget {
  const GoogleWebButton({
    super.key,
    required this.onIdToken,
    required this.onError,
  });

  final ValueChanged<String> onIdToken;
  final ValueChanged<String> onError;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
