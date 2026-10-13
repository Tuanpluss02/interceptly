import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_http/interceptly_http.dart';

class _StreamingMockClient extends http.BaseClient {
  _StreamingMockClient(this.streamController);

  final StreamController<List<int>> streamController;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      streamController.stream,
      200,
      request: request,
    );
  }
}

class _FailingMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw http.ClientException('Simulated network failure');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_http_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
    session = InspectorSession();
    await session.initialize();
  });

  tearDown(() async {
    session.dispose();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('InterceptlyHttpClient', () {
    test(
      'InterceptlyHttpClient records canceled streams promptly upon subscription cancellation',
      () async {
        final streamCtrl = StreamController<List<int>>();
        final innerClient = _StreamingMockClient(streamCtrl);
        final client = InterceptlyHttpClient(innerClient, session);

        final response = await client.send(
          http.Request('GET', Uri.parse('https://api.example.com/stream')),
        );

        expect(session.entries.length, 1);
        expect(session.entries.first.statusCode, 0);
        expect(session.entries.first.hasError, isFalse);

        streamCtrl.add([1, 2, 3, 4]);
        final sub = response.stream.listen((chunk) {});
        await sub.cancel();
        await streamCtrl.close();

        final end = DateTime.now().add(const Duration(seconds: 3));
        while (!session.entries.first.hasError) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'Session entry did not record cancellation within 3 seconds '
              '(was waiting for 45s pending timeout).',
            );
          }
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final entry = session.entries.first;
        expect(entry.hasError, isTrue);
        expect(entry.errorType, 'CancellationException');
        expect(
          entry.errorMessage,
          'Stream subscription was canceled by client.',
        );
      },
    );

    test('records successful response when stream completes normally',
        () async {
      final streamCtrl = StreamController<List<int>>();
      final innerClient = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(innerClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/data')),
      );

      final chunks = <List<int>>[];
      final completer = Completer<void>();
      response.stream.listen(
        chunks.add,
        onDone: completer.complete,
      );

      streamCtrl.add([10, 20, 30]);
      streamCtrl.add([40, 50]);
      await streamCtrl.close();
      await completer.future;

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || session.entries.first.statusCode == 0) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      expect(entry.statusCode, 200);
      expect(entry.hasError, isFalse);
      expect(entry.errorType, isNull);
    });

    test('records stream error when response stream emits error', () async {
      final streamCtrl = StreamController<List<int>>();
      final innerClient = _StreamingMockClient(streamCtrl);
      final client = InterceptlyHttpClient(innerClient, session);

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/failing-stream')),
      );

      final completer = Completer<void>();
      response.stream.listen(
        (_) {},
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      streamCtrl.addError(Exception('stream broken mid-flight'));
      await streamCtrl.close();
      await completer.future;

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, contains('Exception'));
      expect(entry.errorMessage, contains('stream broken mid-flight'));
    });

    test('records transport failure when inner send throws', () async {
      final innerClient = _FailingMockClient();
      final client = InterceptlyHttpClient(innerClient, session);

      await expectLater(
        () => client.send(
          http.Request('GET', Uri.parse('https://api.example.com/offline')),
        ),
        throwsA(isA<http.ClientException>()),
      );

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || !session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'ClientException');
      expect(entry.errorMessage, contains('Simulated network failure'));
    });
  });
}
