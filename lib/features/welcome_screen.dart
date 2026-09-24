import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/seamly_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SeamlyColors.sand,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = math.max(300.0, constraints.maxHeight * 0.36);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: constraints.maxHeight - panelHeight + 28,
                child: const _ClothesRackImage(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: panelHeight,
                child: Container(
                  decoration: const BoxDecoration(
                    color: SeamlyColors.sand,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    30,
                    32,
                    30,
                    math.max(24, MediaQuery.paddingOf(context).bottom + 18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Welcome to',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _WelcomeBrand(),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 196,
                        height: 52,
                        child: FilledButton(
                          key: const ValueKey('welcome-next'),
                          onPressed: onContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF9D7558),
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          child: const Text(
                            'NEXT',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClothesRackImage extends StatelessWidget {
  const _ClothesRackImage();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sourceWidth = constraints.maxWidth * 2;
        final sourceHeight = constraints.maxHeight * 2;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: sourceWidth,
            maxWidth: sourceWidth,
            minHeight: sourceHeight,
            maxHeight: sourceHeight,
            child: Image.asset(
              'assets/images/partner_collage.png',
              width: sourceWidth,
              height: sourceHeight,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.high,
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeBrand extends StatelessWidget {
  const _WelcomeBrand();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/seamly_logo.png',
            width: 104,
            height: 104,
            fit: BoxFit.contain,
            semanticLabel: 'Seamly logo',
          ),
          const SizedBox(width: 12),
          const Text(
            'Seamly',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'Georgia',
              fontSize: 48,
              fontStyle: FontStyle.italic,
              letterSpacing: -2.2,
            ),
          ),
        ],
      ),
    );
  }
}
