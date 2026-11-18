import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import 'account_page.dart';

/// Settings (STEP_12, P13, P16, P27, P28).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    String qLabel(GraphicsQuality q) => switch (q) {
          GraphicsQuality.low => context.tx('کم', 'Low'),
          GraphicsQuality.medium => context.tx('متوسط', 'Medium'),
          GraphicsQuality.high => context.tx('بالا', 'High'),
          GraphicsQuality.ultra => context.tx('فوق‌العاده', 'Ultra'),
        };
    return NxWorldScaffold(
      title: context.tx('تنظیمات', 'SETTINGS'),
      palette: WorldPalette.hub,
      showWallet: false,
      body: ListView(
        padding: const EdgeInsets.all(NxSpace.md),
        children: [
          _section(context, context.tx('تم ظاهری', 'Appearance')),
          GlassPanel(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                s.appearanceMode == NxAppearanceMode.light
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                color: visual.accent,
              ),
              title: Text(context.tx('حالت روشن', 'Light appearance')),
              subtitle: Text(context.tx(
                'پس‌زمینه‌ها و اجزای اصلی برنامه را روشن می‌کند.',
                'Use light surfaces and colors across the app.',
              )),
              value: s.appearanceMode == NxAppearanceMode.light,
              onChanged: (light) => s.appearanceMode =
                  light ? NxAppearanceMode.light : NxAppearanceMode.dark,
            ),
          ),
          const SizedBox(height: NxSpace.sm),
          GlassPanel(
            child: Column(children: [
              _appearanceOption(
                context,
                settings: s,
                theme: NxVisualTheme.gold,
                title: 'طلایی لوکس / Gold Luxe',
                description: context.tx(
                  'جزئیات طلایی فلزی؛ سازگار با حالت روشن و تیره.',
                  'Metallic gold accents, adapted for light and dark modes.',
                ),
                colors: s.appearanceMode == NxAppearanceMode.light
                    ? const [
                        Color(0xFFF4F6FA),
                        Color(0xFF805700),
                        Color(0xFF875323),
                      ]
                    : const [
                        Color(0xFF050A14),
                        Color(0xFFF3C56B),
                        Color(0xFFB77D35),
                      ],
              ),
              const SizedBox(height: 10),
              _appearanceOption(
                context,
                settings: s,
                theme: NxVisualTheme.neon,
                title: 'نئون کیهانی / Cosmic Neon',
                description: context.tx(
                  'درخشش آبی و بنفش؛ سازگار با حالت روشن و تیره.',
                  'Electric blue and violet accents, adapted for light and dark modes.',
                ),
                colors: s.appearanceMode == NxAppearanceMode.light
                    ? const [
                        Color(0xFFF3F7FC),
                        Color(0xFF00699D),
                        Color(0xFF6338B3),
                      ]
                    : const [
                        Color(0xFF030713),
                        Color(0xFF2FBFFF),
                        Color(0xFF9958FF),
                      ],
              ),
            ]),
          ),
          _section(context, context.tx('گرافیک و حرکت', 'Graphics & motion')),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tx('کیفیت گرافیک', 'Graphics quality'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SegmentedButton<GraphicsQuality>(
                segments: [
                  for (final q in GraphicsQuality.values)
                    ButtonSegment(value: q, label: Text(qLabel(q))),
                ],
                selected: {s.quality},
                onSelectionChanged: (v) => s.quality = v.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(
                context.tx(
                    'کیفیت کمتر = ستاره، ذره و جلوه‌ی کمتر و باتری بیشتر.',
                    'Lower quality = fewer stars, particles and effects, better battery.'),
                style: TextStyle(
                    color: NxThemeColors.of(context).muted, fontSize: 12),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.reducedMotion,
                onChanged: (v) => s.reducedMotion = v,
                title: Text(context.tx('کاهش حرکت', 'Reduced motion')),
                subtitle: Text(context.tx(
                    'انیمیشن‌های بلند و حرکت دوربین خاموش',
                    'Disable long animations and camera moves')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.haptics,
                onChanged: (v) => s.haptics = v,
                title: Text(context.tx('لرزش لمسی', 'Haptics')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.sound,
                onChanged: (v) => s.sound = v,
                title: Text(context.tx('بازخورد بازی‌ها', 'Game feedback')),
              ),
            ]),
          ),
          _section(context, context.tx('زبان', 'Language')),
          GlassPanel(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fa', label: Text('فارسی')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.languageCode},
              onSelectionChanged: (v) => s.languageCode = v.first,
              showSelectedIcon: false,
            ),
          ),
          _section(context, context.tx('سفر اول', 'The First Journey')),
          GlassPanel(
            child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.movie_filter_rounded,
                    color: NxColors.violet),
                title: Text(context.tx('پخش کامل سفر', 'Replay full journey')),
                onTap: () => context.go('/journey'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fast_forward_rounded,
                    color: NxColors.turquoise),
                title: Text(context.tx('نسخه‌ی کوتاه سفر', 'Short journey')),
                onTap: () => context.go('/journey?mode=short'),
              ),
            ]),
          ),
          _section(context, context.tx('حساب و داده', 'Account & data')),
          GlassPanel(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Explorer ID: ${p.explorerId}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: visual.text)),
              const SizedBox(height: 4),
              Text(
                context.tx(
                    'یک نسخه از داده‌ها همیشه روی همین گوشی می‌ماند (کار آفلاین).',
                    'A copy of your data always stays on this phone (works offline).'),
                style: TextStyle(
                    color: NxThemeColors.of(context).muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              const AccountStatusCard(),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: NxColors.danger),
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(context.tx('حذف هویت و همه‌ی داده‌ها',
                    'Delete identity and all data')),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.tx('مطمئنی؟', 'Are you sure?')),
                      content: Text(ctx.tx(
                          'همه‌ی پیشرفت، آیتم‌ها و پست‌ها پاک می‌شوند. قابل بازگشت نیست.',
                          'All progress, items and posts will be erased. This cannot be undone.')),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(ctx.tx('انصراف', 'Cancel'))),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: NxColors.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(ctx.tx('حذف', 'Delete')),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    final store = LocalStore.instance;
                    for (final k in store.prefs.getKeys().toList()) {
                      if (!k.startsWith('settings.')) await store.remove(k);
                    }
                    await p.resetAll();
                    if (context.mounted) context.go('/onboarding');
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: NxSpace.xl),
          Center(
            child: Text(
                'NEXORA · YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color:
                        NxThemeColors.of(context).muted.withValues(alpha: 0.6),
                    fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, NxSpace.lg, 4, NxSpace.sm),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: NxThemeColors.of(context).accent,
                letterSpacing: 0.5)),
      );

  Widget _appearanceOption(
    BuildContext context, {
    required AppSettings settings,
    required NxVisualTheme theme,
    required String title,
    required String description,
    required List<Color> colors,
  }) {
    final visual = NxThemeColors.of(context);
    final selected = settings.visualTheme == theme;
    return GlassPanel(
      padding: const EdgeInsets.all(14),
      radius: NxRadius.md,
      onTap: () => settings.visualTheme = theme,
      borderColor:
          selected ? visual.accent : visual.border.withValues(alpha: 0.55),
      tint: selected ? visual.accent.withValues(alpha: 0.08) : null,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors),
              border: Border.all(
                  color: colors[1].withValues(alpha: 0.8), width: 1.3),
              boxShadow: [
                BoxShadow(
                    color: colors[1].withValues(alpha: 0.22), blurRadius: 12)
              ],
            ),
            child: Icon(
                theme == NxVisualTheme.gold
                    ? Icons.workspace_premium_rounded
                    : Icons.bolt_rounded,
                color: Colors.white,
                size: 27),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: visual.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15)),
              const SizedBox(height: 4),
              Text(description,
                  style: TextStyle(
                      color: visual.muted, fontSize: 11, height: 1.45)),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? visual.accent : visual.muted, size: 22),
        ],
      ),
    );
  }
}
