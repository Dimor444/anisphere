import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side driver for `flutter drive --driver=test_driver/integration_test.dart`.
/// Saves screenshots taken with `binding.takeScreenshot(name)` to
/// build/integration_screenshots/<name>.png.
Future<void> main() {
  return integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('build/integration_screenshots/$name.png')
        ..createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
