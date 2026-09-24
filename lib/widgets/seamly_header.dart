import 'package:flutter/material.dart';

import '../theme/seamly_theme.dart';
import 'account_avatar.dart';

/// One brand and account control shared by every main destination.
class SeamlyHeader extends StatelessWidget {
  const SeamlyHeader({
    super.key,
    this.onOpenAccount,
    this.avatarBase64,
    this.onBack,
  });

  final VoidCallback? onOpenAccount;
  final String? avatarBase64;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SeamlyColors.cream,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (onBack != null)
                    IconButton(
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  Image.asset(
                    'assets/images/seamly_logo.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    semanticLabel: 'Seamly logo',
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Seamly',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  if (onOpenAccount != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('header-account'),
                      tooltip: 'My account',
                      onPressed: onOpenAccount,
                      icon: AccountAvatar(base64Photo: avatarBase64),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
