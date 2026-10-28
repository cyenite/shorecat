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

Sign in with the server address and admin token. For a locally started server,
read the token from `shorecat-data/admin-token`, or use the value supplied through
`SHORECAT_ADMIN_TOKEN`.

The [Docker installation](../../docs/hosting.md) includes the built dashboard.

README screenshots come from real data without a server:

```bash
ashlar shot tool/shots/screens.dart:OverviewShot --size 1440x900 --dark
```
