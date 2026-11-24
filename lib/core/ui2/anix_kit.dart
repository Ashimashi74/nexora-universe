import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/nx_theme.dart';

/// ANIX component kit: the owner's runtime art packs (buttons, toggles/checkboxes, modal + sheet
/// panels, tooltips/popovers, navigation icons, game card shells, rank emblems, avatar set +
/// frames and the three scene backgrounds), converted to webp under assets/ui/anix/.
/// Every widget here draws the pack art 9-slice so corners/caps/pointers keep their shape.
class AnixAssets {
  const AnixAssets._();
  static const String _r = 'assets/ui/anix';

  // Scene backgrounds (1080x2400).
  static const String bgWorldHub = '$_r/bg/world_hub.webp';
  static const String bgSocial = '$_r/bg/social.webp';
  static const String bgArcade = '$_r/bg/arcade.webp';

  /// [style] primary|secondary|ghost|destructive-neutral|disabled,
  /// [state] normal|pressed|focused|loading|high-contrast, [size] large|compact.
  static String button(String style, String state, String size) => '$_r/buttons/$style-$state-$size.webp';

  /// toggle-on/off, toggle-pressed-on/off, toggle-disabled-on/off, toggle-focused-on/off; checkbox-*.
  static String toggle(String name) => '$_r/toggle/$name.webp';

  /// [panel] small|medium|fullscreen|bottom-sheet, [state] normal|active|disabled|high-contrast.
  static String modal(String panel, [String state = 'normal']) => '$_r/modal/$panel-$state.webp';

  /// [kind] tooltip-compact|popover-medium, [side] top|bottom|left|right (side that carries the pointer).
  static String tip(String kind, String side, [String state = 'normal']) => '$_r/tooltip/$kind-$side-$state.webp';

  /// [icon] home|worlds|chat|arcade|rewards|shop|profile|menu, [state] normal|active|pressed|disabled|high-contrast.
  static String nav(String icon, [String state = 'normal']) => '$_r/nav/$icon-$state.webp';

  /// [orientation] portrait|landscape, [state] normal|pressed|disabled|high-contrast.
  static String card(String orientation, [String state = 'normal']) => '$_r/card/card-$orientation-$state.webp';

  static String rank(AnixTier tier, [String state = 'normal']) => '$_r/rank/${tier.name}-$state.webp';

  /// Frames exist for bronze..master (+ seasonal); grandmaster uses the master frame.
  static String frame(AnixTier tier, [String state = 'normal']) =>
      '$_r/frames/${tier == AnixTier.grandmaster ? 'master' : tier.name}-$state.webp';

  static String avatar(String id) => '$_r/avatars/$id.webp';

  /// Painted 3D icons (`assets/ui/anix/icons/<name>.webp`), e.g. 'trophy_gold', 'mic', 'chat', 'versus'.
  static String icon(String name) => '$_r/icons/$name.webp';
  static const List<String> iconNames = <String>[
    'backgammon', 'calendar', 'cards', 'chat', 'chess', 'cup', 'friends', 'gamepad', 'gift', 'headset',
    'joystick', 'leaderboard', 'ludo', 'mafia', 'megaphone', 'mic', 'poker', 'pool', 'rocket', 'roulette',
    'settings', 'shield', 'shop', 'snake', 'soccer', 'star', 'target', 'trophy_gold', 'versus', 'wheel',
  ];

  /// Tournament trophies: bronze, silver, gold, diamond, amethyst, champion.
  static String trophy(String tier) => '$_r/trophies/$tier.webp';
  static const List<String> trophyTiers = <String>['bronze', 'silver', 'gold', 'diamond', 'amethyst', 'champion'];

  /// Trophy for a finishing place (1 = champion cup, 2 = silver, 3 = bronze, otherwise null).
  static String? trophyForPlace(int place) => switch (place) {
        1 => trophy('champion'),
        2 => trophy('silver'),
        3 => trophy('bronze'),
        _ => null,
      };

  // Scene backgrounds.
  static const String sceneVoiceStage = '$_r/scenes/voice_stage.webp';
  static const String sceneTrophyHall = '$_r/scenes/trophy_hall.webp';
  static const String sceneHubPanorama = '$_r/scenes/hub_panorama.webp';
  static const String scenePortalBlue = '$_r/scenes/portal_blue.webp';
  static const String scenePortalGold = '$_r/scenes/portal_gold.webp';
  /// Owner art 2026-11: hub gate panorama (landscape), arena portal card and the champions' podium.
  static const String sceneHubGate = '$_r/scenes/hub_gate.webp';
  static const String sceneArenaPortal = '$_r/scenes/arena_portal_card.webp';
  static const String sceneArenaPodium = '$_r/scenes/arena_podium.webp';

  /// Tournament bracket kit (owner art 2026-11): match pills, slot / status icons, champion crest, progress rail.
  static String bracket(String name) => '$_r/bracket/$name.webp';

  /// Painted icon for a menu route (null = keep the vector icon).
  static String? iconForRoute(String path) => switch (path) {
        '/hub' => icon('rocket'),
        '/tournaments' => icon('trophy_gold'),
        '/leaderboard' => icon('leaderboard'),
        '/rooms' => icon('mic'),
        '/settings' => icon('settings'),
        '/account' => icon('shield'),
        '/world/arcade' => icon('gamepad'),
        '/world/social_hub' || '/world/social_station' => icon('chat'),
        '/world/orbit_network' => icon('friends'),
        '/world/nexora_exchange' => icon('shop'),
        '/onboarding' => icon('star'),
        _ => null,
      };

  static const List<String> avatarIds = <String>[
    '01-vanguard', '02-cyber-scout', '03-moon-elf', '04-iron-warden', '05-crimson-duelist', '06-onyx-knight',
    '07-star-fox', '08-void-assassin', '09-arcane-scholar', '10-frostborn', '11-sprout-drone', '12-shadow-mage',
    '13-elder-sage', '14-stonebreaker', '15-violet-psion', '16-golden-sentinel', '17-neon-ranger', '18-bark-guardian',
    '19-night-elf', '20-rune-touched', '21-goggle-fox', '22-hooded-oracle', '23-nova-pilot', '24-lumen-android',
  ];
  static const String defaultAvatar = '01-vanguard';

  static String avatarName(String id, bool fa) {
    final String raw = id.length > 3 ? id.substring(3) : id;
    return raw.split('-').map((String w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}

/// Rank tiers of the emblem pack.
enum AnixTier { bronze, silver, gold, platinum, diamond, master, grandmaster }

/// Tier from the player level (same bands as the rank titles, extended to the emblem pack).
AnixTier anixTierForLevel(int level) {
  if (level >= 60) return AnixTier.grandmaster;
  if (level >= 40) return AnixTier.master;
  if (level >= 25) return AnixTier.diamond;
  if (level >= 15) return AnixTier.platinum;
  if (level >= 8) return AnixTier.gold;
  if (level >= 3) return AnixTier.silver;
  return AnixTier.bronze;
}

/// Tier from an online game rating (Elo, everybody starts at 1000).
AnixTier anixTierForRating(int rating) {
  if (rating >= 2000) return AnixTier.grandmaster;
  if (rating >= 1800) return AnixTier.master;
  if (rating >= 1600) return AnixTier.diamond;
  if (rating >= 1400) return AnixTier.platinum;
  if (rating >= 1200) return AnixTier.gold;
  if (rating >= 1000) return AnixTier.silver;
  return AnixTier.bronze;
}

String anixTierName(AnixTier t, bool fa) => switch (t) {
      AnixTier.bronze => fa ? 'برنز' : 'Bronze',
      AnixTier.silver => fa ? 'نقره' : 'Silver',
      AnixTier.gold => fa ? 'طلا' : 'Gold',
      AnixTier.platinum => fa ? 'پلاتین' : 'Platinum',
      AnixTier.diamond => fa ? 'الماس' : 'Diamond',
      AnixTier.master => fa ? 'استاد' : 'Master',
      AnixTier.grandmaster => fa ? 'استاد بزرگ' : 'Grandmaster',
    };


// ------------------------------------------------------------------------------------------ 9-slice

/// Draws pack art as a true 9-slice: [center] is in image pixels and every border is drawn at
/// image-pixels / [scale] logical pixels (Flutter's DecorationImage does not scale slice borders).
class AnixNineSlice extends StatefulWidget {
  const AnixNineSlice({
    super.key,
    required this.asset,
    required this.center,
    required this.scale,
    this.child,
    this.opacity = 1,
  });
  final String asset;
  final Rect center;

  /// Image pixels per logical pixel.
  final double scale;
  final Widget? child;
  final double opacity;

  @override
  State<AnixNineSlice> createState() => _AnixNineSliceState();
}

class _AnixNineSliceState extends State<AnixNineSlice> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AnixNineSlice old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final ImageStream next = AssetImage(widget.asset).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == next.key) return;
    _unlisten();
    _stream = next;
    _listener = ImageStreamListener((ImageInfo info, bool _) {
      if (!mounted) return;
      setState(() => _image = info.image);
    }, onError: (Object _, StackTrace? __) {});
    next.addListener(_listener!);
  }

  void _unlisten() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _NinePainter(_image, widget.center, widget.scale, widget.opacity),
        child: widget.child,
      );
}

class _NinePainter extends CustomPainter {
  _NinePainter(this.image, this.center, this.scale, this.opacity);
  final ui.Image? image;
  final Rect center;
  final double scale;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? img = image;
    if (img == null || size.isEmpty) return;
    // Borders must fit: shrink the scale so left+right / top+bottom borders never exceed the box.
    final double bw = img.width - center.width, bh = img.height - center.height;
    double s = scale;
    if (bw / s > size.width) s = bw / size.width;
    if (bh / s > size.height) s = bh / size.height;
    canvas.save();
    canvas.scale(1 / s);
    final Paint p = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.drawImageNine(img, center, Rect.fromLTWH(0, 0, size.width * s, size.height * s), p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NinePainter old) =>
      old.image != image || old.center != center || old.scale != scale || old.opacity != opacity;
}

// ------------------------------------------------------------------------------------------ buttons

enum AnixButtonStyle { primary, secondary, ghost, destructive }

/// Pack button (5 styles x 5 states x 2 sizes), 9-slice: the rounded end caps never stretch.
class AnixButton extends StatefulWidget {
  const AnixButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.style = AnixButtonStyle.primary,
    this.height = 52,
    this.fontSize = 16,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final AnixButtonStyle style;
  final double height;
  final double fontSize;
  final bool loading;

  @override
  State<AnixButton> createState() => _AnixButtonState();
}

class _AnixButtonState extends State<AnixButton> {
  bool _down = false;
  bool _focus = false;

  String get _styleName => switch (widget.style) {
        AnixButtonStyle.primary => 'primary',
        AnixButtonStyle.secondary => 'secondary',
        AnixButtonStyle.ghost => 'ghost',
        AnixButtonStyle.destructive => 'destructive-neutral',
      };

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null && !widget.loading;
    final bool large = widget.height >= 50;
    final String size = large ? 'large' : 'compact';
    // The pack's loading art bakes its spinner into the stretchable centre, so loading draws the
    // normal art with a native spinner instead.
    final String state = !enabled ? 'normal' : (_down ? 'pressed' : (_focus ? 'focused' : 'normal'));
    final String asset = AnixAssets.button(widget.onTap == null && !widget.loading ? 'disabled' : _styleName, state, size);
    // Canvas: large 320x96 (caps 48), compact 192x72 (caps 36).
    final double canvasH = large ? 96 : 72;
    final double cap = canvasH / 2;
    final double canvasW = large ? 320 : 192;
    final Rect slice = Rect.fromLTRB(cap, cap - 1, canvasW - cap, cap + 1);
    final Color fg = switch (widget.style) {
      AnixButtonStyle.ghost => const Color(0xFFBFF3FF),
      _ => Colors.white,
    };
    final List<BoxShadow> glow = enabled && widget.style == AnixButtonStyle.primary
        ? <BoxShadow>[
            BoxShadow(
                color: const Color(0xFF2FD3FF).withValues(alpha: _down ? 0.25 : 0.38),
                blurRadius: widget.height * 0.42,
                spreadRadius: -widget.height * 0.12),
          ]
        : const <BoxShadow>[];
    final Widget face = AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: const Duration(milliseconds: 110),
      child: Container(
        height: widget.height,
        constraints: BoxConstraints(minWidth: widget.height * (widget.loading ? 2.4 : 1.2)),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(widget.height / 2), boxShadow: glow),
        child: AnixNineSlice(
          asset: asset,
          center: slice,
          scale: canvasH / widget.height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.height * 0.34),
            child: widget.loading
            ? const SizedBox.shrink() // the loading art carries its own spinner
            : Opacity(
                opacity: enabled ? 1 : 0.55,
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                  if (widget.icon != null) ...<Widget>[
                    Icon(widget.icon, color: fg, size: widget.fontSize + 4),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontWeight: FontWeight.w900,
                            fontSize: widget.fontSize,
                            letterSpacing: 0.8,
                            shadows: const <Shadow>[Shadow(color: Color(0x99000000), blurRadius: 6)])),
                  ),
                ]),
              ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (bool v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          child: face,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------ toggles

/// Pack toggle (160x88 art, gold glow on the "on" state).
class AnixToggle extends StatefulWidget {
  const AnixToggle({super.key, required this.value, required this.onChanged, this.width = 54});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;

  @override
  State<AnixToggle> createState() => _AnixToggleState();
}

class _AnixToggleState extends State<AnixToggle> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final String onOff = widget.value ? 'on' : 'off';
    final String name = !enabled ? 'toggle-disabled-$onOff' : (_down ? 'toggle-pressed-$onOff' : 'toggle-$onOff');
    final double h = widget.width * 88 / 160;
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onChanged!(!widget.value);
              }
            : null,
        child: SizedBox(
          width: widget.width,
          height: h,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Image.asset(AnixAssets.toggle(name),
                key: ValueKey<String>(name),
                width: widget.width,
                height: h,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                cacheWidth: (widget.width * 3).round(),
                errorBuilder: (_, __, ___) => Switch(value: widget.value, onChanged: widget.onChanged)),
          ),
        ),
      ),
    );
  }
}

/// Pack checkbox.
class AnixCheckbox extends StatefulWidget {
  const AnixCheckbox({super.key, required this.value, required this.onChanged, this.size = 30});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  State<AnixCheckbox> createState() => _AnixCheckboxState();
}

class _AnixCheckboxState extends State<AnixCheckbox> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onChanged != null;
    final String c = widget.value ? 'checked' : 'unchecked';
    final String name = !enabled ? 'checkbox-disabled-$c' : (_down ? 'checkbox-pressed-$c' : 'checkbox-$c');
    return Semantics(
      checked: widget.value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onChanged!(!widget.value);
              }
            : null,
        child: Image.asset(AnixAssets.toggle(name),
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            cacheWidth: (widget.size * 3).round(),
            errorBuilder: (_, __, ___) => Checkbox(value: widget.value, onChanged: (bool? v) => widget.onChanged?.call(v ?? false))),
      ),
    );
  }
}

/// Drop-in for SwitchListTile with the pack toggle.
class AnixSwitchTile extends StatelessWidget {
  const AnixSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
    this.activeColor,
  });
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;

  /// Ignored (the pack art defines the colours); kept so call sites stay unchanged.
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: secondary,
      title: title,
      subtitle: subtitle,
      dense: dense,
      contentPadding: contentPadding,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: AnixToggle(value: value, onChanged: onChanged),
    );
  }
}

/// Drop-in for CheckboxListTile with the pack checkbox (trailing, like the Material default).
class AnixCheckboxTile extends StatelessWidget {
  const AnixCheckboxTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
    this.activeColor,
  });
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: secondary,
      title: title,
      subtitle: subtitle,
      dense: dense,
      contentPadding: contentPadding,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: AnixCheckbox(value: value, onChanged: onChanged == null ? null : (bool v) => onChanged!(v)),
    );
  }
}

// ------------------------------------------------------------------------------------------ panels

enum AnixPanelSize { small, medium, fullscreen, sheet }

/// Modal / panel family frame, 9-slice. Content is forced onto the dark ANIX theme so it reads on the art.
class AnixPanelFrame extends StatelessWidget {
  const AnixPanelFrame({
    super.key,
    required this.child,
    this.size = AnixPanelSize.medium,
    this.state = 'normal',
    this.padding,
  });
  final Widget child;
  final AnixPanelSize size;
  final String state;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final (String name, double w, double h, double inset) = switch (size) {
      AnixPanelSize.small => ('small', 320.0, 240.0, 36.0),
      AnixPanelSize.medium => ('medium', 512.0, 384.0, 44.0),
      AnixPanelSize.fullscreen => ('fullscreen', 768.0, 1024.0, 52.0),
      AnixPanelSize.sheet => ('bottom-sheet', 768.0, 420.0, 52.0),
    };
    // Draw the art at 2x density so the frame rails stay thin on phones.
    const double density = 2.0;
    final Widget framed = AnixNineSlice(
      asset: AnixAssets.modal(name, state),
      center: Rect.fromLTRB(inset, inset, w - inset, h - inset),
      scale: density,
      child: Padding(padding: padding ?? EdgeInsets.all(inset / density + 6), child: child),
    );
    return anixDarkContent(context, framed);
  }
}

/// Keeps text/icons light on the dark panel art, also in the light appearance mode.
Widget anixDarkContent(BuildContext context, Widget child) {
  final ThemeData t = Theme.of(context);
  if (t.brightness == Brightness.dark) return child;
  return Theme(data: buildNxTheme(), child: child);
}

/// AlertDialog-compatible dialog drawn on the pack's medium panel.
class AnixDialog extends StatelessWidget {
  const AnixDialog(
      {super.key, this.title, this.content, this.actions, this.icon, this.backgroundColor, this.shape});
  final Widget? title;

  /// Accepted for AlertDialog call-site compatibility; the pack panel replaces them.
  final Color? backgroundColor;
  final ShapeBorder? shape;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData t = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: AnixPanelFrame(
          size: AnixPanelSize.medium,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            if (icon != null) ...<Widget>[Center(child: icon), const SizedBox(height: 10)],
            if (title != null)
              DefaultTextStyle.merge(
                style: (t.textTheme.titleLarge ?? const TextStyle()).copyWith(
                    fontWeight: FontWeight.w900, color: const Color(0xFFF4EAD2), fontSize: 19),
                child: title!,
              ),
            if (title != null && content != null) const SizedBox(height: 12),
            if (content != null)
              Flexible(
                child: SingleChildScrollView(
                  child: DefaultTextStyle.merge(
                    style: (t.textTheme.bodyMedium ?? const TextStyle()).copyWith(color: const Color(0xFFDCD6F2), height: 1.4),
                    child: content!,
                  ),
                ),
              ),
            if (actions != null && actions!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 6,
                overflowAlignment: OverflowBarAlignment.end,
                children: actions!,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// showModalBottomSheet with the pack's bottom-sheet panel behind the content.
Future<T?> showAnixSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  BoxConstraints? constraints,
  bool isDismissible = true,
  bool enableDrag = true,
  // Accepted for call-site compatibility; the pack panel replaces them.
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: false,
    constraints: constraints,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext ctx) => AnixPanelFrame(
      size: AnixPanelSize.sheet,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (showDragHandle ?? true)
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            decoration: BoxDecoration(color: const Color(0x66FFF0BD), borderRadius: BorderRadius.circular(2)),
          ),
        Flexible(child: builder(ctx)),
      ]),
    ),
  );
}

// ------------------------------------------------------------------------------------------ tooltip / popover

/// Tooltip look for the app theme: the compact tooltip panel with its pointer under the text
/// (tooltips open above their target). Only the rails left of the pointer stretch, so the pointer
/// keeps its shape.
/// (tooltip-theme.webp is tooltip-compact-bottom-normal at half size, so the slice is 1:1.)
Decoration anixTooltipDecoration() => const BoxDecoration(
      image: DecorationImage(
        image: AssetImage('assets/ui/anix/tooltip/tooltip-theme.webp'),
        centerSlice: Rect.fromLTRB(75, 13, 105, 26),
      ),
    );

/// Popover bubble (medium popover, pointer at the bottom). Used for ORACLE / hub speech bubbles.
class AnixPopover extends StatelessWidget {
  const AnixPopover({super.key, required this.child, this.maxWidth = 240});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // 360x220 art: body rows 4..178, pointer rows 178..214 around x=180.
    // Stretch only columns 26..150 (left of the pointer) and rows 30..150.
    const double scale = 2.4;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 336 / scale, maxWidth: maxWidth < 336 / scale ? 336 / scale : maxWidth),
      child: AnixNineSlice(
        asset: 'assets/ui/anix/tooltip/popover-medium-bottom-normal.webp',
        center: const Rect.fromLTRB(26, 30, 150, 150),
        scale: scale,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11 + 42 / scale),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFFF4EAD2)),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------ nav

/// One pack navigation icon with its state art.
class AnixNavIcon extends StatelessWidget {
  const AnixNavIcon({super.key, required this.icon, this.active = false, this.pressed = false, this.size = 28});
  final String icon;
  final bool active;
  final bool pressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String state = pressed ? 'pressed' : (active ? 'active' : 'normal');
    return Image.asset(AnixAssets.nav(icon, state),
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => Icon(Icons.circle_outlined, size: size * 0.8, color: Colors.white54));
  }
}

// ------------------------------------------------------------------------------------------ cards

/// Game card shell (portrait 360x520): art sits under the transparent window, footer is text-safe.
class AnixGameCard extends StatefulWidget {
  const AnixGameCard({
    super.key,
    required this.art,
    required this.footer,
    this.onTap,
    this.overlay,
  });
  final Widget art;
  final Widget footer;
  final Widget? overlay;
  final VoidCallback? onTap;

  // Window and footer geometry from the pack SVG (fractions of 360x520).
  static const Rect window = Rect.fromLTRB(34 / 360, 36 / 520, 326 / 360, 352 / 520);
  static const Rect footerRect = Rect.fromLTRB(36 / 360, 392 / 520, 324 / 360, 486 / 520);

  @override
  State<AnixGameCard> createState() => _AnixGameCardState();
}

class _AnixGameCardState extends State<AnixGameCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final String state = widget.onTap == null ? 'disabled' : (_down ? 'pressed' : 'normal');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _down = false),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
          final double w = c.maxWidth, h = c.maxHeight;
          Rect at(Rect f) => Rect.fromLTRB(f.left * w, f.top * h, f.right * w, f.bottom * h);
          final Rect win = at(AnixGameCard.window);
          final Rect foot = at(AnixGameCard.footerRect);
          return Stack(children: <Widget>[
            Positioned.fromRect(
              rect: win,
              child: ClipRRect(borderRadius: BorderRadius.circular(w * 12 / 360), child: widget.art),
            ),
            Positioned.fill(
              child: Image.asset(AnixAssets.card('portrait', state),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  cacheWidth: (w * 2.4).round(),
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            if (widget.overlay != null) Positioned.fromRect(rect: win, child: widget.overlay!),
            Positioned.fromRect(rect: foot, child: widget.footer),
          ]);
        }),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------ rank + avatars

/// Rank emblem for a tier.
class AnixRankEmblem extends StatelessWidget {
  const AnixRankEmblem({super.key, required this.tier, this.size = 40, this.active = false});
  final AnixTier tier;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
        label: anixTierName(tier, Localizations.localeOf(context).languageCode == 'fa'),
        image: true,
        child: Image.asset(AnixAssets.rank(tier, active ? 'active' : 'normal'),
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: (size * 2.6).round(),
            errorBuilder: (_, __, ___) => SizedBox(width: size, height: size)),
      );
}

/// Avatar portrait inside a rank frame. [photoUrl] (an uploaded profile photo) wins over [avatarId].
class AnixFramedAvatar extends StatelessWidget {
  const AnixFramedAvatar({
    super.key,
    required this.avatarId,
    required this.tier,
    this.size = 64,
    this.photoUrl,
    this.active = false,
  });
  final String avatarId;
  final AnixTier tier;
  final double size;
  final String? photoUrl;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final String id = AnixAssets.avatarIds.contains(avatarId) ? avatarId : AnixAssets.defaultAvatar;
    final double inner = size * 0.73;
    final bool isPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final ImageProvider<Object> img = isPhoto
        ? NetworkImage(photoUrl!) as ImageProvider<Object>
        : ResizeImage(AssetImage(AnixAssets.avatar(id)), width: (inner * 2.4).round());
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        ClipOval(
          child: SizedBox(
            width: inner,
            height: inner,
            // The base-set portraits carry their own thin ring; zoom past it so only the rank frame shows.
            child: Transform.scale(
              scale: isPhoto ? 1 : 1.55,
              child: Image(
                image: img,
                width: inner,
                height: inner,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) =>
                    Image.asset(AnixAssets.avatar(id), width: inner, height: inner, fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        Image.asset(AnixAssets.frame(tier, active ? 'active' : 'normal'),
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: (size * 2.6).round(),
            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      ]),
    );
  }
}

/// Avatar picker sheet: the 24-portrait base set, each in the player's current rank frame.
Future<String?> showAnixAvatarPicker(BuildContext context,
    {required String current, required AnixTier tier, required bool fa}) {
  return showAnixSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      final double h = MediaQuery.sizeOf(ctx).height * 0.72;
      return SizedBox(
        height: h,
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
            child: Text(fa ? 'انتخاب آواتار' : 'Choose your avatar',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFFF4EAD2))),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 8, childAspectRatio: 0.78),
              itemCount: AnixAssets.avatarIds.length,
              itemBuilder: (BuildContext c, int i) {
                final String id = AnixAssets.avatarIds[i];
                final bool on = id == current;
                return GestureDetector(
                  onTap: () => Navigator.of(c).pop(id),
                  child: Column(children: <Widget>[
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext c, BoxConstraints b) =>
                            AnixFramedAvatar(avatarId: id, tier: tier, size: b.biggest.shortestSide, active: on),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(AnixAssets.avatarName(id, fa),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: on ? const Color(0xFFFFD86B) : const Color(0xFFBFB3E6))),
                  ]),
                );
              },
            ),
          ),
        ]),
      );
    },
  );
}
