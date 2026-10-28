import 'package:flutter/widgets.dart';

import 'src/screens/shell.dart';
import 'src/screens/sign_in.dart';
import 'src/session.dart';
import 'ui/app.dart';
import 'ui/app_theme.dart';

void main() => runApp(const DashboardApp());

class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key});

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  final session = Session();

  @override
  void dispose() {
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SessionScope(
    session: session,
    child: AshlarApp(
      title: 'shorecat',
      theme: appTheme,
      darkTheme: appDarkTheme,
      home: const _Home(),
    ),
  );
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) =>
      SessionScope.of(context).isSignedIn ? const Shell() : const SignIn();
}
