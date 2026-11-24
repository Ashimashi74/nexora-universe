import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:nexora/core/online/voice_connect.dart';

void main() {
  group('VoiceGrantCache', () {
    late DateTime now;
    late VoiceGrantCache cache;
    int calls = 0;

    Future<Map<String, dynamic>?> fetch() async {
      calls++;
      return <String, dynamic>{'token': 't$calls', 'url': 'wss://x', 'ttl': 900};
    }

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      calls = 0;
      cache = VoiceGrantCache(clock: () => now);
    });

    test('reuses a grant until shortly before it expires', () async {
      expect((await cache.get('k', fetch))!['token'], 't1');
      now = now.add(const Duration(minutes: 11));
      expect((await cache.get('k', fetch))!['token'], 't1');
      now = now.add(const Duration(minutes: 1, seconds: 1)); // 12m01s > 15m - 3m margin
      expect((await cache.get('k', fetch))!['token'], 't2');
      expect(calls, 2);
    });

    test('prefetch and tap share one in-flight request', () async {
      cache.prefetch('k', fetch);
      final Map<String, dynamic>? g = await cache.get('k', fetch);
      expect(g!['token'], 't1');
      expect(calls, 1);
    });

    test('errors are never cached and invalidate forces a refetch', () async {
      final Map<String, dynamic>? e = await cache.get('k', () async => <String, dynamic>{'error': 'not_member'});
      expect(e!['error'], 'not_member');
      expect(cache.peek('k'), isNull);
      await cache.get('k', fetch);
      cache.invalidate('k');
      await cache.get('k', fetch);
      expect(calls, 2);
    });

    test('keys are independent', () async {
      await cache.get('a', fetch);
      await cache.get('b', fetch);
      expect(cache.peek('a')!['token'], 't1');
      expect(cache.peek('b')!['token'], 't2');
    });
  });

  test('voice room options favour low-latency speech', () {
    final lk.RoomOptions o = voiceRoomOptions();
    expect(o.defaultAudioPublishOptions.dtx, isTrue);
    expect(o.defaultAudioPublishOptions.red, isTrue);
    expect(o.defaultAudioPublishOptions.encoding, lk.AudioEncoding.presetSpeech);
    expect(o.defaultAudioCaptureOptions.echoCancellation, isTrue);
    expect(o.defaultAudioCaptureOptions.noiseSuppression, isTrue);
    expect(o.defaultAudioCaptureOptions.autoGainControl, isTrue);
    expect(o.adaptiveStream && o.dynacast, isTrue);
    expect(voiceConnectOptions.timeouts.connection, lessThan(const Duration(seconds: 10)));
  });
}
