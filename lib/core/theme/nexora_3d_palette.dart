import 'package:flutter/material.dart';

/// NEXORA — THE COMPLETE 3D DIGITAL UNIVERSE
/// Official Brand Color Palette (Part 3 — Complete 3D Design System).
class Nexora3dPalette {
  const Nexora3dPalette._();

  static const Color midnightNavy = Color(0xFF0B0A2A);
  static const Color deepSpaceBlue = Color(0xFF11143D);
  static const Color electricBlue = Color(0xFF526BFF);
  static const Color violet = Color(0xFF805CFF);
  static const Color warmOrange = Color(0xFFFF9A3C);
  static const Color coralPink = Color(0xFFFF4F8B);
  static const Color softWhite = Color(0xFFF5F5FF);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[electricBlue, violet],
  );

  static const LinearGradient spaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[midnightNavy, deepSpaceBlue],
  );
}
