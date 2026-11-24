import 'package:flutter/material.dart';

import '../ui2/anix_kit.dart';
import '../ui2/luxe.dart';
import '../ui2/page_turn.dart';

/// ANIX design tokens. Legacy gameplay colors remain stable; the app chrome
/// reads [NxThemeColors] from the active theme instead.
class NxColors {
  NxColors._();
  /// Secondary highlight ("you", "owned", "done"): Station Luxe champagne. It replaced the retired neon turquoise
  /// (0xFF2EE6D6) so no screen keeps a second accent language next to gold.
  static const champagne = Color(0xFFF6E7BD);

  /// Gameplay-only colour (NX Cards card colour, Mafia / Quiz in-board highlights): a game piece needs four
  /// distinguishable colours, so this stays inside game boards. App chrome uses [champagne].
  static const turquoise = Color(0xFF2EE6D6);
  static const gold = Color(0xFFD9B872);
  static const pink = Color(0xFFFF4FA3);
  static const danger = Color(0xFFFF5A6E);
  static const success = Color(0xFF3DDC97);
  static const glass = Color(0x14FFFFFF);
  static const textDim = Color(0x99F4EAD2);

  // ---- Station Luxe tokens (single art direction) --------------------------------------
  // The home page's palette: black, warm charcoal, gold. Screens use these names; nothing in
  // the app should introduce a second background/accent language.
  static const luxeBg = Color(0xFF07080C);
  static const panel = Color(0xFF14130F);
  static const panelWarm = Color(0xFF1D1B15);
  static const goldLine = Color(0x33D9B872);
  static const ink = Color(0xFFF4EAD2);
  static const mutedInk = Color(0x99F4EAD2);
  static const goldDeep = Color(0xFF8A6A2F);
}

enum NxAppearanceMode { dark, light }

enum NxVisualTheme { gold, neon }

/// Colors and surface treatment for the two selectable ANIX visual themes.
class NxThemeColors extends ThemeExtension<NxThemeColors> {
  const NxThemeColors({
    required this.accent,
    required this.accentSecondary,
    required this.background,
    required this.backgroundMid,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.muted,
    this.premiumPanels = true,
  });

  final Color accent;
  final Color accentSecondary;
  final Color background;
  final Color backgroundMid;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color muted;
  final bool premiumPanels;

  /// Station Luxe (black / gold / champagne) — the one app skin. It is identical to [neon] so a user
  /// who picked the old "gold" preset in settings lands on the same home-page palette instead of the
  /// retired navy theme; the preset name is kept for settings compatibility.
  static const gold = NxThemeColors(
    accent: Color(0xFFD9B872),
    accentSecondary: Color(0xFF8A6A2C),
    background: Color(0xFF07080C),
    backgroundMid: Color(0xFF12110D),
    surface: Color(0xE6141310),
    surfaceRaised: Color(0xF01C1A14),
    border: Color(0xFF8A6A2C),
    text: Color(0xFFF4EAD2),
    muted: Color(0xFFB9AE95),
  );

  /// App skin: ANIX PRO Station Luxe (black / gold / champagne). Name kept for settings compatibility.
  static const neon = NxThemeColors(
    accent: Color(0xFFD9B872),
    accentSecondary: Color(0xFF8A6A2C),
    background: Color(0xFF07080C),
    backgroundMid: Color(0xFF12110D),
    surface: Color(0xE6141310),
    surfaceRaised: Color(0xF01C1A14),
    border: Color(0xFF8A6A2C),
    text: Color(0xFFF4EAD2),
    muted: Color(0xFFB9AE95),
  );

  static const goldLight = NxThemeColors(
    accent: Color(0xFF9A6500),
    accentSecondary: Color(0xFF8A4B08),
    background: Color(0xFFFFFBF1),
    backgroundMid: Color(0xFFFFF2D4),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFF7E5),
    border: Color(0xFFC49A48),
    text: Color(0xFF241A08),
    muted: Color(0xFF6C5A38),
  );

  /// Visual language inside active game boards and their HUDs: the same Station Luxe skin as
  /// the rest of the app (a board must not be the one blue screen in a gold app).
  static const gameplay = NxThemeColors(
    accent: Color(0xFFD9B872),
    accentSecondary: Color(0xFF8A6A2C),
    background: Color(0xFF07080C),
    backgroundMid: Color(0xFF12110D),
    surface: Color(0xE6141310),
    surfaceRaised: Color(0xF01C1A14),
    border: Color(0xFF8A6A2C),
    text: Color(0xFFF4EAD2),
    muted: Color(0xFFB9AE95),
    premiumPanels: false,
  );

  static NxThemeColors of(BuildContext context) =>
      Theme.of(context).extension<NxThemeColors>() ?? neon;

  @override
  NxThemeColors copyWith({
    Color? accent,
    Color? accentSecondary,
    Color? background,
    Color? backgroundMid,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? text,
    Color? muted,
    bool? premiumPanels,
  }) {
    return NxThemeColors(
      accent: accent ?? this.accent,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      background: background ?? this.background,
      backgroundMid: backgroundMid ?? this.backgroundMid,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      premiumPanels: premiumPanels ?? this.premiumPanels,
    );
  }

  @override
  NxThemeColors lerp(ThemeExtension<NxThemeColors>? other, double t) {
    if (other is! NxThemeColors) return this;
    return NxThemeColors(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t) ??
          accentSecondary,
      background: Color.lerp(background, other.background, t) ?? background,
      backgroundMid:
          Color.lerp(backgroundMid, other.backgroundMid, t) ?? backgroundMid,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceRaised:
          Color.lerp(surfaceRaised, other.surfaceRaised, t) ?? surfaceRaised,
      border: Color.lerp(border, other.border, t) ?? border,
      text: Color.lerp(text, other.text, t) ?? text,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      premiumPanels: t < 0.5 ? premiumPanels : other.premiumPanels,
    );
  }
}

/// Per-world accent colours.
///
/// One visual identity: **Station Luxe** (black, gold, champagne) is the app skin, and the
/// home page (`HubPage`) is the reference for it. Every world therefore shares the same
/// background ramp ([background]) and only varies the [primary] accent that tints its own
/// glows and chips — that is what keeps the Arcade, Rooms, Social, ORACLE and the profile
/// pages feeling like one application instead of seven themes. The accent is a tint on
/// top of gold, never a replacement for it: `WorldPalette` no longer carries light-mode
/// gradients (the profile world used to flip the whole app to a pale lavender) because a
/// page that ignores the home-page palette breaks the identity.
class WorldPalette {
  const WorldPalette(this.primary, this.secondary, List<Color> ramp,
      {this.light = false})
      : background = _luxeRamp;

  final Color primary;
  final Color secondary;

  /// Background ramp — always the Station Luxe ramp (kept identical to `Luxe.bg` and
  /// `Nx2.deep` so a page painted with `NxBackground` and one painted with `LuxeScene`
  /// stack without a visible seam).
  final List<Color> background;

  /// Kept for API compatibility (settings/quality code reads it). No world is light any
  /// more: the app has a single dark luxe skin.
  final bool light;

  /// Black → warm charcoal → black, the ramp behind every screen.
  static const List<Color> _luxeRamp = <Color>[
    Color(0xFF07080C),
    Color(0xFF12110D),
    Color(0xFF07080C),
  ];

  /// Gold, the identity accent.
  static const Color gold = Color(0xFFD9B872);
  static const Color champagne = Color(0xFFF6E7BD);
  static const Color bronze = Color(0xFF8A6A2C);

  static const hub = WorldPalette(gold, champagne, _luxeRamp);
  static const nova = WorldPalette(Color(0xFFE7B7C9), champagne, _luxeRamp);
  static const orbit = WorldPalette(Color(0xFFB8CBB0), champagne, _luxeRamp);
  static const arcade = WorldPalette(Color(0xFFE5C07B), champagne, _luxeRamp);
  static const oracle = WorldPalette(Color(0xFFC9B8E8), champagne, _luxeRamp);
  static const personal = WorldPalette(gold, champagne, _luxeRamp);
  static const social = WorldPalette(Color(0xFFC7C0A8), champagne, _luxeRamp);
  static const exchange = WorldPalette(gold, champagne, _luxeRamp);
}

class NxSpace {
  NxSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class NxRadius {
  NxRadius._();
  static const sm = 10.0;
  static const md = 16.0;
  static const lg = 24.0;
}

class NxMotion {
  NxMotion._();
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 280);
  static const slow = Duration(milliseconds: 520);
  static const curve = Curves.easeOutCubic;
}

/// The NX2 redesign ships one skin: cosmic neon. [style] is kept for API compatibility.
ThemeData buildNxTheme([
  NxVisualTheme style = NxVisualTheme.neon,
  NxAppearanceMode appearance = NxAppearanceMode.dark,
]) => _buildTheme(
      // One skin: light mode is the Station Luxe light palette for either preset (the lavender "neon light"
      // skin of the retired navy/neon look is gone).
      appearance == NxAppearanceMode.light
          ? NxThemeColors.goldLight
          : (style == NxVisualTheme.gold ? NxThemeColors.gold : NxThemeColors.neon),
      appearance,
    );

/// Preserve the original Finger Soccer field, ball and player-disc palette.
ThemeData buildNxGameplayTheme() =>
    _buildTheme(NxThemeColors.gameplay, NxAppearanceMode.dark);

/// Ink used on gold fills (the same near-black as the Luxe buttons).
const Color _luxeInk = Color(0xFF14120C);

ThemeData _buildTheme(NxThemeColors visual, NxAppearanceMode appearance) {
  final scheme = (appearance == NxAppearanceMode.light
          ? ColorScheme.light
          : ColorScheme.dark)(
    primary: visual.accent,
    secondary: visual.accentSecondary,
    tertiary:
        visual.premiumPanels ? visual.accentSecondary : NxColors.champagne,
    surface: visual.surfaceRaised,
    error: NxColors.danger,
    onPrimary: appearance == NxAppearanceMode.light ? Colors.white : const Color(0xFF08101A),
    onSurface: visual.text,
  );
  final bool isDark = appearance == NxAppearanceMode.dark;
  // Station Luxe chrome: the exact panel gradient stops of the home page's sheets/dialogs,
  // so Material dialogs, sheets and menus sit on the same warm charcoal as LuxeCard.
  final Color chromePanel = isDark ? const Color(0xFF14130F) : visual.surfaceRaised;
  final Color chromeSheet = isDark ? const Color(0xFF0F0E0B) : visual.surfaceRaised;
  final Color chromeChip = isDark ? const Color(0xE61C1912) : visual.surface;
  final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: isDark ? Brightness.dark : Brightness.light,
      // Every Material default (FAB labels, chips, buttons with their own text styles) uses the app fonts too.
      fontFamily: kNxFont,
      fontFamilyFallback: kNxFontFallback);
  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[visual],
    pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: NxPageTurnTransitionsBuilder(),
      TargetPlatform.iOS: NxPageTurnTransitionsBuilder(),
      TargetPlatform.linux: NxPageTurnTransitionsBuilder(),
      TargetPlatform.macOS: NxPageTurnTransitionsBuilder(),
      TargetPlatform.windows: NxPageTurnTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: visual.background,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: visual.text,
      titleTextStyle: TextStyle(
          fontFamily: kNxFontHead,
          fontFamilyFallback: kNxFontHeadFallback,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: visual.text),
    ),
    textTheme: nxGameTextTheme(base.textTheme)
        .apply(bodyColor: visual.text, displayColor: visual.text),
    iconTheme: IconThemeData(color: visual.text),
    cardTheme: CardThemeData(
      color: visual.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        side: BorderSide(color: visual.border.withValues(alpha: 0.35)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: visual.surface.withValues(alpha: 0.82),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.border.withValues(alpha: 0.46)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.border.withValues(alpha: 0.38)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        borderSide: BorderSide(color: visual.accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: visual.muted),
      hintStyle: TextStyle(color: visual.muted.withValues(alpha: 0.82)),
    ),
    // Material buttons are drawn as the Station Luxe button (same gold gradient, same
    // pill radius, same ink) so legacy call sites look native on the home-page palette.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: visual.accent,
        foregroundColor: _luxeInk,
        disabledBackgroundColor: visual.accent.withValues(alpha: 0.32),
        disabledForegroundColor: _luxeInk.withValues(alpha: 0.6),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontFamily: kNxFont,
            fontFamilyFallback: kNxFontFallback,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: visual.text,
        side: BorderSide(color: visual.accent.withValues(alpha: 0.55)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontFamily: kNxFont, fontFamilyFallback: kNxFontFallback, fontWeight: FontWeight.w800),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? const Color(0xF21C1A14) : visual.surfaceRaised,
      contentTextStyle: TextStyle(
          fontFamily: kNxFont,
          fontFamilyFallback: kNxFontFallback,
          fontWeight: FontWeight.w700,
          color: visual.text),
      actionTextColor: visual.accent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        side: BorderSide(color: visual.border.withValues(alpha: 0.45)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: chromePanel,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
          fontFamily: kNxFontHead,
          fontFamilyFallback: kNxFontHeadFallback,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: visual.text),
      contentTextStyle: TextStyle(
          fontFamily: kNxFont,
          fontFamilyFallback: kNxFontFallback,
          fontSize: 13.5,
          height: 1.45,
          color: visual.muted),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LuxeRadius.lg),
        side: BorderSide(color: visual.accent.withValues(alpha: 0.30)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: chromeSheet,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: chromeSheet,
      showDragHandle: true,
      dragHandleColor: visual.accent.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(LuxeRadius.lg)),
      ),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: visual.accent,
      unselectedLabelColor: visual.muted,
      indicatorColor: visual.accent,
      dividerColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: visual.accent),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: chromePanel,
      indicatorColor: visual.accentSecondary.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800, color: visual.text)),
      iconTheme: WidgetStatePropertyAll<IconThemeData>(
          IconThemeData(color: visual.text)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: chromeChip,
      selectedColor: visual.accentSecondary.withValues(alpha: 0.45),
      side: BorderSide(color: visual.border.withValues(alpha: 0.7)),
      labelStyle: TextStyle(color: visual.text, fontWeight: FontWeight.w700),
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
          s.contains(WidgetState.selected) ? Colors.white : visual.muted),
      trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> s) =>
          s.contains(WidgetState.selected)
              ? visual.accentSecondary
              : const Color(0x33FFFFFF)),
    ),
    // ANIX tooltip pack: compact panel with its pointer, opening above the target.
    tooltipTheme: TooltipThemeData(
      decoration: anixTooltipDecoration(),
      preferBelow: false,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(
          fontFamily: kNxFont,
          fontFamilyFallback: kNxFontFallback,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFFF4EAD2)),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: visual.accent,
      thumbColor: Colors.white,
      inactiveTrackColor: const Color(0x33FFFFFF),
    ),
    // Everything below exists so legacy pages that still use raw Material widgets (menus, list tiles,
    // spinners, checkboxes, sheets) inherit the same chrome as the pages rebuilt on the Luxe kit.
    dividerTheme: DividerThemeData(
      color: visual.border.withValues(alpha: 0.28),
      thickness: 1,
      space: 1,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: chromePanel,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NxRadius.md),
        side: BorderSide(color: visual.border.withValues(alpha: 0.45)),
      ),
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(TextStyle(
          fontFamily: kNxFont,
          fontFamilyFallback: kNxFontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: visual.text)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: visual.text, fontFamily: kNxFont),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(chromePanel),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.md)),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: visual.text,
      iconColor: visual.muted,
      selectedColor: visual.accent,
      selectedTileColor: visual.accent.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.sm)),
      minVerticalPadding: 10,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: visual.accent,
        textStyle: const TextStyle(
            fontFamily: kNxFont, fontFamilyFallback: kNxFontFallback, fontWeight: FontWeight.w800),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: visual.text,
        highlightColor: visual.accent.withValues(alpha: 0.16),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> st) =>
          st.contains(WidgetState.selected) ? visual.accent : Colors.transparent),
      checkColor: const WidgetStatePropertyAll<Color>(Color(0xFF07080C)),
      side: BorderSide(color: visual.border.withValues(alpha: 0.7), width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> st) =>
          st.contains(WidgetState.selected) ? visual.accent : visual.muted),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> st) =>
            st.contains(WidgetState.selected)
                ? visual.accent.withValues(alpha: 0.22)
                : chromeChip),
        foregroundColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> st) =>
            st.contains(WidgetState.selected) ? visual.accent : visual.muted),
        side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: visual.border.withValues(alpha: 0.4))),
        textStyle: const WidgetStatePropertyAll<TextStyle>(TextStyle(
            fontFamily: kNxFont, fontFamilyFallback: kNxFontFallback, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}


// ------------------------------------------------------------------ fonts (bundled, OFL)
/// Latin + digits: Chakra Petch (HUD/game look). Persian uses Estedad for a
/// consistent, readable shape across body text, buttons and headings.
const String kNxFont = 'ChakraPetch';
const List<String> kNxFontFallback = <String>['Estedad'];
const String kNxFontHead = 'ChakraPetch';
const List<String> kNxFontHeadFallback = <String>['Estedad'];

TextTheme nxGameTextTheme(TextTheme t) {
  TextStyle? body(TextStyle? s) => s?.copyWith(fontFamily: kNxFont, fontFamilyFallback: kNxFontFallback);
  TextStyle? head(TextStyle? s) => s?.copyWith(fontFamily: kNxFontHead, fontFamilyFallback: kNxFontHeadFallback);
  return t.copyWith(
    displayLarge: head(t.displayLarge),
    displayMedium: head(t.displayMedium),
    displaySmall: head(t.displaySmall),
    headlineLarge: head(t.headlineLarge),
    headlineMedium: head(t.headlineMedium),
    headlineSmall: head(t.headlineSmall),
    titleLarge: head(t.titleLarge),
    titleMedium: body(t.titleMedium),
    titleSmall: body(t.titleSmall),
    bodyLarge: body(t.bodyLarge),
    bodyMedium: body(t.bodyMedium),
    bodySmall: body(t.bodySmall),
    labelLarge: body(t.labelLarge),
    labelMedium: body(t.labelMedium),
    labelSmall: body(t.labelSmall),
  );
}
