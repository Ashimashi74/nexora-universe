import 'package:flutter/material.dart';

/// ANIX brand artwork (NX emblem + ANIX wordmark), generated from the owner's NX primary logo.
class AnixBrand {
  const AnixBrand._();
  static const String logo = 'assets/branding/anix_logo.webp';
  static const String mark = 'assets/branding/anix_mark.webp';
  static const String wordmark = 'assets/branding/anix_wordmark.webp';

  /// Home screen emblem: the owner's NX ring logo with the ANIX wordmark.
  static const String homeLogo = 'assets/branding/home_logo_anix.webp';

  /// The same logo exactly as supplied (NEXORA wordmark), kept in case the owner prefers it.
  static const String homeLogoNexora = 'assets/branding/home_logo_nexora.webp';
}

/// The stacked ANIX logo (emblem above the wordmark). [height] is the full logo height.
class AnixLogo extends StatelessWidget {
  const AnixLogo({super.key, this.height = 120, this.markOnly = false});
  final double height;
  final bool markOnly;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'ANIX',
        image: true,
        child: Image.asset(
          markOnly ? AnixBrand.mark : AnixBrand.logo,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) => SizedBox(
            height: height,
            child: Center(
              child: Text('ANIX',
                  style: TextStyle(
                      color: const Color(0xFFF4C860), fontWeight: FontWeight.w900, fontSize: height * .3, letterSpacing: 2)),
            ),
          ),
        ),
      );
}
