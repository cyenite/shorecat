# shorecat_dashboard

The shorecat monitoring dashboard: a Flutter web app built with
[Ashlar UI](https://ui.ashlar.ke). Components live in `lib/ui` (copied there by
`ashlar add`, so they are ours to change); the shell started from the
`shop-dashboard` block and sign-in from `magic-link-sign-in`.

```bash
flutter build web
shorecat server --dashboard build/web      # served at the server's /
flutter run -d chrome                      # or develop against any server
```

Sign in with the server address and the admin token it printed.

README screenshots come from real data without a server:

```bash
ashlar shot tool/shots/screens.dart:OverviewShot --size 1440x900 --dark
```
