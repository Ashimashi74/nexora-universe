import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui2/anix_brand.dart';
import '../../core/online/cloud_profile_sync.dart';
import '../../core/online/online_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

/// Sign in / sign up with a USERNAME and password (e-mail optional, no codes). Login accepts the username or the
/// e-mail. The session persists until sign-out; the last username is pre-filled after sign-out, and the fields carry
/// autofill hints so password managers can save and fill them.
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final TextEditingController _id = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _newPass = TextEditingController();
  final TextEditingController _email = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _show = false;
  String? _error;
  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final String? q = GoRouterState.of(context).uri.queryParameters['email'];
    if (q != null && q.isNotEmpty) _id.text = q;
    unawaited(OnlineService.lastUsername().then((String? u) {
      if (mounted && u != null && _id.text.isEmpty) setState(() => _id.text = u);
    }));
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_id, _pass, _user, _newPass, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final OnlineService online = ref.read(onlineProvider);
    if (!online.configured) {
      setState(() => _error = context.tx('اتصال آنلاین تنظیم نشده است.', 'Online authentication is not configured.'));
      return;
    }
    String? err;
    if (_signUp) {
      if (!OnlineService.isValidUsername(_user.text)) {
        err = context.tx('نام کاربری: ۳ تا ۲۰ حرف انگلیسی کوچک، عدد، _ یا .', 'Username: 3–20 of a-z, 0-9, _ or .');
      } else if (_newPass.text.length < OnlineService.minPasswordLength) {
        err = context.tx('رمز حداقل ۸ نویسه باشد.', 'Password must be at least 8 characters.');
      } else if (_email.text.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
        err = context.tx('ایمیل معتبر نیست (اختیاری است؛ می‌توانی خالی بگذاری).', 'That email is not valid (it is optional; you can leave it empty).');
      }
    } else if (_id.text.trim().isEmpty || _pass.text.isEmpty) {
      err = context.tx('نام کاربری (یا ایمیل) و رمز را وارد کن.', 'Enter your username (or email) and password.');
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = _signUp
        ? await online.signUpUsername(_user.text, _newPass.text, email: _email.text)
        : await online.signInIdentifier(_id.text, _pass.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = _friendly(online.lastError);
      });
      return;
    }
    TextInput.finishAutofillContext(); // lets the password manager offer to save the login
    ref.read(settingsProvider).setAuthMode('email');
    ref.read(cloudSyncProvider).start();
    unawaited(online.gamesHello(force: true));
    if (!mounted) return;
    // The username chosen at sign-up is the digital identity: adopt it so the identity page is not asked again.
    final bool ready = ref.read(profileProvider).adoptAccountName(online.accountUsername ?? (_signUp ? OnlineService.normalizeUsername(_user.text) : null));
    if (ready) ref.read(settingsProvider).markOnboarded();
    context.go(ready ? '/hub' : '/onboarding');
  }

  String _friendly(String? value) {
    switch (value) {
      case 'network':
        return context.tx('اتصال اینترنت را بررسی کن.', 'Check your internet connection.');
      case 'invalid_login':
        return context.tx('نام کاربری/ایمیل یا رمز نادرست است.', 'Wrong username/email or password.');
      case 'username_taken':
        return context.tx('این نام کاربری گرفته شده است.', 'That username is taken.');
      case 'bad_username':
        return context.tx('نام کاربری: ۳ تا ۲۰ حرف انگلیسی کوچک، عدد، _ یا .', 'Username: 3–20 of a-z, 0-9, _ or .');
      case 'email_taken':
        return context.tx('این ایمیل قبلاً ثبت شده؛ با آن وارد شو.', 'That email already has an account; log in with it.');
      case 'weak_password':
        return context.tx('رمز ضعیف است (حداقل ۸ نویسه).', 'Password too weak (at least 8 characters).');
      case 'rate_limit':
        return context.tx('تلاش زیاد بود؛ کمی صبر کن.', 'Too many attempts; wait a moment.');
      case 'signup_disabled':
        return context.tx('ثبت‌نام حساب تازه روی سرور بسته است.', 'New sign-ups are disabled on the server.');
      case 'not_configured':
        return context.tx('اتصال آنلاین تنظیم نشده است.', 'Online authentication is not configured.');
      case null:
        return context.tx('انجام نشد. دوباره تلاش کن.', 'That did not work. Try again.');
      default:
        return context.tx('خطای سرور: $value', 'Server error: $value');
    }
  }

  void _continueGuest() {
    ref.read(settingsProvider).setAuthMode('guest');
    final bool hasIdentity = ref.read(profileProvider).hasIdentity;
    context.go(hasIdentity ? '/hub' : '/onboarding');
  }

  Widget _passField(TextEditingController c, String label, Iterable<String> hints) => TextField(
        controller: c,
        enabled: !_busy,
        obscureText: !_show,
        textDirection: TextDirection.ltr,
        autofillHints: hints,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          suffixIcon: IconButton(
            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Scaffold(
      backgroundColor: visual.background,
      body: NxBrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      const AnixLogo(height: 118),
                      const SizedBox(height: 14),
                      Text(_signUp ? context.tx('ساخت حساب نیکسورا', 'Create your NEXORA account') : context.tx('ورود به نیکسورا', 'Log in to NEXORA'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: visual.text, fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 14),
                      SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(value: false, label: Text(context.tx('ورود', 'Log in')), icon: const Icon(Icons.login_rounded)),
                          ButtonSegment<bool>(value: true, label: Text(context.tx('ثبت‌نام', 'Sign up')), icon: const Icon(Icons.person_add_alt_1_rounded)),
                        ],
                        selected: <bool>{_signUp},
                        onSelectionChanged: _busy ? null : (Set<bool> v) => setState(() {
                          _signUp = v.first;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 16),
                      if (!_signUp) ...<Widget>[
                        TextField(
                          key: const ValueKey<String>('auth-id'),
                          controller: _id,
                          enabled: !_busy,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const <String>[AutofillHints.username, AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                              labelText: context.tx('نام کاربری یا ایمیل', 'Username or email'),
                              prefixIcon: const Icon(Icons.person_outline_rounded)),
                        ),
                        const SizedBox(height: 10),
                        _passField(_pass, context.tx('رمز عبور', 'Password'), const <String>[AutofillHints.password]),
                      ] else ...<Widget>[
                        TextField(
                          key: const ValueKey<String>('auth-user'),
                          controller: _user,
                          enabled: !_busy,
                          textDirection: TextDirection.ltr,
                          autocorrect: false,
                          maxLength: 20,
                          autofillHints: const <String>[AutofillHints.newUsername],
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                          ],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                              labelText: context.tx('نام کاربری', 'Username'),
                              helperText: context.tx('a-z، 0-9، _ و . — بعداً همین را برای ورود می‌زنی', 'a-z, 0-9, _ and . — you log in with it'),
                              prefixIcon: const Icon(Icons.alternate_email_rounded)),
                        ),
                        const SizedBox(height: 6),
                        _passField(_newPass, context.tx('رمز عبور (حداقل ۸)', 'Password (min 8)'), const <String>[AutofillHints.newPassword]),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _email,
                          enabled: !_busy,
                          textDirection: TextDirection.ltr,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const <String>[AutofillHints.email],
                          decoration: InputDecoration(
                              labelText: context.tx('ایمیل (اختیاری)', 'Email (optional)'),
                              helperText: context.tx('فقط برای بازیابی؛ به کسی نشان داده نمی‌شود', 'Only for recovery; never shown to anyone'),
                              prefixIcon: const Icon(Icons.email_outlined)),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: Icon(_signUp ? Icons.rocket_launch_rounded : Icons.login_rounded),
                        label: Text(_signUp ? context.tx('ساخت حساب', 'Create account') : context.tx('ورود', 'Log in')),
                      ),
                      if (_busy) ...<Widget>[const SizedBox(height: 12), const LinearProgressIndicator()],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.danger, fontWeight: FontWeight.w700)),
                      ],
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                          onPressed: _busy ? null : _continueGuest,
                          icon: const Icon(Icons.offline_bolt_rounded),
                          label: Text(context.tx('ورود مهمان؛ فقط آفلاین', 'Continue as Guest · offline only'))),
                      const SizedBox(height: 8),
                      Text(
                          context.tx('مهمان به حساب آنلاین، چت، بازی آنلاین، تورنمنت و همگام‌سازی دسترسی ندارد.',
                              'Guest mode has no online account, chat, online games, tournaments, or cloud sync.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: visual.muted, fontSize: 11, height: 1.35)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
