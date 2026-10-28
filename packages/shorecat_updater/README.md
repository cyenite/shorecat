# shorecat_updater

Pure Dart patch updater for Shorecat. Checks for updates, verifies signatures,
downloads resumable deltas, rebuilds artifacts and tracks boot success/rollback.

Flutter applications should use `shorecat_code_push`, which integrates this
updater with the Android boot hook and first-frame reporting. This lower-level
package is for custom hosts and tooling; it does not itself arrange for the
Flutter engine to load a patched artifact.

See the [architecture](https://github.com/cyenite/shorecat/blob/main/docs/architecture.md)
for the state machine, artifact format and signing contract.
