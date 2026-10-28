# shorecat_code_push

Flutter plugin that runs shorecat patches on Android, on the stock engine.

- `Shorecat.initialize()` in `main()`: opens the updater, clears the boot
  breadcrumb after the first frame, checks for a patch in the background.
- `ShorecatFlutterActivity`: extend it from `MainActivity` (`shorecat init`
  does this). It adds `--aot-shared-library-name` for the installed patch.
- `ShorecatBoot.engineArgs(context)`: the same arguments for hosts that build
  their own `FlutterEngine` (add-to-app, cached engines).
- `Shorecat.instance`: `currentPatchNumber`, `nextPatchNumber`,
  `isRestartRequired`, `update()`, `checkForUpdate()`, `restart()`.

Code push only runs in Android release builds; `initialize` returns null
elsewhere. The plugin declares the INTERNET permission, which release builds
lack by default.

The `example` app is the demo used for the on-device test. Its
`shorecat.yaml` points at a local test server; run
`shorecat init --force --server <url> --token <token>` in `example/` to
point it at yours.

See the repository README and `docs/architecture.md`.
