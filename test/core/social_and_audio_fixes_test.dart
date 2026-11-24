import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/audio/audio_mix.dart';
import 'package:nexora/core/audio/music_service.dart';
import 'package:nexora/core/online/online_config.dart';
import 'package:nexora/core/online/social_api.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/finger_soccer/core/bm_data.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
    NxAudioMix.voice.value = false;
    NxAudioMix.talking.value = false;
  });

  test('menu music stays silent while tracking inGame state', () async {
    final MusicService m = MusicService.instance;
    await m.start();
    expect(m.inGameListenable.value, isFalse);
    m.enterGame();
    expect(m.inGameListenable.value, isTrue);
    m.exitGame();
    expect(m.inGameListenable.value, isFalse);
  });

  test('NxAudioMix ducks game audio smoothly during voice chat and talking', () {
    expect(NxAudioMix.gain, 1.0);
    NxAudioMix.voice.value = true;
    expect(NxAudioMix.gain, closeTo(0.42, 0.01));
    NxAudioMix.talking.value = true;
    expect(NxAudioMix.gain, closeTo(0.16, 0.01));
    NxAudioMix.talking.value = false;
    NxAudioMix.voice.value = false;
    expect(NxAudioMix.gain, 1.0);
  });

  test('real username validation enforces 3..20 ASCII username rules and authoritative server sync', () async {
    expect(ProfileService.isValidRealUsername('ashi_74'), isTrue);
    expect(ProfileService.isValidRealUsername('nx.pilot'), isTrue);
    expect(ProfileService.isValidRealUsername('ab'), isFalse);
    expect(ProfileService.isValidRealUsername('this_username_is_way_too_long_123'), isFalse);
    expect(ProfileService.isValidRealUsername('کاوشگر'), isFalse);

    final ProfileService p = ProfileService(LocalStore.instance);
    await p.createIdentity(name: 'GuestLocal');
    expect(p.username, 'GuestLocal');

    // Signing in to a real server account adopts the authoritative server username instead of keeping a guest name.
    p.applyCloudBlob(
      const <String, dynamic>{},
      replace: false,
      serverName: 'ashi818',
      serverAuthoritativeName: true,
    );
    expect(p.username, 'ashi818');

    await p.setConfirmedUsername('nexora_pro');
    expect(p.username, 'nexora_pro');
  });

  test('NxUser.fromRow parses follow relationship and avatarUrl from _nx_user_card', () {
    final NxUser u = NxUser.fromRow(<String, dynamic>{
      'id': '00000000-0000-0000-0000-000000000001',
      'username': 'hosein',
      'display_name': 'Hosein',
      'avatar_url': 'https://example.com/a.webp',
      'level': 12,
      'xp': 1850,
      'is_following': true,
      'follows_me': true,
      'is_pending': false,
    });
    expect(u.username, 'hosein');
    expect(u.displayName, 'Hosein');
    expect(u.avatarUrl, 'https://example.com/a.webp');
    expect(u.level, 12);
    expect(u.xp, 1850);
    expect(u.isFollowing, isTrue);
    expect(u.followsMe, isTrue);
    expect(u.isPending, isFalse);
    expect(OnlineConfig.socialEnabled, isFalse);
  });

  test('all 22 Finger Soccer balls are exposed to shop and selection', () {
    expect(NB, 22);
    expect(kBmBallN.length, 22);
    expect(kBmBallFa.length, 22);
    expect(kBmBallSlug.length, 22);
  });
}
