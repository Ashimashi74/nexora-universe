import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../online/online_service.dart';

/// Shows a modal bottom sheet previewing another user's profile with
/// Follow/Unfollow and Direct Message actions backed by Supabase.
Future<void> showUserProfilePreview(
  BuildContext context, {
  required String userId,
  required String username,
  String? avatarUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF141824),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
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
  bool _following = false;
  int _xp = 0;
  String _bio = '';
  final TextEditingController _msgCtrl = TextEditingController();
  bool _sending = false;

  SupabaseClient? get _client => OnlineService.current?.client;
  String? get _me => OnlineService.current?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (c == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final Map<String, dynamic>? prof = await c
          .from('profiles')
          .select('xp, bio')
          .eq('id', widget.userId)
          .maybeSingle();
      bool isFollowing = false;
      if (me != null && me != widget.userId) {
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
          _xp = (prof?['xp'] as num?)?.toInt() ?? 0;
          _bio = prof?['bio'] as String? ?? '';
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
    if (c == null || me == null || me == widget.userId) return;
    final bool next = !_following;
    setState(() => _following = next);
    try {
      if (next) {
        await c.from('follows').upsert(<String, dynamic>{
          'follower': me,
          'followee': widget.userId,
        });
      } else {
        await c
            .from('follows')
            .delete()
            .eq('follower', me)
            .eq('followee', widget.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = !next);
    }
  }

  Future<void> _sendMessage() async {
    final String text = _msgCtrl.text.trim();
    final SupabaseClient? c = _client;
    final String? me = _me;
    if (text.isEmpty || c == null || me == null || _sending) return;
    setState(() => _sending = true);
    try {
      // Direct messages live in Orbit's nx_chats / nx_messages (there is no direct_messages table):
      // open (or reuse) the 1:1 chat, then send through the server-checked RPC.
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('پیام ارسال شد')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ارسال پیام ناموفق بود')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSelf = _me == widget.userId;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF232A3B),
                backgroundImage: (widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty)
                    ? NetworkImage(widget.avatarUrl!)
                    : null,
                child: (widget.avatarUrl == null || widget.avatarUrl!.isEmpty)
                    ? Text(
                        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.amber, fontSize: 22, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.username,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _loading ? '...' : 'XP: $_xp',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (!isSelf)
                ElevatedButton(
                  onPressed: _toggleFollow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _following ? Colors.white12 : const Color(0xFFFFA21F),
                    foregroundColor: _following ? Colors.white : Colors.black,
                  ),
                  child: Text(_following ? 'دنبال شده' : 'دنبال کردن'),
                ),
            ],
          ),
          if (_bio.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(_bio, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ],
          if (!isSelf) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'ارسال پیام مستقیم...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1D2333),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _sendMessage,
                  icon: const Icon(Icons.send_rounded, color: Color(0xFFFFA21F)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
