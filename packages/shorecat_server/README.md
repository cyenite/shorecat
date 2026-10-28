# shorecat_server

Self-hosted Shorecat HTTP server for releases, signed patches, staged rollouts,
health gates and device telemetry. Uses one JSON data directory and requires one
server process per directory.

```bash
dart pub global activate shorecat_server
shorecat_server --host 127.0.0.1 --port 8787 --data ./shorecat-data
```

Read the generated administrator credential from `shorecat-data/admin-token`.
Set `SHORECAT_ADMIN_TOKEN` to supply one instead. Tokens are not logged by default.
Use `--public-url https://updates.example.com` behind a TLS reverse proxy.
SIGINT and SIGTERM flush pending storage before exit.

For the complete dashboard, use the Docker image or pass `--dashboard` with a
built Flutter web dashboard directory. Without it, the server serves a minimal
HTML dashboard. See the [hosting guide](https://github.com/cyenite/shorecat/blob/main/docs/hosting.md)
for Docker, HTTPS, backups and upgrades.
