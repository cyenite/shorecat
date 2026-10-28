// Adapted from the Ashlar UI magic-link-sign-in block: one form, one mark,
// with the admin token in place of an email address.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../ui/button.dart';
import '../../ui/form.dart';
import '../../ui/theme.dart';
import '../session.dart';

class SignIn extends StatefulWidget {
  const SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final _form = GlobalKey<FormState>();
  bool isBusy = false;
  String token = '';
  String? error;
  late String server = SessionScope.of(context).server;

  Future<void> _submit() async {
    if (!_form.currentState!.submit()) return;
    setState(() {
      isBusy = true;
      error = null;
    });
    try {
      await SessionScope.of(context).signIn(server, token.trim());
    } on Object catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(t.radiusXl),
                    ),
                    child: AshlarIcon(
                      AshlarIconsRoundedStroke.cat,
                      size: 28,
                      color: c.primaryForeground,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Open the cat flap',
                  textAlign: TextAlign.center,
                  style: t.text.xl.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your shorecat server printed an admin token when it started. '
                  'Paste it here to watch your patches land on their feet.',
                  textAlign: TextAlign.center,
                  style: t.text.sm.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(height: 24),
                FormText(
                  label: const Text('Server'),
                  initialValue: server,
                  keyboardType: TextInputType.url,
                  onChanged: (v) => server = v,
                  validator: Validate.required('Enter the server address.'),
                ),
                const SizedBox(height: 16),
                FormText(
                  label: const Text('Admin token'),
                  obscureText: true,
                  placeholder: 'Paste the token',
                  onChanged: (v) => token = v,
                  onSubmitted: (_) => _submit(),
                  forceErrorText: error,
                  validator: Validate.required('Enter the admin token.'),
                ),
                const SizedBox(height: 16),
                Button(
                  expand: true,
                  onPressed: isBusy ? null : _submit,
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.pawPrint),
                  child: Text(isBusy ? 'Checking...' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
