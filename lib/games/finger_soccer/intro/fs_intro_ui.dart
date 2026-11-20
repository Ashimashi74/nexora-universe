// Shared look of the finger-soccer intro screens (reference: the "گل کوچیک" pre-match flow, 360x787 design canvas).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fs_intro_data.dart';

const String kFsStadium = 'assets/games/bermuda/intro/stadium_dusk.webp';

/// Design canvas of the reference game area (its 480x800 recording shows a 360x787 portrait game view).
const double kFsW = 360, kFsH = 787;

const Color kFsTeal = Color(0xFF15A88C);
const Color kFsTealDark = Color(0xFF0B7D67);
const Color kFsLime = Color(0xFF9BE21B);
const Color kFsLimeDark = Color(0xFF5DA90C);
const Color kFsYellow = Color(0xFFFFD52E);
const Color kFsYellowDark = Color(0xFFE0A100);
const Color kFsCream = Color(0xFFF2DDB4);
const Color kFsCreamEdge = Color(0xFFC9A46B);
const Color kFsBarGreen = Color(0xFF58C81C);
const Color kFsNavy = Color(0xFF1C2038);
const Color kFsNavyTile = Color(0xFF262A47);
const Color kFsNavyEdge = Color(0xFF3A3F63);
const Color kFsOrangeTitle = Color(0xFFFF6A1A);

TextStyle fsText(double size,
        {Color color = Colors.white,
        FontWeight weight = FontWeight.w700,
        String family = 'Estedad',
        double? height,
        List<Shadow>? shadows}) =>
    TextStyle(
        fontFamily: family,
        fontSize: size,
        color: color,
        fontWeight: weight,
        height: height ?? 1.25,
        shadows: shadows,
        decoration: TextDecoration.none);

/// Full-bleed stadium background with the design canvas scaled (contain) on top, like the reference which letterboxes
/// its fixed portrait layout. [dim] darkens the stadium (formation screen, shop).
class FsCanvas extends StatelessWidget {
  const FsCanvas({super.key, required this.children, this.dim = 0, this.topLane = 0, this.bottomGradient = 0});
  final List<Widget> children;
  final double dim;
  final double bottomGradient;

  /// Extra space kept free at the top (logical px) for the host's exit / ORACLE buttons.
  final double topLane;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(fit: StackFit.expand, children: <Widget>[
        const FsStadiumBg(),
        if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
        if (bottomGradient > 0)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: bottomGradient * .55),
                  Colors.black.withValues(alpha: bottomGradient * .15),
                  Colors.black.withValues(alpha: bottomGradient * .55),
                  Colors.black.withValues(alpha: bottomGradient),
                ],
                stops: const <double>[0, .35, .62, 1],
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: pad.top + topLane, bottom: pad.bottom),
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: kFsW, height: kFsH, child: Stack(clipBehavior: Clip.none, children: children)),
          ),
        ),
      ]),
    );
  }
}

class FsStadiumBg extends StatelessWidget {
  const FsStadiumBg({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(kFsStadium,
      fit: BoxFit.cover,
      alignment: const Alignment(0, .2),
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF0B1A3C), Color(0xFF3B4C7A), Color(0xFF1F6B22), Color(0xFF0E3A10)],
                stops: <double>[0, .5, .62, 1],
              ),
            ),
          ));
}

/// Button press feel of the reference: shrinks a little while held and springs back on release.
class FsPress extends StatefulWidget {
  const FsPress({super.key, required this.child, this.onTap, this.enabled = true});
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  State<FsPress> createState() => _FsPressState();
}

class _FsPressState extends State<FsPress> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final bool on = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTap: on ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? .92 : 1,
        duration: Duration(milliseconds: _down ? 70 : 160),
        curve: _down ? Curves.easeOut : Curves.elasticOut,
        child: Opacity(opacity: widget.enabled ? 1 : .55, child: widget.child),
      ),
    );
  }
}

/// Rounded "3D" button: a lighter face over a darker bottom lip, as on the reference's green / yellow / grey buttons.
class FsBevel extends StatelessWidget {
  const FsBevel({
    super.key,
    required this.w,
    required this.h,
    required this.top,
    required this.bottom,
    required this.child,
    this.lip,
    this.radius = 6,
    this.lipH = 3,
    this.border,
  });
  final double w, h, radius, lipH;
  final Color top, bottom;
  final Color? lip;
  final Color? border;
  final Widget child;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: w,
        height: h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: lip ?? Color.lerp(bottom, Colors.black, .35),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(0, 2))],
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: lipH),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: border == null ? null : Border.all(color: border!, width: 1),
                gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: <Color>[top, bottom]),
              ),
              child: Center(child: child),
            ),
          ),
        ),
      );
}

/// Green "select" style button.
Widget fsLimeButton(String label, double w, double h, {double size = 13}) => FsBevel(
      w: w,
      h: h,
      top: const Color(0xFFC8F53A),
      bottom: const Color(0xFF7DCB12),
      lip: const Color(0xFF8A8F86),
      radius: 4,
      child: Text(label, style: fsText(size, color: const Color(0xFF1B4A05), weight: FontWeight.w900)),
    );

/// Grey "selected" style button.
Widget fsGreyButton(String label, double w, double h, {double size = 13}) => FsBevel(
      w: w,
      h: h,
      top: const Color(0xFFF4F4F4),
      bottom: const Color(0xFFD2D2D2),
      lip: const Color(0xFF8E8E8E),
      radius: 4,
      child: Text(label, style: fsText(size, color: const Color(0xFF8A8A8A), weight: FontWeight.w900)),
    );

/// Yellow buy button with the gem price.
Widget fsBuyButton(String label, int price, double w, double h, {double size = 13}) => FsBevel(
      w: w,
      h: h,
      top: const Color(0xFFFFE35A),
      bottom: kFsYellow,
      lip: kFsYellowDark,
      radius: 4,
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text('$label ${fsFa(price)}', style: fsText(size, color: const Color(0xFF4A3100), weight: FontWeight.w900)),
        const SizedBox(width: 4),
        const FsGem(size: 15),
      ]),
    );

/// The app's gem (الماس) currency mark.
class FsGem extends StatelessWidget {
  const FsGem({super.key, this.size = 14});
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _GemPainter());
}

class _GemPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final double w = s.width, h = s.height;
    final Path p = Path()
      ..moveTo(w * .22, h * .12)
      ..lineTo(w * .78, h * .12)
      ..lineTo(w, h * .38)
      ..lineTo(w * .5, h * .95)
      ..lineTo(0, h * .38)
      ..close();
    c.drawPath(
        p,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF9FF4FF), Color(0xFF2C9CF0), Color(0xFF1659C9)])
              .createShader(Offset.zero & s));
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .07
          ..color = const Color(0xFF0E3E8A));
    c.drawLine(Offset(0, h * .38), Offset(w, h * .38), Paint()..color = const Color(0x99FFFFFF)..strokeWidth = w * .05);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Big yellow 3D arrow (team picker). [left] points left. Bounces sideways like the reference.
class FsArrow extends StatefulWidget {
  const FsArrow({super.key, required this.left, required this.onTap, this.w = 52, this.h = 60});
  final bool left;
  final VoidCallback onTap;
  final double w, h;
  @override
  State<FsArrow> createState() => _FsArrowState();
}

class _FsArrowState extends State<FsArrow> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FsPress(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? child) => Transform.translate(
              offset: Offset((widget.left ? -1 : 1) * 3 * Curves.easeInOut.transform(_c.value), 0), child: child),
          child: CustomPaint(size: Size(widget.w, widget.h), painter: _ArrowPainter(widget.left)),
        ),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.left);
  final bool left;
  @override
  void paint(Canvas c, Size s) {
    if (left) {
      c.translate(s.width, 0);
      c.scale(-1, 1);
    }
    final double w = s.width, h = s.height;
    // right-pointing arrow: shaft on the left, head on the right
    Path arrow(double dx, double dy) => Path()
      ..moveTo(dx + w * .04, dy + h * .33)
      ..lineTo(dx + w * .5, dy + h * .33)
      ..lineTo(dx + w * .5, dy + h * .08)
      ..lineTo(dx + w * .96, dy + h * .5)
      ..lineTo(dx + w * .5, dy + h * .92)
      ..lineTo(dx + w * .5, dy + h * .67)
      ..lineTo(dx + w * .04, dy + h * .67)
      ..close();
    final Path side = arrow(0, h * .06);
    c.drawPath(side.shift(const Offset(0, 2)), Paint()..color = const Color(0x55000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawPath(side, Paint()..color = const Color(0xFFC77E00));
    final Path face = arrow(0, 0);
    c.drawPath(
        face,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0xFFFFF27A), Color(0xFFFFD21A), Color(0xFFF4A800)])
              .createShader(Offset.zero & s));
    c.drawPath(
        face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0xFFB86E00));
    // glossy highlight on the shaft
    c.drawRRect(RRect.fromLTRBR(w * .1, h * .37, w * .5, h * .45, const Radius.circular(3)),
        Paint()..color = const Color(0x88FFFFFF));
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.left != left;
}

/// Reference loading bar: black track with a yellow-to-orange fill and an optional centred counter.
class FsLoadBar extends StatelessWidget {
  const FsLoadBar({super.key, required this.value, this.w = 200, this.h = 22, this.counter, this.fill = true});
  final double value;
  final double w, h;
  final String? counter;
  final bool fill;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: w,
        height: h,
        child: Stack(children: <Widget>[
          const Positioned.fill(child: ColoredBox(color: Color(0xFF050505))),
          if (fill)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: w * value.clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xFFFFC21E), Color(0xFFFFB417), Color(0xFFF07A00)],
                    stops: <double>[0, .6, 1],
                  ),
                ),
              ),
            ),
          if (counter != null)
            Center(child: Text(counter!, style: fsText(14, weight: FontWeight.w900, height: 1))),
        ]),
      );
}

/// Collapsed game bar ("نوار بازی") handle at the bottom-left: chevron, player count, muted mic.
/// Size of the game bar handle (bottom-left pill); the in-match formation button sits right beside it.
const double kFsBarHandleWidth = 97, kFsBarHandleHeight = 40;

class FsBarHandle extends StatelessWidget {
  const FsBarHandle({super.key, required this.players, required this.onTap, this.micOff = true});
  final int players;
  final bool micOff;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FsPress(
        onTap: onTap,
        child: Container(
          width: kFsBarHandleWidth,
          height: kFsBarHandleHeight,
          decoration: const BoxDecoration(
            color: Color(0xFF1B1F3B),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
            boxShadow: <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 6)],
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: <Widget>[
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 4),
              Text(fsFa(players), style: fsText(12, weight: FontWeight.w900)),
              const SizedBox(width: 2),
              const Icon(Icons.people_outline_rounded, color: Colors.white, size: 13),
              const Spacer(),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(color: Color(0xFF2E3460), shape: BoxShape.circle),
                child: Icon(micOff ? Icons.mic_off_outlined : Icons.mic_none_rounded, color: const Color(0xFFB7BCD9), size: 16),
              ),
              const SizedBox(width: 8),
            ]),
          ),
        ),
      );
}

/// Grey quick-chat button of the reference (bottom-right).
class FsChatButton extends StatelessWidget {
  const FsChatButton({super.key, required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => FsPress(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 35,
          decoration: BoxDecoration(color: const Color(0xFF8E8E8E).withValues(alpha: .92), borderRadius: BorderRadius.circular(7)),
          child: Center(
            child: Container(
              width: 23,
              height: 23,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: const Icon(Icons.campaign_rounded, size: 15, color: Color(0xFF8E8E8E)),
              ),
            ),
          ),
        ),
      );
}

/// Text with a dark outline (the reference's orange title and white captions).
class FsOutlined extends StatelessWidget {
  const FsOutlined(this.text, {super.key, required this.style, this.stroke = 3, this.strokeColor = const Color(0xFF3A1300)});
  final String text;
  final TextStyle style;
  final double stroke;
  final Color strokeColor;
  @override
  Widget build(BuildContext context) => Stack(children: <Widget>[
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: style.fontFamily,
                fontSize: style.fontSize,
                fontWeight: style.fontWeight,
                height: style.height,
                decoration: TextDecoration.none,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = stroke
                  ..strokeJoin = StrokeJoin.round
                  ..color = strokeColor)),
        Text(text, textAlign: TextAlign.center, style: style),
      ]);
}

/// A team disc as the reference shows it on the team picker: the crest art on a thick silver cylinder.
class FsDisc3D extends StatelessWidget {
  const FsDisc3D({super.key, required this.asset, required this.r, this.depth = 9});
  final String asset;
  final double r, depth;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: r * 2 + 6,
        height: r * 2 + depth + 8,
        child: Stack(alignment: Alignment.topCenter, children: <Widget>[
          Positioned(
            top: depth + 2,
            child: Container(
              width: r * 2,
              height: r * 2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[BoxShadow(color: Color(0x88000000), blurRadius: 8, offset: Offset(0, 4))],
                gradient: LinearGradient(colors: <Color>[Color(0xFF6E737A), Color(0xFFD9DDE2), Color(0xFF8B9097), Color(0xFF55595F)], stops: <double>[0, .35, .7, 1]),
              ),
            ),
          ),
          for (int i = depth.toInt(); i > 0; i -= 2)
            Positioned(
              top: i.toDouble(),
              child: Container(
                width: r * 2,
                height: r * 2,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: <Color>[Color(0xFF7D828A), Color(0xFFE4E7EB), Color(0xFF9A9FA6), Color(0xFF61656B)], stops: <double>[0, .35, .7, 1]),
                ),
              ),
            ),
          Positioned(
            top: 0,
            child: Container(
              width: r * 2,
              height: r * 2,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFDADDE1)),
              child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox())),
            ),
          ),
        ]),
      );
}
