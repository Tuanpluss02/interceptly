// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/adapter.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/engine/body_decode_service.dart';
import 'package:interceptly/src/engine/body_store.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/realtime_store.dart';
import 'package:interceptly/src/engine/search_service.dart';
import 'package:interceptly/src/engine/writer_isolate.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/service_extension/http_extension_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    await Interceptly.resetForTesting();
    dir = await Directory.systemTemp.createTemp('interceptly_regressions_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
  });

  tearDown(() async {
    await Interceptly.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  test('stream preserves data after a recoverable source error', () async {
    final source = StreamController<List<int>>();
    final output = <int>[];
    final errors = <Object>[];
    final done = Completer<void>();

    teeStreamCapture(
      source.stream,
      maxBytes: 100,
      onDone: (_, __) {},
      onError: (_, __, ___, ____) {},
      onCancel: (_, __) {},
    ).listen(
      (chunk) => output.addAll(chunk),
      onError: (Object e) => errors.add(e),
      onDone: done.complete,
    );

    source.add([1]);
    source.addError(StateError('recoverable'));
    source.add([2]);
    await source.close();
    await done.future;

    expect(output, [1, 2]);
    expect(errors, hasLength(1));
  });

  test('restart never aliases the body of an older request', () async {
    final writer = WriterIsolate(
      const InterceptlySettings(bodyOffloadThreshold: 1),
    );
    addTearDown(writer.dispose);
    await writer.start(tempDirPath: dir.path, fileName: 'restart.tmp');

    RawCapture capture(String id, String body) => RawCapture(
          id: id,
          method: 'GET',
          url: 'https://example.com/$id',
          statusCode: 200,
          durationMs: 1,
          timestamp: DateTime.now(),
          requestHeaders: const {},
          responseHeaders: const {},
          responseBodyBytes: RawCapture.wrapBytes(
            Uint8List.fromList(utf8.encode(body)),
          ),
        );

    final beforeFuture = writer.results.first;
    writer.send(capture('A', 'AAAA'));
    final before = await beforeFuture;

    await writer.restart(tempDirPath: dir.path, fileName: 'restart.tmp');

    final afterFuture = writer.results.first;
    writer.send(capture('B', 'BBBB'));
    final after = await afterFuture;

    expect(before.fileRotationCount, after.fileRotationCount);
    final rawA = await BodyStore.readBytes(
      '${dir.path}/restart.tmp',
      before.fileOffset!,
      before.fileLength!,
    );
    final rawB = await BodyStore.readBytes(
      '${dir.path}/restart.tmp',
      after.fileOffset!,
      after.fileLength!,
    );
    expect(BodyDecodeService.unpackToText(rawA).$2, 'AAAA');
    expect(BodyDecodeService.unpackToText(rawB).$2, 'BBBB');
  });

  test('MCP can read beyond UI preview budget', () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(maxUiPreviewBytes: 8),
    );
    addTearDown(engine.dispose);
    engine.recordEntryForTesting(
      IndexEntry(
        id: 'body',
        method: 'GET',
        url: 'https://example.com',
        statusCode: 200,
        durationMs: 1,
        timestamp: DateTime.now(),
        hasError: false,
        requestSizeBytes: 16,
        responseSizeBytes: 16,
        bodyLocation: BodyLocation.memory,
        inlineRequestBody: Uint8List.fromList(utf8.encode('0123456789abcdef')),
        inlineResponseBody: Uint8List.fromList(utf8.encode('abcdefghijklmnop')),
        requestTruncation: const BodyTruncation.complete(16),
        responseTruncation: const BodyTruncation.complete(16),
      ),
    );

    final result = await HttpExtensionHandlers.handleGetRequestDetail(
      engine: engine,
      parameters: {
        'id': 'body',
        'part': 'response_body',
        'offset': '8',
        'max_chars': '8',
      },
    );
    expect(result['responseBody'], 'ijklmnop');
    expect(result['totalChars'], 16);
    expect(result['remainingChars'], 0);
    expect(result['isTruncated'], isFalse);

    final reqResult = await HttpExtensionHandlers.handleGetRequestDetail(
      engine: engine,
      parameters: {
        'id': 'body',
        'part': 'request_body',
        'offset': '8',
        'max_chars': '8',
      },
    );
    expect(reqResult['requestBody'], '89abcdef');
    expect(reqResult['totalChars'], 16);
  });

  test('active realtime session keeps recording after clear and eviction',
      () async {
    final engine = InterceptlyEngine(
      settings: InterceptlySettings(
        persistToDisk: false,
        maxEntries: 2,
        shouldCapture: (_) => true,
      ),
    );
    addTearDown(engine.dispose);
    final collector = DefaultRealtimeTrafficCollector(engine: engine);
    final scope = collector.openSession(uri: Uri.parse('wss://example.com'));
    addTearDown(scope.close);

    scope.receive('before');
    await engine.clearRealtime();
    scope.receive('after');

    expect(
      engine.getRealtimeFrames(scope.sessionId).map((f) => f.textPayload),
      ['after'],
    );
    expect(engine.byId(scope.sessionId), isNotNull);

    // Evict the realtime session entry from MemoryIndex by inserting 3 HTTP entries
    for (var i = 0; i < 3; i++) {
      engine.recordPending(
        id: 'http_$i',
        method: 'GET',
        url: 'https://example.com/$i',
        timestamp: DateTime.now(),
      );
    }
    expect(engine.byId(scope.sessionId), isNull);

    scope.receive('after_eviction');
    expect(
      engine.getRealtimeFrames(scope.sessionId).map((f) => f.textPayload),
      ['after', 'after_eviction'],
    );
    expect(engine.byId(scope.sessionId), isNotNull);
  });

  test('HTTP completing or failing after clear does not resurrect a request',
      () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    final collector = DefaultHttpTrafficCollector(engine: engine);
    final scope1 = await collector.begin(
      method: 'GET',
      uri: Uri.parse('https://example.com/1'),
    );
    final scope2 = await collector.begin(
      method: 'POST',
      uri: Uri.parse('https://example.com/2'),
    );

    await engine.clear();

    await scope1.complete(statusCode: 200, bodyBytes: Uint8List.fromList([65]));
    scope2.fail(StateError('aborted'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(engine.entries, isEmpty);
  });

  test('RealtimeStore evicts session counts and notifiers within maxSessions',
      () {
    final store = RealtimeStore(
      maxFramesPerSession: 10,
      maxTotalRealtimeFrames: 100,
      maxSessions: 3,
      onThrottledBatch: () {},
    );
    addTearDown(store.dispose);

    // Keep one active listener on session 0 to verify safe disposal handling
    final session0Notifier = store.getFrameCountsNotifier('s_0');
    void dummyListener() {}
    session0Notifier.addListener(dummyListener);

    for (var i = 0; i < 10; i++) {
      final sessionId = 's_$i';
      store.getFrameCountsNotifier(sessionId);
      store.recordFrameSync(
        RealtimeFrame(
          id: 'f_$i',
          sessionId: sessionId,
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'msg_$i',
        ),
      );
      store.markSessionClosed(sessionId);
    }

    expect(store.trackedCountsSessionCount, lessThanOrEqualTo(3));
    expect(store.trackedNotifierSessionCount, lessThanOrEqualTo(3));

    // Removing the listener after session_0 was evicted must not throw
    expect(
        () => session0Notifier.removeListener(dummyListener), returnsNormally);
  });

  test('SearchService offloads large in-memory bodies and matches accurately',
      () async {
    final largePrefix = 'x' * (BodyDecodeService.computeThreshold + 1024);
    final largeBody = '$largePrefix{"token":"NeedlesInMemory_42"}';
    final entry = IndexEntry(
      id: 'large_mem',
      method: 'POST',
      url: 'https://example.com/memory',
      statusCode: 200,
      durationMs: 12,
      timestamp: DateTime.now(),
      hasError: false,
      requestSizeBytes: 0,
      responseSizeBytes: largeBody.length,
      bodyLocation: BodyLocation.memory,
      inlineResponseBody: Uint8List.fromList(utf8.encode(largeBody)),
      responseContentType: 'application/json',
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: BodyTruncation.complete(largeBody.length),
    );

    final matched = await SearchService.matchInlineBodyAsync(
      entry,
      'needlesinmemory_42',
    );
    expect(matched, isTrue);

    final results = await SearchService.search(
      entries: [entry],
      query: 'NEEDLESINMEMORY_42',
      searchBody: true,
    );
    expect(results, hasLength(1));
    expect(results.first.summary.id, 'large_mem');
    expect(results.first.matchScopes, contains(SearchMatchScope.body));
  });
}
