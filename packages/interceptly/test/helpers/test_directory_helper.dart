import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mocks the Flutter `path_provider` method channel to return [tempDirPath].
void mockPathProvider(String tempDirPath) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory' ||
          methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory') {
        return tempDirPath;
      }
      return null;
    },
  );
}

/// Clears any mocked handlers for the Flutter `path_provider` method channel.
void resetPathProviderMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

/// Executes [action] with a freshly created isolated temporary directory,
/// automatically stubbing `path_provider` to point to it and deleting it afterwards.
Future<T> withTempTestDir<T>(Future<T> Function(Directory dir) action) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp('interceptly_test_');
  try {
    mockPathProvider(tempDir.path);
    return await action(tempDir);
  } finally {
    resetPathProviderMock();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
