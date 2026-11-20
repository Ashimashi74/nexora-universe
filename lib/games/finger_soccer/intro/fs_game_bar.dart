// Game bar "نوار بازی" (reference recording 2, 44-56 s): a navy panel with six action tiles (chat, quick message,
// connection status, exit, report a problem, mute all), the sound section (game volume + full-screen toggle), the
// voice-chat section (chat volume + duck toggle) and the voice-chat participants; plus the exit confirmation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fs_intro_data.dart';
import 'fs_intro_ui.dart';

/// An extra on/off row of the sound section.
class FsBarToggle {
  FsBarToggle(this.label, this.value, this.onChanged);
  final String label;
  bool value;
  final ValueChanged<bool> onChanged;
}

/// Settings the bar edits (kept by the caller between openings).
class FsBarSettings {
  FsBarSettings({this.gameVolume = 1, this.voiceVolume = 1, this.fullScreen = false, this.duck = true, this.mutedAll = false});
  double gameVolume, voiceVolume;
  bool fullScreen, duck, mutedAll;
}

class FsGameBar extends StatefulWidget {
  const FsGameBar({
    super.key,
    required this.settings,
    required this.players,
    required this.onClose,
    required this.onExit,
    this.online = false,
    this.connected = true,
    this.onChanged,
    this.onChat,
    this.onQuick,
    this.onReport,
    this.me = 0,
    this.onRestart,
    this.extra = const <FsBarToggle>[],
  });
  final FsBarSettings settings;

  /// Offline pass-and-play: the status tile becomes "شروع دوباره" (restart).
  final VoidCallback? onRestart;

  /// Extra toggles under the full-screen one (e.g. the goal announcer in a match).
  final List<FsBarToggle> extra;

  /// Names in the voice-chat list ([me] gets "(تو)").
  final List<String> players;
  final int me;
  final bool online, connected;
  final VoidCallback onClose;
  final VoidCallback onExit;

  /// Called after every settings change (mute all, volumes, full screen, duck).
  final ValueChanged<FsBarSettings>? onChanged;

  /// Null = not available yet (tile drawn disabled).
  final VoidCallback? onChat, onQuick, onReport;

  /// Slides the bar in from the left over the current screen; resolves when it closes.
  static Future<void> show(BuildContext context,
      {required FsBarSettings settings,
      required List<String> players,
      required VoidCallback onExit,
      bool online = false,
      bool connected = true,
      int me = 0,
      VoidCallback? onRestart,
      List<FsBarToggle> extra = const <FsBarToggle>[],
      ValueChanged<FsBarSettings>? onChanged}) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'game bar',
      barrierColor: const Color(0x55000000),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext c, _, __) => FsGameBar(
        settings: settings,
        players: players,
        me: me,
        online: online,
        connected: connected,
        onChanged: onChanged,
        extra: extra,
        onRestart: onRestart == null
            ? null
            : () {
                Navigator.of(c).pop();
                onRestart();
              },
        onClose: () => Navigator.of(c).pop(),
        onExit: () async {
          final bool ok = await showFsExitConfirm(c, online: online);
          if (!ok || !c.mounted) return;
          Navigator.of(c).pop();
          onExit();
        },
      ),
      transitionBuilder: (BuildContext c, Animation<double> a, _, Widget child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );
  }

  @override
  State<FsGameBar> createState() => _FsGameBarState();
}

const Color _kGrey = Color(0xFFA0A4C8);

class _FsGameBarState extends State<FsGameBar> {
  FsBarSettings get s => widget.settings;

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged?.call(s);
  }

  Widget _tile(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white}) => FsPress(
        onTap: onTap,
        enabled: onTap != null,
        child: Container(
          width: 94,
          height: 102,
          decoration: BoxDecoration(
            color: kFsNavyTile,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kFsNavyEdge.withValues(alpha: .7)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: fsText(14, color: color, weight: FontWeight.w900, height: 1.35)),
          ]),
        ),
      );

  Widget _slider(String label, IconData icon, double v, ValueChanged<double>? onChanged, VoidCallback? onSpeaker) =>
      Opacity(
        opacity: onChanged == null ? .55 : 1,
        child: Column(children: <Widget>[
          Row(children: <Widget>[
            Text(label, style: fsText(15, weight: FontWeight.w900)),
            const SizedBox(width: 6),
            Icon(icon, color: Colors.white, size: 16),
            const Spacer(),
            Text('${fsFa((v * 100).round())}٪', style: fsText(11, weight: FontWeight.w700)),
          ]),
          SizedBox(
            height: 30,
            child: Row(children: <Widget>[
              FsPress(
                onTap: onSpeaker,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(color: Color(0xFF9CA0B5), shape: BoxShape.circle),
                  child: Icon(v == 0 ? Icons.volume_off_outlined : Icons.volume_up_outlined, size: 15, color: const Color(0xFF2A2E4A)),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: const SliderThemeData(
                    trackHeight: 5,
                    activeTrackColor: Color(0xFFF7C33C),
                    inactiveTrackColor: Color(0xFF4A4F75),
                    thumbColor: Color(0xFFF7C33C),
                    overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(value: v, onChanged: onChanged),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _toggle(String label, bool v, ValueChanged<bool>? onChanged) => Opacity(
        opacity: onChanged == null ? .55 : 1,
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: kFsNavyTile, borderRadius: BorderRadius.circular(12)),
          child: Row(children: <Widget>[
            Expanded(child: Text(label, style: fsText(14.5, weight: FontWeight.w900, height: 1.45))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onChanged == null ? null : () => onChanged(!v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 55,
                height: 32,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: v ? const Color(0xFF3DD6A0) : const Color(0xFF171A33),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: v ? const Color(0xFF3DD6A0) : const Color(0xFF5A5F86)),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  alignment: v ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                  child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _round(IconData i, VoidCallback onTap) => FsPress(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: const Color(0xFF2E3354), border: Border.all(color: const Color(0xFF7A80A8))),
          child: Icon(i, color: Colors.white, size: 18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final String status = !widget.online ? 'آفلاین' : (widget.connected ? 'وصل' : 'در حال\nوصل شدن');
    return FsBarFrame(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        SizedBox(
          height: 40,
          child: Row(children: <Widget>[
            Text('نوار بازی', style: fsText(18, weight: FontWeight.w900)),
            const SizedBox(width: 10),
            const Icon(Icons.people_outline_rounded, color: _kGrey, size: 15),
            const SizedBox(width: 2),
            Text(fsFa(widget.players.length), style: fsText(12, color: _kGrey)),
            const Spacer(),
            _round(Icons.keyboard_arrow_down_rounded, widget.onClose),
            const SizedBox(width: 7),
            _round(Icons.remove_rounded, widget.onClose),
          ]),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
          if (widget.onRestart != null && !widget.online)
            _tile(Icons.refresh_rounded, 'شروع\nدوباره', widget.onRestart)
          else
            _tile(Icons.wifi_tethering_rounded, status, null),
          _tile(Icons.sentiment_satisfied_alt_rounded, 'پیام سریع', widget.onQuick),
          _tile(Icons.chat_bubble_outline_rounded, 'گفتگو', widget.onChat),
        ]),
        const SizedBox(height: 11),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
          _tile(s.mutedAll ? Icons.volume_off_outlined : Icons.volume_up_outlined, s.mutedAll ? 'صدا\nروشن' : 'بی‌صدا\nهمه',
              () => _set(() => s.mutedAll = !s.mutedAll)),
          _tile(Icons.bug_report_outlined, 'گزارش\nمشکل', widget.onReport),
          _tile(Icons.logout_rounded, 'خروج', widget.onExit, color: const Color(0xFFFF6B6B)),
        ]),
        const SizedBox(height: 12),
        const Divider(color: Color(0xFF33385A), height: 1),
        const SizedBox(height: 10),
        Text('صدا', style: fsText(13, color: _kGrey)),
        const SizedBox(height: 6),
        _slider('صدای بازی', Icons.sports_esports_outlined, s.gameVolume, (double v) => _set(() => s.gameVolume = v),
            () => _set(() => s.gameVolume = s.gameVolume == 0 ? 1 : 0)),
        const SizedBox(height: 4),
        _toggle('تمام‌صفحه (نوار بالا و دکمه‌های گوشی پنهان)', s.fullScreen, (bool v) {
          _set(() => s.fullScreen = v);
          SystemChrome.setEnabledSystemUIMode(v ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
        }),
        for (final FsBarToggle t in widget.extra) ...<Widget>[
          const SizedBox(height: 8),
          _toggle(t.label, t.value, (bool v) {
            setState(() => t.value = v);
            t.onChanged(v);
          }),
        ],
        const SizedBox(height: 10),
        // Voice chat has no backend in this game yet: drawn as in the reference, disabled.
        _slider('صدای گفتگو', Icons.headphones_outlined, s.voiceVolume, null, null),
        const SizedBox(height: 4),
        _toggle('موقع حرف زدن، صدای بازی کم شود', s.duck, null),
        const SizedBox(height: 10),
        const Divider(color: Color(0xFF33385A), height: 1),
        const SizedBox(height: 10),
        Text('گفتگوی صوتی بازی', style: fsText(13, color: _kGrey)),
        const SizedBox(height: 6),
        for (int i = 0; i < widget.players.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3A3F63)),
                child: const Icon(Icons.person, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(i == widget.me ? '${widget.players[i]} (تو)' : widget.players[i], style: fsText(14, weight: FontWeight.w900)),
            ]),
          ),
      ]),
    );
  }
}

/// The navy panel on the 360x787 canvas (x 14..346, y 50..772 in the reference).
class FsBarFrame extends StatelessWidget {
  const FsBarFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: kFsW,
            height: kFsH,
            child: Stack(children: <Widget>[
              Positioned(
                left: 14,
                top: 50,
                width: 332,
                height: 722,
                child: Material(
                  color: kFsNavy,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF2E3350), width: 1.2)),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 14), child: child),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "از بازی خارج می‌شوی؟" with stay / exit. True = exit.
Future<bool> showFsExitConfirm(BuildContext context, {bool online = false}) async {
  final bool? r = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (BuildContext c) => Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: kFsNavy,
        insetPadding: const EdgeInsets.symmetric(horizontal: 26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF2E3350))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text('از بازی خارج می‌شوی؟', textAlign: TextAlign.center, style: fsText(20, weight: FontWeight.w900)),
            const SizedBox(height: 12),
            Text(
                online
                    ? 'اگه از بازی آنلاین خارج بشی، باخت حساب میشه.\n\nاز گفتگوی بازی هم خارج می‌شوی.'
                    : 'این بازی تموم میشه و نتیجه‌اش ذخیره نمیشه.',
                textAlign: TextAlign.center,
                style: fsText(14.5, color: const Color(0xFFC9CCE6), weight: FontWeight.w500, height: 1.7)),
            const SizedBox(height: 18),
            Row(children: <Widget>[
              Expanded(
                child: FsPress(
                  onTap: () => Navigator.pop(c, false),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                        color: kFsNavyTile, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF7A80A8))),
                    child: Center(child: Text('ماندن', style: fsText(15, weight: FontWeight.w900))),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FsPress(
                  onTap: () => Navigator.pop(c, true),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFF4A2030), borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text('خروج', style: fsText(15, color: const Color(0xFFFF6B6B), weight: FontWeight.w900))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
  return r == true;
}
