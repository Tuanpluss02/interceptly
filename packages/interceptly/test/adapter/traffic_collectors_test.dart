import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';

import '../helpers/async_test_utils.dart';
import '../helpers/test_directory_helper.dart';

Future<RequestSummary> _waitForEntry(
  InterceptlyEngine engine,
  String id,
) async {
  await waitForCondition(
    () {
      final entry = engine.byId(id);
      return entry != null && entry.statusCode != 0;
    },
    timeout: const Duration(seconds: 10),
  );
  return engine.byId(id)!;
}

Future<RequestSummary> _waitForFailedEntry(
  InterceptlyEngine engine,
  String id,
) async {
  await waitForCondition(
    () {
      final entry = engine.byId(id);
      return entry != null && entry.hasError;
    },
    timeout: const Duration(seconds: 10),
  );
  return engine.byId(id)!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    await Interceptly.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('collector_test_');
    mockPathProvider(tempDir.path);
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    resetPathProviderMock();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('DefaultHttpTrafficCollector', () {
    test(
      'startRequest creates HttpRequestContext and records pending request in engine',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        expect(collector.engine, equals(engine));

        final uri = Uri.parse('https://api.example.com/items');
        final bodyBytes = Uint8List.fromList([1, 2, 3, 4]);
        final headers = {'authorization': 'Bearer token', 'x-custom': 'val'};

        final context = await collector.startRequest(
          method: 'POST',
          uri: uri,
          headers: headers,
          bodyBytes: bodyBytes,
          contentType: 'application/json',
        );

        expect(context, isNotNull);
        expect(context!.method, equals('POST'));
        expect(context.uri, equals(uri));
        expect(context.url, equals('https://api.example.com/items'));
        expect(context.requestHeaders, equals(headers));
        expect(context.requestBodyBytes, equals(bodyBytes));
        expect(context.requestContentType, equals('application/json'));
        expect(context.id, isNotEmpty);

        // Verify pending entry in engine memory index
        expect(engine.entries.length, equals(1));
        final pending = engine.entries.first;
        expect(pending.id, equals(context.id));
        expect(pending.method, equals('POST'));
        expect(pending.url, equals('https://api.example.com/items'));
        expect(pending.statusCode, equals(0));
      },
    );

    test('startRequest respects custom requestId', () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/custom-id');

      final context = await collector.startRequest(
        method: 'GET',
        uri: uri,
        requestId: 'custom-req-1234',
      );

      expect(context, isNotNull);
      expect(context!.id, equals('custom-req-1234'));
      expect(engine.entries.first.id, equals('custom-req-1234'));
    });

    test('startRequest returns null when engine is disabled', () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();

      engine.disable();
      expect(engine.isEnabled, isFalse);

      final collector = DefaultHttpTrafficCollector();
      final context = await collector.startRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example.com/disabled'),
      );

      expect(context, isNull);
      expect(engine.entries, isEmpty);
    });

    test('startRequest respects shouldCapture filter', () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();
      engine.configure(
        InterceptlySettings(
          shouldCapture: (url) => url.contains('/allowed'),
        ),
      );

      final collector = DefaultHttpTrafficCollector();

      final ignored = await collector.startRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example.com/ignored'),
      );
      expect(ignored, isNull);
      expect(engine.entries, isEmpty);

      final allowed = await collector.startRequest(
        method: 'GET',
        uri: Uri.parse('https://api.example.com/allowed'),
      );
      expect(allowed, isNotNull);
      expect(engine.entries.length, equals(1));
    });

    test(
      'completeResponse calculates duration and records completed RawCapture into engine',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/success');

        final context = await collector.startRequest(
          method: 'GET',
          uri: uri,
        );
        expect(context, isNotNull);

        final responseBytes = Uint8List.fromList([10, 20, 30]);
        final responseHeaders = {
          'content-type': 'application/json',
          'x-resp': 'ok',
        };

        await collector.completeResponse(
          context: context!,
          statusCode: 200,
          headers: responseHeaders,
          bodyBytes: responseBytes,
          responseContentType: 'application/json',
        );

        final entry = await _waitForEntry(engine, context.id);
        expect(entry.id, equals(context.id));
        expect(entry.statusCode, equals(200));
        expect(entry.hasError, isFalse);
        expect(entry.durationMs, greaterThanOrEqualTo(0));
      },
    );

    test(
      'completeResponse with content-length differing from bodyBytes within maxBody does not flag truncation',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/json-length-mismatch');

        final context = await collector.startRequest(
          method: 'GET',
          uri: uri,
        );
        expect(context, isNotNull);

        // Simulated 20 KB JSON with whitespace differences
        final responseBytes = Uint8List(20150);
        final responseHeaders = {
          'content-type': 'application/json',
          'content-length': '20480',
        };

        await collector.completeResponse(
          context: context!,
          statusCode: 200,
          headers: responseHeaders,
          bodyBytes: responseBytes,
          responseContentType: 'application/json',
        );

        final entry = await _waitForEntry(engine, context.id);
        expect(entry.responseSizeBytes, equals(20480));
        expect(entry.responseTruncation.isTruncated, isFalse);
        expect(entry.responseTruncation.stage, equals(TruncationStage.none));
        expect(entry.responseTruncation.hasDataLoss, isFalse);
      },
    );

    test(
      'completeResponse ignores negative content-length (-1) and falls back to bodyBytes length',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/chunked-response');

        final context = await collector.startRequest(
          method: 'GET',
          uri: uri,
        );
        expect(context, isNotNull);

        final responseBytes = Uint8List(500);
        final responseHeaders = {
          'content-type': 'application/json',
          'content-length': '-1',
        };

        await collector.completeResponse(
          context: context!,
          statusCode: 200,
          headers: responseHeaders,
          bodyBytes: responseBytes,
          responseContentType: 'application/json',
        );

        final entry = await _waitForEntry(engine, context.id);
        expect(entry.responseSizeBytes, equals(500));
      },
    );

    test('completeResponse respects explicit durationMs when provided',
        () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();

      final collector = DefaultHttpTrafficCollector();
      final uri = Uri.parse('https://api.example.com/explicit-duration');

      final context = await collector.startRequest(
        method: 'POST',
        uri: uri,
      );
      expect(context, isNotNull);

      await collector.completeResponse(
        context: context!,
        statusCode: 201,
        durationMs: 456,
      );

      final entry = await _waitForEntry(engine, context.id);
      expect(entry.statusCode, equals(201));
      expect(entry.durationMs, equals(456));
    });

    test(
      'failRequest records failed RawCapture with error details and duration',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/failure');

        final context = await collector.startRequest(
          method: 'GET',
          uri: uri,
        );
        expect(context, isNotNull);

        const socketException = SocketException('Connection refused');
        collector.failRequest(
          context: context!,
          error: socketException,
          errorType: 'SocketException',
          errorMessage: 'Connection refused',
        );

        final entry = await _waitForFailedEntry(engine, context.id);
        expect(entry.id, equals(context.id));
        expect(entry.statusCode, equals(0));
        expect(entry.hasError, isTrue);
        expect(entry.errorType, equals('SocketException'));
        expect(entry.errorMessage, equals('Connection refused'));
        expect(entry.durationMs, greaterThanOrEqualTo(0));
      },
    );

    test(
      'failRequest infers errorType and errorMessage when omitted and respects custom statusCode',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/server-error');

        final context = await collector.startRequest(
          method: 'POST',
          uri: uri,
        );
        expect(context, isNotNull);

        final httpError = FormatException('Invalid response syntax');
        collector.failRequest(
          context: context!,
          error: httpError,
          statusCode: 502,
          durationMs: 120,
        );

        final entry = await _waitForFailedEntry(engine, context.id);
        expect(entry.id, equals(context.id));
        expect(entry.statusCode, equals(502));
        expect(entry.hasError, isTrue);
        expect(entry.errorType, equals('FormatException'));
        expect(entry.errorMessage, contains('Invalid response syntax'));
        expect(entry.durationMs, equals(120));
      },
    );

    test(
      'startRequest rethrows SimulatedNetworkException and records failure when offline simulation is active',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        // Configure offline simulation
        engine.setNetworkSimulation(
          NetworkSimulationProfile.offlineProfile,
        );

        final collector = DefaultHttpTrafficCollector();
        final uri = Uri.parse('https://api.example.com/offline-test');

        expect(
          () => collector.startRequest(
            method: 'GET',
            uri: uri,
          ),
          throwsA(isA<SimulatedNetworkException>()),
        );

        // Verify that the failed capture was recorded in engine
        expect(engine.entries.length, equals(1));
        final failedEntry =
            await _waitForFailedEntry(engine, engine.entries.first.id);
        expect(failedEntry.hasError, isTrue);
        expect(failedEntry.errorType, equals('SimulatedNetworkException'));
      },
    );

    test(
      'collector operations never throw unexpected errors outwards (guardCapture resilience)',
      () async {
        final engine = InterceptlyEngine.instance;
        await engine.initialize();

        final collector = DefaultHttpTrafficCollector();
        final dummyContext = HttpRequestContext(
          id: 'dummy-resilience',
          method: 'GET',
          uri: Uri.parse('https://api.example.com/resilience'),
          startedAt: DateTime.now(),
        );

        // Even if engine is disposed, collector completeResponse and failRequest should be safe
        await engine.dispose();

        expect(
          () => collector.completeResponse(
            context: dummyContext,
            statusCode: 200,
          ),
          returnsNormally,
        );

        expect(
          () => collector.failRequest(
            context: dummyContext,
            error: Exception('Some error'),
          ),
          returnsNormally,
        );
      },
    );
  });

  group('HttpCaptureScope and Collector contracts', () {
    test('collector supports custom engine injection and global instance', () {
      final customEngine = InterceptlyEngine(
        settings: const InterceptlySettings(maxBodyBytes: 1234),
      );
      final httpCollector = DefaultHttpTrafficCollector(engine: customEngine);

      expect(httpCollector.engine, equals(customEngine));
      expect(httpCollector.maxBodyBytes, equals(1234));
      expect(HttpTrafficCollector.instance, isA<DefaultHttpTrafficCollector>());
    });

    test('HttpTrafficCollector.begin returns HttpCaptureScope', () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();

      final collector = DefaultHttpTrafficCollector();
      final scope = await collector.begin(
        method: 'GET',
        uri: Uri.parse('https://example.com/api'),
      );

      expect(scope.isActive, isTrue);
      expect(scope.isSettled, isFalse);
      expect(scope.method, equals('GET'));
      expect(scope.uri, equals(Uri.parse('https://example.com/api')));

      await scope.complete(statusCode: 200);
      expect(scope.isSettled, isTrue);

      // Calling complete or fail again should be a no-op
      await scope.complete(statusCode: 500);
      scope.fail('Late error');
      expect(scope.isSettled, isTrue);
    });

    test('HttpCaptureScope.amendRequest updates context before settling',
        () async {
      final engine = InterceptlyEngine.instance;
      await engine.initialize();

      final collector = DefaultHttpTrafficCollector();
      final scope = await collector.begin(
        method: 'GET',
        uri: Uri.parse('https://example.com/initial'),
      );

      scope.amendRequest(
        method: 'POST',
        uri: Uri.parse('https://example.com/amended'),
        headers: {'x-custom': 'header'},
      );

      expect(scope.method, equals('POST'));
      expect(scope.uri, equals(Uri.parse('https://example.com/amended')));
      expect(scope.context?.requestHeaders, equals({'x-custom': 'header'}));

      await scope.complete(statusCode: 200);
      expect(scope.isSettled, isTrue);

      final entry = await _waitForEntry(engine, scope.id!);
      expect(entry.method, equals('POST'));
      expect(entry.url, equals('https://example.com/amended'));
    });

    test('HttpCaptureScope.inactive handles completion calls safely', () async {
      final inactive = HttpCaptureScope.inactive();
      expect(inactive.isActive, isFalse);
      expect(inactive.isSettled, isFalse);
      expect(inactive.id, isNull);
      expect(inactive.method, isNull);
      expect(inactive.uri, isNull);

      inactive.amendRequest(method: 'GET');
      await inactive.complete(statusCode: 200);
      inactive.fail('Some error');
      expect(inactive.isSettled, isFalse);
    });
  });
}
