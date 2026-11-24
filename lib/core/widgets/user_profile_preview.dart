import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../worlds/orbit_network/ui/orbit_chat_page.dart';
import '../online/online_service.dart';
import '../online/social_api.dart';
import '../settings/app_settings.dart';
import '../ui2/luxe.dart';

/// Shows a modal bottom sheet previewing another user's profile with real
/// Follow/Unfollow, follower/post/win stats, and instant Direct Message actions
/// backed by the Social Supabase project.
Future<void> showUserProfilePreview(
  BuildContext context, {
  required String userId,
  required String username,
  String? avatarUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => _UserProfilePreviewSheet(
      userId: userId,
      username: username,
      avatarUrl: avatarUrl,
    ),
  );
}

class _UserProfilePreviewSheet extends StatefulWidget {
  const _UserProfilePreviewSheet({
    required this.userId,
    required this.username,
    this.avatarUrl,
  });

  final String userId;
  final String username;
  final String? avatarUrl;

  @override
  State<_UserProfilePreviewSheet> createState() => _UserProfilePreviewSheetState();
}

class _UserProfilePreviewSheetState extends State<_UserProfilePreviewSheet> {
  bool _loading = true;
  bool _busyFollow = false;
  bool _sending = false;
  bool _openingChat = false;

  late String _username = widget.username;
  String _displayName = '';
  String _explorerId = '';
  String? _avatarUrl;
  String _bio = '';
  int _level = 1;
  int _xp = 0;
  int _wins = 0;
  int _followers = 0;
  int _followingCount = 0;
  int _posts = 0;
  bool _isPrivate = false;
  bool _following = false;
  bool _followsMe = false;
  bool _pending = false;

  final TextEditingController _msgCtrl = TextEditingController();

  SupabaseClient? get _client => OnlineService.current?.social;
  String? get _me => OnlineService.current?.uid;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.avatarUrl;
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  void _applyProfile(Map<String, dynamic> p) {
    final String? u = p['username'] as String?;
    if (u != null && u.isNotEmpty) _username = u;
    _displayName = (p['display_name'] as String?)?.trim() ?? '';
    _explorerId = (p['explorer_id'] as String?)?.trim() ?? '';
    final String? av = p['avatar_url'] as String?;
    if (av != null && av.isNotEmpty) _avatarUrl = av;
    _bio = (p['bio'] as String?)?.trim() ?? '';
    _level = (p['level'] as num?)?.toInt() ?? 1;
    _xp = (p['xp'] as num?)?.toInt() ?? 0;
    _wins = (p['wins'] as num?)?.toInt() ?? 0;
    _followers = (p['followers'] as num?)?.toInt() ?? 0;
    _followingCount = (p['following'] as num?)?.toInt() ?? 0;
    _posts = (p['posts'] as num?)?.toInt() ?? 0;
    _isPrivate = p['is_private'] == true;
    _following = p['is_following'] == true;
    _followsMe = p['follows_me'] == true;
    _pending = p['is_pending'] == true;
  }

  Future<void> _load() async {
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (c == null || me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final SocialApi api = SocialApi(c, userId: me);
      final Map<String, dynamic>? prof = await api.socialProfile(widget.userId);
      if (prof != null) {
        if (mounted) {
          setState(() {
            _applyProfile(prof);
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      // Fallback to direct select if RPC fails.
    }
    try {
      final Map<String, dynamic>? prof = await c
          .from('profiles')
          .select('username, display_name, avatar_url, level, xp, wins, bio, is_private')
          .eq('id', widget.userId)
          .maybeSingle();
      final int followers = await c.from('follows').count(CountOption.exact).eq('followee', widget.userId);
      final int following = await c.from('follows').count(CountOption.exact).eq('follower', widget.userId);
      bool isFollowing = false;
      if (me != widget.userId) {
        final Map<String, dynamic>? f = await c
            .from('follows')
            .select('followee')
            .eq('follower', me)
            .eq('followee', widget.userId)
            .maybeSingle();
        isFollowing = f != null;
      }
      if (mounted) {
        setState(() {
          if (prof != null) _applyProfile(prof);
          _followers = followers;
          _followingCount = following;
          _following = isFollowing;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (c == null || me == null || me == widget.userId || _busyFollow) return;
    final bool wantFollow = !(_following || _pending);
    setState(() => _busyFollow = true);
    try {
      final Map<String, dynamic>? updated = await SocialApi(c, userId: me).toggleFollow(widget.userId, wantFollow);
      if (!mounted) return;
      setState(() {
        if (updated != null) {
          _applyProfile(updated);
        } else {
          _following = wantFollow && !_isPrivate;
          _pending = wantFollow && _isPrivate;
          _followers = (_followers + (wantFollow ? 1 : -1)).clamp(0, 1 << 30);
        }
      });
    } catch (_) {
      if (mounted) {
        luxeToast(context, context.tx('عملیات دنبال‌کردن انجام نشد', 'Could not update follow status'));
      }
    } finally {
      if (mounted) setState(() => _busyFollow = false);
    }
  }

  Future<void> _sendMessage() async {
    final String text = _msgCtrl.text.trim();
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (text.isEmpty || c == null || me == null || _sending) return;
    setState(() => _sending = true);
    try {
      final dynamic chatId = await c.rpc('nx_open_direct', params: <String, dynamic>{'p_user': widget.userId});
      await c.rpc('nx_send_message', params: <String, dynamic>{
        'p_chat': '$chatId',
        'p_kind': 'text',
        'p_text': text.length > 4000 ? text.substring(0, 4000) : text,
        'p_payload': <String, dynamic>{},
        'p_reply_to': null,
      });
      _msgCtrl.clear();
      if (mounted) {
        luxeToast(context, context.tx('پیام ارسال شد ✓', 'Message sent ✓'));
      }
    } catch (_) {
      if (mounted) {
        luxeToast(context, context.tx('ارسال پیام ناموفق بود', 'Could not send message'));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFullChat() async {
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (c == null || me == null || _openingChat) return;
    setState(() => _openingChat = true);
    try {
      final dynamic chatId = await c.rpc('nx_open_direct', params: <String, dynamic>{'p_user': widget.userId});
      if (!mounted) return;
      final NavigatorState nav = Navigator.of(context);
      nav.pop();
      await nav.push<void>(MaterialPageRoute<void>(
        builder: (BuildContext ctx) => OrbitChatPage(chatId: '$chatId'),
      ));
    } catch (_) {
      if (mounted) {
        setState(() => _openingChat = false);
        luxeToast(context, context.tx('باز کردن گفت‌وگو ممکن نشد', 'Could not open chat'));
      }
    }
  }

  Widget _statBox(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: Luxe.isLight(context) ? Luxe.dayGlass : Luxe.glass,
          border: Border.all(color: Luxe.lineOf(context)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _loading ? '…' : value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Luxe.inkOf(context)),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Luxe.muteOf(context)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool light = Luxe.isLight(context);
    final Color ink = Luxe.inkOf(context);
    final Color mute = Luxe.muteOf(context);
    final Color gold = Luxe.goldOf(context);
    final bool isSelf = _me == widget.userId;
    final bool onlineSignedIn = _client != null && _me != null;

    final String followLabel = _pending
        ? context.tx('در انتظار تایید', 'Requested')
        : _following
            ? context.tx('دنبال می‌کنی', 'Following')
            : context.tx('دنبال کردن', 'Follow');

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: light
              ? const <Color>[Color(0xFFFFFDF8), Color(0xFFF3EBDC)]
              : const <Color>[Color(0xFF171510), Color(0xFF0A0A0D)],
        ),
        border: Border(top: BorderSide(color: Luxe.lineOf(context))),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: light ? const Color(0x458A6A2C) : const Color(0x40F6E7BD),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Luxe.goldGrad),
                child: CircleAvatar(
                  radius: 30,
                  backgroundColor: light ? const Color(0xFFF4ECDC) : const Color(0xFF161512),
                  backgroundImage: (_avatarUrl != null && _avatarUrl!.isNotEmpty) ? NetworkImage(_avatarUrl!) : null,
                  child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                      ? Text(
                          _username.isNotEmpty ? _username.characters.first.toUpperCase() : '?',
                          style: TextStyle(color: gold, fontSize: 23, fontWeight: FontWeight.w900),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            _displayName.isNotEmpty ? _displayName : _username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (_isPrivate) ...<Widget>[
                          const SizedBox(width: 6),
                          Icon(Icons.lock_outline_rounded, size: 15, color: mute),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text('@$_username', style: TextStyle(color: gold, fontSize: 12.5, fontWeight: FontWeight.w700)),
                        Text('· Lv $_level · $_xp XP', style: TextStyle(color: mute, fontSize: 12)),
                        if (_followsMe)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: gold.withValues(alpha: 0.16),
                            ),
                            child: Text(
                              context.tx('دنبال‌کننده‌ی تو', 'Follows you'),
                              style: TextStyle(color: gold, fontSize: 10.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                      ],
                    ),
                    if (_explorerId.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(_explorerId, style: TextStyle(color: mute, fontSize: 11, letterSpacing: 1.0)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (_bio.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(_bio, style: TextStyle(color: ink.withValues(alpha: 0.88), fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _statBox(context, '$_followers', context.tx('دنبال‌کننده', 'Followers')),
              const SizedBox(width: 8),
              _statBox(context, '$_followingCount', context.tx('دنبال‌شونده', 'Following')),
              const SizedBox(width: 8),
              _statBox(context, '$_posts', context.tx('پست‌ها', 'Posts')),
              const SizedBox(width: 8),
              _statBox(context, '$_wins', context.tx('بردها', 'Wins')),
            ],
          ),
          if (!isSelf && onlineSignedIn) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: (_following || _pending)
                      ? OutlinedButton.icon(
                          onPressed: _busyFollow ? null : _toggleFollow,
                          icon: Icon(_pending ? Icons.schedule_rounded : Icons.check_rounded, size: 18),
                          label: Text(followLabel),
                        )
                      : FilledButton.icon(
                          onPressed: _busyFollow ? null : _toggleFollow,
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                          label: Text(followLabel),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openingChat ? null : _openFullChat,
                    icon: const Icon(Icons.forum_outlined, size: 18),
                    label: Text(context.tx('باز کردن چت', 'Open chat')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    style: TextStyle(color: ink),
                    decoration: InputDecoration(
                      hintText: context.tx('ارسال پیام مستقیم به $_username…', 'Send a direct message to $_username…'),
                      hintStyle: TextStyle(color: mute),
                      filled: true,
                      fillColor: light ? const Color(0xFFF3ECDD) : const Color(0xFF171612),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Luxe.lineOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Luxe.lineOf(context)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _sendMessage,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
