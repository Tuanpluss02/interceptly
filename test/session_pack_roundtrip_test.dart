import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/inspector_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session pack round-trip through temp file', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('interceptly_bisect');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );

    final session = InspectorSession();
    await session.initialize();
    session.record(
      RawCapture(
        id: 'r1',
        method: 'GET',
        url: 'https://api.example.com/data',
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        statusCode: 200,
        durationMs: 12,
        timestamp: DateTime.now(),
        responseBodyBytes: RawCapture.wrapBytes(
          Uint8List.fromList(utf8.encode('{"ok":true}')),
        ),
        responseContentType: 'application/json',
      ),
    );

    final end = DateTime.now().add(const Duration(seconds: 10));
    while (session.entries.isEmpty) {
      if (DateTime.now().isAfter(end)) {
        throw StateError('no entries within timeout');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(session.entries.length, 1);

    final record = await session.loadDetail(session.entries.first);
    expect(record.responseBodyPreview, '{"ok":true}');

    final big = Uint8List.fromList(
      utf8.encode(jsonEncode({'data': List.filled(2000, 'pad')})),
    );
    session.record(
      RawCapture(
        id: 'r2',
        method: 'GET',
        url: 'https://api.example.com/big',
        requestHeaders: const {},
        responseHeaders: const {'content-type': 'application/json'},
        statusCode: 200,
        durationMs: 12,
        timestamp: DateTime.now(),
        responseBodyBytes: RawCapture.wrapBytes(big),
        responseContentType: 'application/json',
      ),
    );

    final end2 = DateTime.now().add(const Duration(seconds: 10));
    while (session.entries.length < 2) {
      if (DateTime.now().isAfter(end2)) {
        throw StateError('second entry never arrived');
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    final bigEntry = session.entries.firstWhere((e) => e.id == 'r2');
    final bigRecord = await session.loadDetail(bigEntry);
    expect(bigRecord.responseBodyPreview, isNotNull);
    expect(
      bigRecord.responseBodyPreview,
      contains('"data"'),
    );
    await session.dispose();
    await tempDir.delete(recursive: true);
  });
}
