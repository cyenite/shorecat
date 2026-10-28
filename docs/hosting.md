# Hosting Shorecat

Shorecat runs as one server container with its dashboard included. It stores apps,
releases, patches, telemetry and generated credentials in one persistent volume.
The server does not need Dart, Flutter, PostgreSQL or Redis installed on the host.
Run exactly one Shorecat instance per data volume; the JSON store is not clustered.

## Install from a release

Use a Linux amd64 or arm64 server with Docker Engine and Docker Compose installed.
For public HTTPS, point a domain's A record (and AAAA record, if used) at the server
and allow inbound TCP ports 80 and 443. UDP 443 is optional for HTTP/3.

Download `shorecat-deploy-v<VERSION>.tar.gz` from the repository's
[GitHub releases](https://github.com/cyenite/shorecat/releases) and extract it into
a directory you will keep, for example `/opt/shorecat`. Deployment bundles and
images become available after the first release workflow completes. Until then,
use the source-build instructions below.

```bash
tar -xzf shorecat-deploy-v0.1.0.tar.gz
cp .env.example .env
chmod 600 .env
```

Edit `.env`: set `SHORECAT_PUBLIC_URL=https://updates.your-domain.com` and select
the released `SHORECAT_IMAGE` version. Keep
`COMPOSE_FILE=compose.yaml:compose.https.yaml` to use the included Caddy proxy.
Then start the service:

```bash
docker compose pull
docker compose up -d
docker compose ps
docker compose exec shorecat cat /data/admin-token
```

Open your public URL and sign in with that token. The token is generated once,
persisted in the volume, and never printed in startup logs. Alternatively set
`SHORECAT_ADMIN_TOKEN` in `.env` before startup and sign in with that value; in
that mode the environment value takes precedence over any stored token.
An empty environment value uses the generated token. Keep `.env` and backups
private. Signing private keys belong on developer/CI machines, not this server.

Caddy obtains and renews certificates automatically. Its certificate state has
separate persistent volumes. Check `docker compose logs caddy` if certificate
issuance fails; the domain must resolve correctly and ports 80/443 must be free.

The first GHCR image publication may require the repository owner to change the
package visibility to public before anonymous users can pull it. Private images
require `docker login ghcr.io` with credentials allowed to read that package.

## Use an existing reverse proxy

Set `COMPOSE_FILE=compose.yaml` in `.env` and leave
`SHORECAT_BIND_ADDRESS=127.0.0.1`. Configure the host proxy to terminate HTTPS and
forward **all paths**, including `/api/v1/` and `/healthz`, to
`http://127.0.0.1:8787`. Allow large release uploads and sufficiently long upload
timeouts; artifacts can be much larger than ordinary JSON requests. Preserve
Range request headers for resumable downloads.

`SHORECAT_PUBLIC_URL` must be the HTTPS origin devices can reach, without a path,
query or fragment. This controls the URLs returned for patch downloads. Do not
put an interactive proxy login in front of device API routes.

For a proxy in another container, attach it to the Compose network and forward to
`shorecat:8080`; `127.0.0.1` inside that proxy container refers to the proxy itself.

## Build from source or try locally

```bash
git clone https://github.com/cyenite/shorecat.git
cd shorecat
cp .env.example .env
```

For local development, set `SHORECAT_PUBLIC_URL=http://localhost:8787` and
`COMPOSE_FILE=compose.yaml:compose.build.yaml` in `.env`, then run:

```bash
docker compose up -d --build
docker compose exec shorecat cat /data/admin-token
```

The Dockerfile builds the dashboard and native Dart server in separate stages;
the runtime image contains neither SDK. For a public source deployment, set your
HTTPS origin and use
`COMPOSE_FILE=compose.yaml:compose.build.yaml:compose.https.yaml` instead.

Physical phones cannot reach a server through `localhost` on the phone. Use the
public HTTPS URL when connecting an app. The generated development APK also needs
appropriate Android cleartext configuration if you deliberately use HTTP.

## Connect a Flutter app

After the packages have been published to pub.dev:

```bash
dart pub global activate shorecat_cli
flutter pub add shorecat_code_push
shorecat init --server https://updates.your-domain.com --token <admin-token>
shorecat doctor
```

Add the Dart pub cache's `bin` directory to PATH if your shell cannot find
`shorecat` (usually `~/.pub-cache/bin` on Linux/macOS).
Import `package:shorecat_code_push/shorecat_code_push.dart` and initialize it:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Shorecat.initialize();
  runApp(const MyApp());
}
```

`init` registers the app, generates a private signing key, writes public
configuration and switches a standard Kotlin MainActivity to Shorecat's activity.
Customized activities need manual integration. Back up
`~/.config/shorecat/keys/` separately: losing the keys can prevent signing patches
trusted by existing releases. Server backups do not include these keys.

Build and distribute the initial release before pushing patches:

```bash
shorecat release android
# Distribute the resulting release through your normal channel, then fix Dart code.
shorecat patch android --rollout 10 --notes "Fix checkout crash"
```

Android is currently supported. Patches carry Dart code; native code and assets
need a new app release. Release and patch builds must use the same Flutter engine.
See the root README for distribution-policy limitations.

Before the first pub.dev release, contributors can use `bash tool/bootstrap.sh`,
run the CLI from this checkout and use a path dependency for the plugin with the
same local dependency overrides generated by bootstrap.

## Configuration

The native executable and `shorecat server` support the same options. Command-line
options override environment variables:

- `--data` / `SHORECAT_DATA`: data directory (default `shorecat-data`; image `/data`).
- `--host` / `SHORECAT_HOST`: interface (default `127.0.0.1`; image `0.0.0.0`).
- `--port` / `SHORECAT_PORT`: internal port (default/image `8080`).
- `--public-url` / `SHORECAT_PUBLIC_URL`: public HTTP(S) origin.
- `--dashboard` / `SHORECAT_DASHBOARD`: built dashboard directory (image `/app/dashboard`).
- `SHORECAT_ADMIN_TOKEN`: optional administrator token, with no command-line equivalent.
- `--health-check`: probe the configured local `/healthz` endpoint and exit 0/1.
- `--show-admin-token`: explicitly print credentials at startup for an interactive session.

In `.env`, `SHORECAT_PORT` configures the **host mapping** (default `8787`). The
container continues listening on `8080`; Compose does not pass that variable into
the container. `SHORECAT_BIND_ADDRESS` controls host exposure. The default loopback
binding is enough for the included Caddy proxy or a host reverse proxy.

The image runs as UID/GID 10001. Named volumes receive the correct ownership on
creation. If replacing one with a bind mount, create a writable directory owned
by `10001:10001` first. Container startup does not require root.

## Back up and restore

From the deployment directory, run:

```bash
bash tool/backup.sh
```

The script stops Shorecat, archives the complete data volume, then restarts it if
it was running. This causes brief downtime and produces a consistent snapshot.
Archives are created with private permissions under `backups/` by default. Copy
them off the server along with a secure copy of `.env`, deployment files and the
image version. The archive contains the generated admin token and release data.

Restore on a replacement host by extracting the deployment bundle, restoring
`.env`, pulling the same image version, then running:

```bash
bash tool/restore.sh backups/shorecat-YYYYMMDD-HHMMSS.tar.gz --replace-data
docker compose up -d
```

On an existing installation, make a fresh backup first: restore explicitly
replaces the current data volume contents. Keep the same public URL so installed
apps continue reaching the server. If `.env` supplies an admin token, that value
still overrides the token in the restored archive. Caddy can obtain new
certificates; its volumes are not included in the Shorecat data archive.

## Upgrade and roll back

1. Read the target release notes and make a backup.
2. Save the current image version and deployment configuration.
3. Update deployment files from the new bundle and set `SHORECAT_IMAGE` to the new
   exact version in `.env`.
4. Run `docker compose pull && docker compose up -d`.
5. Check `docker compose ps`, `/healthz`, dashboard login and a patch check.

Never delete the data volume during an upgrade (`docker compose down -v` deletes
it). Keep the same deployment directory/project name, or explicitly preserve the
volume when moving the deployment. Pin exact image versions rather than a floating
tag. For a rollback, restore the prior deployment files, image version **and its
matching backup**, unless release notes explicitly confirm backward-compatible
storage. Restoring a backup discards changes made after that snapshot.

Docker restarts the service after a process exit or host reboot unless explicitly
stopped. Health checks report failures; Docker's restart policy does not restart
a process solely because it is unhealthy. Inspect `docker compose logs shorecat`,
disk space and volume permissions when a health check fails. SIGTERM and SIGINT
stop the server and flush pending storage and telemetry before exit.
