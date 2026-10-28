# Releasing Shorecat

Shorecat's Dart packages are published on pub.dev, and its server image and
installation bundles are published through
[GitHub releases](https://github.com/cyenite/shorecat/releases). Run
`bash tool/bootstrap.sh` for local development; it links the sibling packages in
your working copy using ignored pub overrides.

## Prepare package releases

Update package versions, dependency constraints and changelogs. The five
packages distributed through pub.dev are `shorecat_core`, `shorecat_server`,
`shorecat_updater`, `shorecat_cli` and `shorecat_code_push`. The dashboard is
bundled in the server image, and the example is a development app.

Publish in dependency order: `shorecat_core`, `shorecat_server`,
`shorecat_updater`, `shorecat_cli`, then `shorecat_code_push`. Wait for each required
version to resolve on pub.dev before publishing its dependents. The updater's
development tests depend on the server, so the server precedes it.

Stage each package independently to validate against hosted dependencies:

```bash
package=shorecat_core
staging_root=$(mktemp -d)
bash tool/stage-package.sh "$package" "$staging_root/$package"
cd "$staging_root/$package"
dart pub get
dart analyze
dart test
dart pub publish --dry-run
```

For `shorecat_code_push`, use the corresponding Flutter commands. Staging removes
the development workspace directive and excludes local overrides and build
products. This prevents workspace siblings from masking missing or incompatible
hosted dependencies. Run validation from the staging directory and resolve any
publication errors before continuing.

## Publish Dart packages

For automated publishing, authorize GitHub Actions in each package's pub.dev
Admin tab. Set the repository to `cyenite/shorecat` and configure that package's
tag pattern, for example `shorecat_core-v{{version}}`.

Push the package tag matching its new version. `.github/workflows/publish.yml`
validates the version, stages an independent package, resolves dependencies,
analyzes, tests, performs a dry run and publishes using a temporary OIDC token.
No long-lived pub.dev credential is stored in GitHub. Publish dependent package
tags only after their required versions are available.

See Dart's [automated publishing instructions](https://dart.dev/tools/pub/automated-publishing)
for account configuration and per-package tag authorization.

For a manual release, authenticate with an account authorized to publish the
package, then run `dart pub publish` from the validated staging directory. Use
`flutter pub publish` for `shorecat_code_push`.

## Publish the server image and installation bundle

1. Update all five package versions to the intended image version and refresh
   changelogs. Update hosted dependency constraints where necessary.
2. Update the exact image default in `compose.yaml` and `.env.example`.
   Keep bundle download links pointed at
   `releases/latest/download/shorecat-deploy.tar.gz` so they follow new releases.
   Regenerate lockfiles with the pinned toolchains.
3. Run checks and verify the container locally:

   ```bash
   bash tool/bootstrap.sh
   docker build -t shorecat:release-test .
   bash tool/smoke-container.sh shorecat:release-test
   bash tool/smoke-deployment.sh shorecat:release-test
   ```

4. Push `v<VERSION>` once the release is ready.

If a tag event did not start the workflow, dispatch `Release` from the default
branch with `tag=v<VERSION>`. Both checks and image builds check out that exact
existing tag; there is no need to move or recreate it. In the GitHub Actions UI,
select **Release → Run workflow** and enter the version tag.

`.github/workflows/release.yml` first runs the checks workflow, including
container and backup/restore smoke tests. It then builds Linux amd64 and arm64
images and publishes `ghcr.io/cyenite/shorecat:<VERSION>`. The Dockerfile pins Dart
and Flutter versions; the Flutter web build runs on the builder's platform,
while each native server executable is compiled on its target platform through
Buildx/QEMU. Runtime containers have no SDK and run as UID/GID 10001.

The workflow creates a GitHub release and attaches a deployment archive
containing Compose manifests, HTTPS proxy configuration, sample environment,
backup/restore scripts, hosting instructions and license. GitHub Actions must
have permission to write packages and release assets.

Each release includes identical `shorecat-deploy-v<VERSION>.tar.gz` and
`shorecat-deploy.tar.gz` assets. The stable filename keeps the latest-release
download links working; the versioned filename supports pinned downloads.

After publication, verify the release asset and image can be downloaded without
authentication and that the image contains both supported architectures. The
release workflow publishes installation files; operators install or upgrade their
servers using the [hosting guide](hosting.md).
