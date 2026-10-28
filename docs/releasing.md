# Releasing Shorecat

The Dart packages and deployment image are separate distributions. No publication
is needed to build and run the server from source. Run `bash tool/bootstrap.sh`
for local development; it links unpublished packages with ignored pub overrides.

## Package prerequisites

The five distributable packages include MIT licenses, READMEs, changelogs,
repository metadata and hosted version constraints. The dashboard and example
remain unpublished applications. Local sibling paths are not present in the
distributable packages' dependency declarations.

Publish in dependency order: `shorecat_core`, `shorecat_server`,
`shorecat_updater`, `shorecat_cli`, then `shorecat_code_push`. Wait for each version
to resolve on pub.dev before publishing dependents. The updater's development
tests depend on the server, so the server precedes it.

The first release of a new package must be published interactively by an
authorized pub.dev account. Before publication, confirm package-name availability
and ownership; repository access alone does not grant pub.dev ownership.

```bash
# Repeat per package in the order above, choosing a new staging path each time.
bash tool/stage-package.sh shorecat_core /tmp/shorecat-core-0.1.0
cd /tmp/shorecat-core-0.1.0
dart pub get
dart analyze
dart test
dart pub publish --dry-run
dart pub publish
```

For `shorecat_code_push`, use the corresponding Flutter commands. Staging removes
the development workspace directive and excludes local overrides and build
products. That forces dependency resolution against hosted packages, rather than
silently validating against workspace siblings. It also makes the package
independently usable outside this monorepo. Run validation from the staging
directory; don't publish from a directory with local dependency overrides.

A dependent package's dry run cannot fully pass until its dependencies are
available on pub.dev. Do not bypass those validation failures with `--force`.

## Later package releases

After the first interactive publication, enable GitHub Actions publishing in each
package's pub.dev Admin tab. Set the repository to `cyenite/shorecat` and configure
that package's tag pattern, for example `shorecat_core-v{{version}}`.

Update package versions, constraints and changelogs, then push the corresponding
package tag. `.github/workflows/publish.yml` validates the version, stages an
independent package, resolves dependencies, analyzes, tests, performs a dry run,
and publishes using a temporary OIDC token. No long-lived pub.dev credential is
stored in GitHub. Publish dependent package tags only after their required
versions are available.

See Dart's [automated publishing instructions](https://dart.dev/tools/pub/automated-publishing)
for the initial account setup and per-package tag authorization.

## Container release

1. Update all five package versions to the intended image version and refresh
   changelogs. Update hosted dependency constraints where necessary.
2. Update the exact image default in `compose.yaml`, `.env.example` and hosting
   examples; regenerate lockfiles with the pinned toolchains.
3. Run checks and verify the container locally:

   ```bash
   bash tool/bootstrap.sh
   docker build -t shorecat:release-test .
   bash tool/smoke-container.sh shorecat:release-test
   ```

4. Push `v<VERSION>` once the release is ready.

If a tag event did not start the workflow, dispatch `Release` from the default
branch with `tag=v<VERSION>`. Both checks and image builds check out that exact
existing tag; there is no need to move or recreate it:

```bash
gh workflow run release.yml --ref main -f tag=v0.1.0
```

`.github/workflows/release.yml` first runs the checks workflow, including a local
image smoke test. It then builds Linux amd64 and arm64 images and publishes
`ghcr.io/cyenite/shorecat:<VERSION>` plus a minor-version tag. The Dockerfile pins
Dart and Flutter versions; the Flutter web build runs on the builder's platform,
while each native server executable is compiled on its target platform through
Buildx/QEMU. Runtime containers have no SDK and run as UID/GID 10001.

The release workflow creates a GitHub release and attaches a deployment archive
containing Compose manifests, the HTTPS proxy configuration, sample environment,
backup/restore scripts, hosting instructions and license. Make the GHCR package
public once for anonymous pulls, or document registry authentication for private
distribution. GitHub Actions must be allowed to write packages and release assets.

The workflow does not install Shorecat on a user's server. It publishes an image
and downloadable installation files. First package publication and pub.dev's
initial OIDC authorization are account setup steps, not actions a Docker build can
perform.
