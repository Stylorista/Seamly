import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/stylorista_theme.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, this.base64Photo, this.radius = 22});

  final String? base64Photo;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;
    try {
      if (base64Photo != null) bytes = base64Decode(base64Photo!);
    } on FormatException {
      // Older or damaged local cache must not prevent opening account settings.
    }
    return ClipOval(
      child: ColoredBox(
        color: StyloristaColors.sand.withValues(alpha: 0.22),
        child: SizedBox.square(
          dimension: radius * 2,
          child: bytes == null
              ? Icon(
                  Icons.person_outline_rounded,
                  size: radius * 1.15,
                  color: StyloristaColors.ink,
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.person_outline_rounded,
                    size: radius * 1.15,
                    color: StyloristaColors.ink,
                  ),
                ),
        ),
      ),
    );
  }
}
