import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
  });

  test('a signed-in account name becomes the identity once and is persisted', () async {
    final ProfileService p = ProfileService(LocalStore.instance);
    expect(p.hasIdentity, isFalse);
    expect(p.adoptAccountName('player_one'), isTrue);
    expect(p.username, 'player_one');
    await Future<void>.delayed(Duration.zero);

    // A fresh launch reads the saved identity: the identity page has nothing to ask.
    final ProfileService again = ProfileService(LocalStore.instance);
    expect(again.hasIdentity, isTrue);
    expect(again.username, 'player_one');
  });

  test('an existing identity is never overwritten and empty names are ignored', () async {
    final ProfileService p = ProfileService(LocalStore.instance);
    expect(p.adoptAccountName(null), isFalse);
    expect(p.adoptAccountName(' '), isFalse);
    expect(p.hasIdentity, isFalse);
    await p.createIdentity(name: 'Chosen');
    expect(p.adoptAccountName('other_name'), isTrue);
    expect(p.username, 'Chosen');
  });
}
