# shorecat architecture

## Pieces and data flow

```
 developer machine                 shorecat server                 device
 ----------------                  ---------------                 ------
 shorecat release  --libapp.so-->  blobs/<sha256>
                   --release----> db.json (release, file fingerprint, keys)

 shorecat patch    --delta------>  blobs/<sha256>    <--check---  Updater (Dart)
   build, diff,    --signature-->  patch record      --offer--->    download, verify,
   sign, publish                   rollout, channel  <--events--    apply, install
                                   health gate
                                                                   ShorecatBoot (Kotlin)
                                                                     picks the library
                                                                     before the engine
```

A patch is always a delta from the **release's own** `libapp.so`, never from
a previous patch, so any device can jump straight to the newest patch.

## Boot state machine

The same algorithm exists twice and the two must stay in step:
`Updater.beginLaunch` (Dart, `shorecat_updater/lib/src/updater.dart`) and
`BootState.decide` (Kotlin, `shorecat_code_push/android/.../BootState.kt`).
On Android only the Kotlin one runs, because the choice has to be made
before the Flutter engine loads any Dart code. The Dart one serves tests and
non-Android hosts.

On each process start (`ShorecatFlutterActivity.getFlutterShellArgs`, once
per process):

1. No `pointers.json`, or its `release_version` differs from the installed
   app: boot the base release. A store update invalidates every patch, and
   the Dart updater wipes them on its next start.
2. `currently_booting` is set: the previous boot never reached its first
   frame. If `boot_attempts >= max_boot_attempts`, mark that patch `bad`
   (`boot_crash`), queue a `boot_failure` event and drop it from
   `next_boot`/`last_booted`; otherwise allow another attempt.
3. Try `next_boot`, then `last_booted`. A candidate boots only if its
   `state.json` says `installed` and the SHA-256 of its `libapp.so` matches
   the recorded hash. A failed check marks it `bad` (`hash_mismatch`).
4. Booting a patch sets `running`, `currently_booting` and increments
   `boot_attempts`, then passes
   `--aot-shared-library-name=<files>/shorecat/patches/<n>/libapp.so`.

After the first frame is rasterized, Dart calls `reportLaunchSuccess`, which
moves `currently_booting` into `last_booted`, resets the attempt count,
queues `launch_success` and deletes patches nothing points at. `bad` patches
keep their `state.json` as a tombstone so they are never reinstalled.

### On-disk contract (`<filesDir>/shorecat/`)

| Path | Writer | Contents |
|---|---|---|
| `client_id` | Dart | Random UUID, the rollout bucket key |
| `pointers.json` | both | `release_version`, `next_boot`, `last_booted`, `currently_booting`, `running`, `boot_attempts`, `max_boot_attempts`, `boot_started_at` |
| `patches/<n>/state.json` | both | `number`, `state` (`downloading`, `installed`, `bad`), `hash`, `reason` |
| `patches/<n>/libapp.so` | Dart | Rebuilt full artifact |
| `patches/<n>/delta.partial` | Dart | Download in progress, resumed with HTTP Range |
| `pending_events.json` | both | Queued events. Kotlin writes `type`, `patch_number`, `timestamp`, `message`; Dart fills in app, client, release and arch when sending |

Every write goes to a uniquely named temp file and is renamed into place.

## Update flow (Dart)

`Updater.update()`:

1. `POST /api/v1/patches/check` with app, release, platform, arch, channel,
   client id and current patch.
2. Remove any local patch listed in `rolled_back_patch_numbers`; repoint
   `next_boot` to `last_booted` or the base release.
3. Skip patches tombstoned `bad`.
4. Verify the Ed25519 signature over the patch payload against the keys in
   the bundled `shorecat.yaml`, before downloading.
5. Download the delta (resumable), check that the delta header's target hash
   is the signed hash, check the base `libapp.so` (read from the APK or
   split APK, or the extracted native library directory) against the
   header's base hash, apply in a background isolate, verify the output
   hash, write `libapp.so`, mark `installed`, set `next_boot`.

## Server API

Public (devices):

| Method | Path | |
|---|---|---|
| POST | `/api/v1/patches/check` | Newest active patch for the channel that includes this device's rollout bucket and is newer than its current patch (or any, if its current one was rolled back) |
| POST | `/api/v1/patches/events` | `download`, `install_success`, `install_failure`, `launch_success`, `boot_failure`, `uninstall` |
| GET | `/api/v1/blobs/<sha256>` | Content addressed, Range support, immutable caching |
| GET | `/` | Dashboard (the built Flutter web app when `--dashboard` is given, a minimal HTML page otherwise) |

Admin (`Authorization: Bearer <token>`): apps (create, update keys and health
gate), blob upload (the server computes the hash), releases, patch creation,
per-arch patch artifacts, publish, and patch updates (status, rollout,
channel, critical flag, notes), recent events, and
`GET /api/v1/apps/<id>/metrics?hours=N` (1 to 744): hourly counts per event
type plus checks, active and known devices, crash-free rate, adoption by
release and patch, and the CPU mix.

Admin calls carry a bearer token and never cookies, so the API answers CORS
for any origin; that lets the dashboard run from `flutter run -d chrome`
against a remote server.

When a patch artifact is attached, the server checks that the delta's base
hash is the release artifact for that arch and that the signature verifies
against one of the app's keys. Patches start as `draft`, become `active`
on publish, and can be `paused` (no new installs) or `rolled_back` (devices
uninstall it).

Health gate (per app, default on): once a patch has at least `min_launches`
(20) launch reports and its boot failure rate exceeds `max_failure_rate`
(5%), it is set to `rolled_back` with the reason recorded.

## Telemetry

`Telemetry` (`shorecat_server/lib/src/telemetry.dart`) keeps hourly event
counts and the last known state of every device per app in
`telemetry.json`, apart from `db.json`. Checks arrive far more often than
anything else, so this file is written at most every three seconds rather
than per request, and on shutdown. Event hours come from the device's
timestamp when it is plausible (within the 31-day retention and not in the
future), so queued events land in the hour they happened. A device's patch
is updated by checks and by `launch_success` events.

## Dashboard

`packages/shorecat_dashboard` is a Flutter web app built from Ashlar UI:
the shell is adapted from the `shop-dashboard` block (inset sidebar, header
bar, account menu), sign-in from `magic-link-sign-in`, and the screens use
its chart, pie, funnel, heatmap, sparkline, data table, sheet, dialog and
toast components (copied into `lib/ui` by the `ashlar` CLI). A `Session`
polls the app, metrics and events every 10 seconds. Funnels only ever show
devices (each step a subset of the one before); event counts, where one
install leads to many launches, are shown as bars.

`tool/shots/screens.dart` renders the README screenshots with
`ashlar shot` from a fixture of real server data, no server needed.

## Lessons from the device test

Two bugs did not show up in desktop tests and did on a phone:

- **Isolate closures capture their whole scope.** Reading the base
  `libapp.so` inside `Isolate.run` from a closure written inside
  `Shorecat.initialize` shared a context with the `Updater`, whose futures
  cannot cross isolates, so every install failed. Isolate entry points are now
  static or top-level functions that take plain values.
- **One temp name per file is not atomic enough.** Two writers of
  `pending_events.json` both used `pending_events.json.tmp`; the second rename
  failed mid-rollback. Each write now uses a unique temp name, event file
  updates go through a lock, and fire-and-forget work swallows its own errors.

The release on the phone carried the first bug in its update path, which no
patch can reach, so it took a new store release. The second was fixed on the
phone by a patch, delivered by the buggy updater.

## Delta format `SCDELTA1`

| Offset | Size | Field |
|---|---|---|
| 0 | 8 | ASCII `SCDELTA1` |
| 8 | 1 | Version (1) |
| 9 | 1 | Compression: 0 none, 1 zlib, 2 bzip2, 3 zstd |
| 10 | 8 | Base length (u64 LE) |
| 18 | 8 | Target length |
| 26 | 32 | Base SHA-256 |
| 58 | 32 | Target SHA-256 |
| 90 | 8 | Control section length (compressed) |
| 98 | 8 | Diff section length |
| 106 | 8 | Extra section length |
| 114 | | Control, diff and extra sections, each compressed on its own |

The control stream is a sequence of `(add varint, copy varint, seek zigzag
varint)` triples. As in bsdiff, `add` bytes are base plus diff bytes (mod
256), `copy` bytes come from the extra stream, then the base cursor moves
by `seek`. Suffix sorting is Larsson-Sadakane (qsufsort) on an explicit
stack. The match search orders a suffix that is a prefix of the target
before it; reference bsdiff treats that case as equal, which makes it
quadratic on zero-filled runs (18 s vs 0.3 s on 200 KB of zeros).

## Signature payload

UTF-8, newline separated:

```
shorecat-patch-v1
<app id>
<release version>
<platform>
<arch>
<patch number>
<target sha256>
```

Public keys are written `ed25519:<base64>`. A release records the keys that
were in `shorecat.yaml` when it was built, and `shorecat patch` picks
whichever local key (current or archived by `shorecat keys rotate`) that
release trusts.
