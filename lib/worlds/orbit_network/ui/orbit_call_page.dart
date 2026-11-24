import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../core/backend/backend_gateway.dart';
import '../../../core/backend/supabase_backend.dart';
import '../../../core/online/online_config.dart';
import '../../../core/online/voice_connect.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../data/supabase_orbit_repository.dart';
import '../state/orbit_controller.dart';

/// Real voice / video call for an Orbit Network chat through LiveKit.
///
/// The token comes from the `nx-call-token` Edge Function, which only answers authenticated members of the chat.
/// [startNew] = this phone starts the call (rings the other members through nx_calls + a call message);
/// otherwise it joins the call already running in that chat.
class OrbitCallPage extends ConsumerStatefulWidget {
  const OrbitCallPage({
    super.key,
    required this.chatId,
    required this.title,
    this.video = false,
    this.startNew = true,
    this.callId,
  });

  final String chatId;
  final String title;
  final bool video;
  final bool startNew;
  final String? callId;

  @override
  ConsumerState<OrbitCallPage> createState() => _OrbitCallPageState();
}

class _OrbitCallPageState extends ConsumerState<OrbitCallPage> {
  Room? _room;
  EventsListener<RoomEvent>? _events;
  String? _callId;
  String? _error;
  bool _connecting = true;
  bool _mic = true;
  late bool _cam = widget.video;
  bool _speaker = true;
  bool _canPublish = true;
  DateTime? _since;
  Timer? _tick;
  bool _hadPeer = false;

  @override
  void initState() {
    super.initState();
    _callId = widget.callId;
    unawaited(_start());
  }

  /// Connect path, all independent steps in parallel:
  ///   ring (nx_start_call) ‖ grant (cached / Edge Function) ‖ mic open ‖ DNS+TLS+region warm-up
  /// then one LiveKit join that publishes the mic (and camera) as part of the handshake.
  Future<void> _start() async {
    final BackendGateway be = ref.read(backendProvider);
    final SupabaseOrbitRepository? repo =
        ref.read(orbitControllerProvider).online;
    if (be is! SupabaseBackend || repo == null) {
      setState(() {
        _connecting = false;
        _error = 'offline';
      });
      return;
    }
    final Room room = Room(roomOptions: voiceRoomOptions());
    _room = room;
    room.addListener(_onRoom);
    warmVoice(room, OnlineConfig.liveKitUrl);
    final Future<LocalAudioTrack?> micF = openMic();
    LocalAudioTrack? mic;
    try {
      final Future<String?> ring = widget.startNew
          ? repo.startCall(widget.chatId, video: widget.video)
          : Future<String?>.value(_callId);
      final Future<Map<String, dynamic>?> grantF =
          be.liveKitGrant(widget.chatId, video: widget.video);
      final List<Object?> both = await Future.wait<Object?>(<Future<Object?>>[ring, grantF]);
      _callId = both[0] as String?;
      final Map<String, dynamic>? grant = both[1] as Map<String, dynamic>?;
      final String? token = grant?['token'] as String?;
      if (token == null) throw StateError('${grant?['error'] ?? 'no_token'}');
      _canPublish = grant?['canPublish'] != false;
      final String url = '${grant?['url'] ?? OnlineConfig.liveKitUrl}';
      mic = await micF;
      if (!_canPublish) {
        await dropMic(mic);
        mic = null;
        _mic = false;
        _cam = false;
      } else if (mic == null) {
        _mic = false; // mic unavailable (permission denied): still join and listen
      }
      final EventsListener<RoomEvent> ev = room.createListener();
      _events = ev;
      ev.on<RoomDisconnectedEvent>((RoomDisconnectedEvent e) {
        // The SDK already tried to resume / fully reconnect before this fires: show the call as dropped instead
        // of reconnecting in a loop.
        if (!mounted || !identical(_room, room)) return;
        if (e.reason != DisconnectReason.clientInitiated) {
          setState(() => _error = 'disconnected');
        }
      });
      await connectVoice(room, url, token,
          micTrack: mic, camera: _canPublish && widget.video);
      mic = null; // the room owns it now
      unawaited(Hardware.instance.setSpeakerphoneOn(true).then((_) {}, onError: (Object _) {}));
      _since = DateTime.now();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      be.invalidateLiveKitGrant('call${widget.video ? 'v' : ''}', widget.chatId);
      if (mic != null) {
        unawaited(dropMic(mic));
      } else {
        unawaited(micF.then(dropMic));
      }
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = '$e';
        });
      }
    }
  }

  void _onRoom() {
    final Room? r = _room;
    if (r == null || !mounted) return;
    if (r.remoteParticipants.isNotEmpty) _hadPeer = true;
    setState(() {});
  }

  Future<void> _hangUp() async {
    final Room? r = _room;
    final bool alone = r == null || r.remoteParticipants.isEmpty;
    final EventsListener<RoomEvent>? ev = _events;
    _room = null;
    _events = null;
    r?.removeListener(_onRoom);
    await disposeVoice(r, ev);
    final String? id = _callId;
    final SupabaseOrbitRepository? repo =
        ref.read(orbitControllerProvider).online;
    if (id != null && alone && repo != null) await repo.endCall(id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    final Room? r = _room;
    final EventsListener<RoomEvent>? ev = _events;
    _room = null;
    _events = null;
    if (r != null) {
      r.removeListener(_onRoom);
      unawaited(disposeVoice(r, ev));
    }
    super.dispose();
  }

  String _duration() {
    final DateTime? s = _since;
    if (s == null) return '';
    final Duration d = DateTime.now().difference(s);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Widget _tile(Participant p, {required bool local}) {
    final NxThemeColors visual = NxThemeColors.of(context);
    VideoTrack? video;
    for (final TrackPublication<Track> pub in p.videoTrackPublications) {
      final Track? t = pub.track;
      if (t is VideoTrack && !pub.muted) video = t;
    }
    final bool speaking = p.isSpeaking;
    final String name =
        local ? context.tx('تو', 'You') : (p.name.isEmpty ? 'Pilot' : p.name);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: visual.surfaceRaised,
        borderRadius: BorderRadius.circular(NxRadius.lg),
        border: Border.all(
          color:
              speaking ? visual.accent : visual.border.withValues(alpha: 0.65),
          width: speaking ? 3 : 1,
        ),
        boxShadow: speaking
            ? <BoxShadow>[
                BoxShadow(
                    color: visual.accent.withValues(alpha: 0.4), blurRadius: 18)
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: <Widget>[
        if (video != null)
          VideoTrackRenderer(video)
        else
          Center(
            child: CircleAvatar(
              radius: 38,
              backgroundColor: visual.accent.withValues(alpha: 0.28),
              child: Text(name.characters.first.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
            ),
          ),
        PositionedDirectional(
          start: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (p.isMuted)
                const Icon(Icons.mic_off_rounded,
                    size: 14, color: NxColors.danger),
              const SizedBox(width: 4),
              Text(name,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _btn(IconData icon, String tip, VoidCallback? onTap,
          {Color? color, bool active = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Tooltip(
          message: tip,
          child: RawMaterialButton(
            onPressed: onTap,
            shape: const CircleBorder(),
            fillColor: color ??
                (active ? Colors.white.withValues(alpha: 0.16) : Colors.white),
            constraints: const BoxConstraints.tightFor(width: 58, height: 58),
            child: Icon(icon,
                color: color != null
                    ? Colors.white
                    : (active ? Colors.white : NxColors.luxeBg)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Room? room = _room;
    final List<Widget> tiles = <Widget>[];
    if (room != null && !_connecting && _error == null) {
      final LocalParticipant? lp = room.localParticipant;
      if (lp != null) tiles.add(_tile(lp, local: true));
      for (final RemoteParticipant rp in room.remoteParticipants.values) {
        tiles.add(_tile(rp, local: false));
      }
    }
    final int remotes = room?.remoteParticipants.length ?? 0;
    String status;
    if (_error != null) {
      status = _error == 'offline'
          ? context.tx(
              'برای تماس باید آنلاین باشی.', 'You need to be online to call.')
          : _error == 'disconnected'
              ? context.tx('تماس قطع شد.', 'Call dropped.')
              : context.tx('اتصال تماس برقرار نشد.', 'Could not connect the call.');
    } else if (_connecting) {
      status = context.tx('در حال اتصال…', 'Connecting…');
    } else if (remotes == 0) {
      status = _hadPeer
          ? context.tx('بقیه رفتند', 'Everyone else left')
          : context.tx('در حال زنگ زدن…', 'Ringing…');
    } else {
      status = _duration();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool did, Object? _) {
        if (!did) unawaited(_hangUp());
      },
      child: Scaffold(
        backgroundColor: visual.background,
        body: NxBrandBackground(
          child: SafeArea(
            child: Column(children: <Widget>[
              const SizedBox(height: 12),
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                '${widget.video ? context.tx('تماس تصویری', 'Video call') : context.tx('تماس صوتی', 'Voice call')} · $status',
                style: const TextStyle(color: NxColors.textDim),
              ),
              if (_error != null && _error != 'offline' && _error != 'disconnected')
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: NxColors.danger, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: tiles.isEmpty
                    ? Center(
                        child: _connecting
                            ? CircularProgressIndicator(color: visual.accent)
                            : Icon(
                                widget.video
                                    ? Icons.videocam_off_rounded
                                    : Icons.call_end_rounded,
                                size: 64,
                                color: NxColors.textDim),
                      )
                    : GridView.count(
                        padding: const EdgeInsets.all(12),
                        crossAxisCount: tiles.length <= 2 ? 1 : 2,
                        childAspectRatio: tiles.length <= 2 ? 1.5 : 0.9,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: tiles,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (_canPublish && _error == null)
                        _btn(_mic ? Icons.mic_rounded : Icons.mic_off_rounded,
                            context.tx('میکروفون', 'Microphone'), () async {
                          _mic = !_mic;
                          await room?.localParticipant
                              ?.setMicrophoneEnabled(_mic);
                          if (mounted) setState(() {});
                        }, active: _mic),
                      if (_canPublish && _error == null)
                        _btn(
                            _cam
                                ? Icons.videocam_rounded
                                : Icons.videocam_off_rounded,
                            context.tx('دوربین', 'Camera'), () async {
                          _cam = !_cam;
                          await room?.localParticipant?.setCameraEnabled(_cam);
                          if (mounted) setState(() {});
                        }, active: _cam),
                      if (_error == null)
                        _btn(
                            _speaker
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            context.tx('بلندگو', 'Speaker'), () async {
                          _speaker = !_speaker;
                          try {
                            await Hardware.instance.setSpeakerphoneOn(_speaker);
                          } catch (_) {}
                          if (mounted) setState(() {});
                        }, active: _speaker),
                      _btn(Icons.call_end_rounded, context.tx('قطع', 'Hang up'),
                          _hangUp,
                          color: NxColors.danger),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
