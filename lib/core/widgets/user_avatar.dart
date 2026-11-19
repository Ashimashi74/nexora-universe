import 'package:flutter/material.dart';

import '../ui2/anix_kit.dart';
import '../ui2/nx2_widgets.dart';

/// Small round avatar for any player: an uploaded photo (https url), one of the painted ANIX avatars (id) or initials.
class NxUserAvatar extends StatelessWidget {
  const NxUserAvatar({super.key, required this.avatar, required this.name, this.size = 36, this.ring});
  final String? avatar;
  final String name;
  final double size;

  /// Optional ring colour (e.g. speaking / manager highlight).
  final Color? ring;

  static bool isPhoto(String? a) => a != null && (a.startsWith('https://') || a.startsWith('http://'));

  @override
  Widget build(BuildContext context) {
    final String? a = avatar;
    final String initials = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    Widget fallback() => Container(
          color: Nx2.plum,
          alignment: Alignment.center,
          child: Text(initials,
              style: TextStyle(color: Nx2.text, fontWeight: FontWeight.w900, fontSize: size * 0.42)),
        );
    Widget img;
    if (isPhoto(a)) {
      img = Image.network(a!, fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, __, ___) => fallback());
    } else if (a != null && AnixAssets.avatarIds.contains(a)) {
      img = Image.asset(AnixAssets.avatar(a), fit: BoxFit.cover, width: size, height: size,
          cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => fallback());
    } else {
      img = fallback();
    }
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring == null ? 0 : 2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring ?? Colors.transparent),
      child: ClipOval(child: img),
    );
  }
}
