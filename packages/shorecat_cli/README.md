# shorecat_cli

Developer CLI for a self-hosted Shorecat server. Initialize a Flutter Android app,
build releases, sign and publish Dart patches, and manage staged rollouts.

```bash
dart pub global activate shorecat_cli
shorecat init --server https://updates.example.com --token <admin-token>
shorecat doctor
shorecat release android
shorecat patch android --rollout 10 --notes "Fix checkout"
```

Install `shorecat_code_push` in the app and call `Shorecat.initialize()` before
`runApp()`. Flutter and the Android build tools must be available for builds.
Release and patch builds must use the same Flutter engine version.

Private signing keys and server credentials are stored under `~/.config/shorecat`.
Back up signing keys; they are needed to publish patches trusted by existing
releases. For CI, use `SHORECAT_TOKEN`, `SHORECAT_PRIVATE_KEY` and/or `SHORECAT_HOME`.

The CLI also includes `shorecat server`. For production hosting, prefer the
[Docker installation](https://github.com/cyenite/shorecat/blob/main/docs/hosting.md).
