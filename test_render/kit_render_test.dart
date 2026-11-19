import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/ui2/anix_kit.dart';
import 'package:nexora/core/ui2/nx2_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

/// Component sheet of the ANIX kit (compare with the pack previews) + a dialog and a sheet in place.
void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en'});
    await LocalStore.init();
    await loadFonts();
  });

  Widget app(Widget body) => ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildNxTheme(),
          builder: (BuildContext context, Widget? child) =>
              RepaintBoundary(key: kShotKey, child: child ?? const SizedBox.shrink()),
          home: Scaffold(backgroundColor: Nx2.deep, body: Nx2Background(scene: Nx2Scene.hub, child: body)),
        ),
      );

  testWidgets('kit sheet', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(app(SafeArea(
      child: ListView(padding: const EdgeInsets.all(14), children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: AnixButton(label: 'PLAY', icon: Icons.play_arrow_rounded, onTap: () {}, height: 56)),
          const SizedBox(width: 8),
          Expanded(child: AnixButton(label: 'SECONDARY', style: AnixButtonStyle.secondary, onTap: () {}, height: 56, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(child: AnixButton(label: 'Ghost', style: AnixButtonStyle.ghost, onTap: () {}, height: 44, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: AnixButton(label: 'Delete', style: AnixButtonStyle.destructive, onTap: () {}, height: 44, fontSize: 13)),
          const SizedBox(width: 8),
          const Expanded(child: AnixButton(label: 'Off', onTap: null, height: 44, fontSize: 13)),
        ]),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          AnixButton(label: 'Loading', onTap: () {}, loading: true, height: 44),
          const SizedBox(width: 8),
          AnixButton(label: 'Choose avatar', style: AnixButtonStyle.secondary, onTap: () {}, height: 40, fontSize: 13),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: <Widget>[
          AnixToggle(value: true, onChanged: (_) {}),
          AnixToggle(value: false, onChanged: (_) {}),
          const AnixToggle(value: true, onChanged: null),
          AnixCheckbox(value: true, onChanged: (_) {}),
          AnixCheckbox(value: false, onChanged: (_) {}),
        ]),
        AnixSwitchTile(value: true, onChanged: (_) {}, title: const Text('Music'), secondary: const Icon(Icons.music_note_rounded)),
        AnixCheckboxTile(value: true, onChanged: (_) {}, title: const Text('Moderation')),
        const SizedBox(height: 6),
        const Row(children: <Widget>[
          AnixPopover(maxWidth: 200, child: Text('Good evening, Ashkan! Long-press me.')),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 4, children: <Widget>[for (final AnixTier t in AnixTier.values) AnixRankEmblem(tier: t, size: 44)]),
        const SizedBox(height: 6),
        Wrap(spacing: 4, children: <Widget>[
          for (int i = 0; i < AnixTier.values.length; i++)
            AnixFramedAvatar(avatarId: AnixAssets.avatarIds[i * 3], tier: AnixTier.values[i], size: 46),
        ]),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          for (final String n in const <String>['home', 'chat', 'arcade', 'rewards', 'shop', 'profile'])
              Padding(padding: const EdgeInsets.all(4), child: AnixNavIcon(icon: n, active: n == 'arcade', size: 34)),
        ]),
        SizedBox(
          height: 200,
          child: Row(children: <Widget>[
            SizedBox(
              width: 138,
              child: AnixGameCard(
                onTap: () {},
                art: const ColoredBox(color: Color(0xFF1A3A5A)),
                footer: const Center(child: Text('Card shell', style: TextStyle(fontWeight: FontWeight.w900))),
              ),
            ),
          ]),
        ),
      ]),
    )));
    await settle(tester, frames: 20);
    await shoot(tester, 'kit/components.png');
  });

  testWidgets('kit dialog', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(app(Builder(builder: (BuildContext context) {
      return Center(
        child: AnixButton(
          label: 'Open',
          onTap: () => showDialog<void>(
            context: context,
            builder: (BuildContext ctx) => AnixDialog(
              title: const Text('Leave the match?'),
              content: const Text('The match counts as a loss if you leave now.'),
              actions: <Widget>[
                TextButton(onPressed: () {}, child: const Text('Stay')),
                FilledButton(onPressed: () {}, child: const Text('Leave')),
              ],
            ),
          ),
        ),
      );
    })));
    await settle(tester, frames: 4);
    await tester.tap(find.text('Open'));
    await settle(tester, frames: 20);
    await shoot(tester, 'kit/dialog.png');
  });

  testWidgets('kit sheet + tooltip', (WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(app(Builder(builder: (BuildContext context) {
      return Column(children: <Widget>[
        const SizedBox(height: 120),
        const Tooltip(message: 'Search', child: Icon(Icons.search_rounded, size: 40)),
        const SizedBox(height: 40),
        AnixButton(
          label: 'Sheet',
          onTap: () => showAnixSheet<void>(
            context: context,
            builder: (BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              const ListTile(leading: Icon(Icons.person_add_rounded), title: Text('Invite a friend')),
              const ListTile(leading: Icon(Icons.share_rounded), title: Text('Share the room code')),
              AnixSwitchTile(value: true, onChanged: (_) {}, title: const Text('Voice chat')),
              const SizedBox(height: 18),
            ]),
          ),
        ),
      ]);
    })));
    await settle(tester, frames: 4);
    final TestGesture g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.search_rounded)));
    await settle(tester, frames: 30);
    await shoot(tester, 'kit/tooltip.png');
    await g.up();
    await settle(tester, frames: 4);
    await tester.tap(find.text('Sheet'));
    await settle(tester, frames: 20);
    await shoot(tester, 'kit/sheet_tooltip.png');
  });
}
