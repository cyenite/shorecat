# shorecat_core

Shared Dart primitives for Shorecat: the SCDELTA1 binary delta format, SHA-256
artifact verification, Ed25519 patch signatures, stable rollout buckets and the
HTTP wire protocol. This package has no Flutter dependency.

```dart
import 'package:shorecat_core/shorecat_core.dart';

final patch = Delta.create(baseBytes, updatedBytes);
final rebuilt = Delta.apply(baseBytes, patch);
```

Use `shorecat_cli` to create and sign app patches and `shorecat_code_push` to
install them in a Flutter Android app. See the
[repository](https://github.com/cyenite/shorecat) for the complete system.
