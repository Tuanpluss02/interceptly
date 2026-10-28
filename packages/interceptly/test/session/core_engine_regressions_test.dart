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
import 'package:interceptly/src/engine/bounded_event_queue.dart';
import 'package:interceptly/src/engine/capture_pipeline.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/engine/realtime_store.dart';
import 'package:interceptly/src/engine/search_service.dart';
import 'package:interceptly/src/engine/writer_isolate.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/service_extension/http_extension_handlers.dart';
import 'package:interceptly/src/ui/search/master_search_controller.dart';

/// Polls [condition] every 10ms until true or [timeout] expires.
Future<void> pollUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('pollUntil timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

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

  test(
      'restart before IndexEntry is confirmed on main isolate preserves rotation and never aliases bodies',
      () async {
    final writer = WriterIsolate(
      const InterceptlySettings(bodyOffloadThreshold: 1),
    );
    addTearDown(writer.dispose);
    // 12 bytes = exact packed length of a 4-byte response body ('0000' or 'AAAA').
    await writer.start(
      tempDirPath: dir.path,
      fileName: 'restart_rot.tmp',
      maxFileBytes: 12,
    );

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

    // Fill initial file at rotation 0.
    final warmupFuture = writer.results.first;
    writer.send(capture('0', '0000'));
    final warmup = await warmupFuture;
    expect(warmup.fileRotationCount, 0);

    // Send A ('AAAA') which triggers file rotation to 1 in the writer isolate,
    // and immediately call restart BEFORE awaiting A's IndexEntry!
    final entries = <IndexEntry>[];
    final sub = writer.results.listen(entries.add);
    addTearDown(sub.cancel);

    writer.send(capture('A', 'AAAA'));
    // Spin synchronously until the background isolate has rotated the file on
    // disk and written 'AAAA', before the main isolate event loop can deliver
    // A's IndexEntry over ReceivePort.
    final tempFile = File('${dir.path}/restart_rot.tmp');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (tempFile.existsSync()) {
          final bytes = tempFile.readAsBytesSync();
          if (utf8.decode(bytes, allowMalformed: true).contains('AAAA')) {
            break;
          }
        }
      } catch (_) {}
    }

    await writer.restart(
      tempDirPath: dir.path,
      fileName: 'restart_rot.tmp',
      maxFileBytes: 24,
    );

    writer.send(capture('B', 'BBBB'));
    final waitDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (entries.length < 2) {
      if (DateTime.now().isAfter(waitDeadline)) {
        fail('timed out waiting for 2 entries, got ${entries.length}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final before = entries.firstWhere((e) => e.id == 'A');
    final after = entries.firstWhere((e) => e.id == 'B');

    expect(before.fileRotationCount, 1);
    expect(after.fileRotationCount, 1);
    final rawA = await BodyStore.readBytes(
      '${dir.path}/restart_rot.tmp',
      before.fileOffset!,
      before.fileLength!,
    );
    final rawB = await BodyStore.readBytes(
      '${dir.path}/restart_rot.tmp',
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
      settings: const InterceptlySettings(
        persistToDisk: false,
        maxEntries: 1,
      ),
    );
    addTearDown(engine.dispose);
    await engine.initialize();

    final collector = DefaultHttpTrafficCollector(engine: engine);
    final scope1 = await collector.begin(
      method: 'GET',
      uri: Uri.parse('https://example.com/1'),
    );
    scope1.amendRequest(headers: const {'x-amended': 'true'});
    final scope2 = await collector.begin(
      method: 'POST',
      uri: Uri.parse('https://example.com/2'),
    );

    // Exceed _pendingGenerations capacity (maxEntries * 4 = 4) so that
    // Expando generation on the amended HttpRequestContext is exercised.
    for (var i = 0; i < 4; i++) {
      final s = await collector.begin(
        method: 'GET',
        uri: Uri.parse('https://example.com/extra_$i'),
      );
      await s.complete(statusCode: 200);
    }

    await engine.clear();

    await scope1.complete(statusCode: 200, bodyBytes: Uint8List.fromList([65]));
    scope2.fail(StateError('aborted'));
    final holdClear = DateTime.now().add(const Duration(milliseconds: 500));
    while (DateTime.now().isBefore(holdClear)) {
      expect(engine.entries, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pollUntil(() => engine.entries.isEmpty);
  });

  test(
      'RealtimeStore evicts session counts and notifiers within maxSessions while keeping active listeners live',
      () async {
    final store = RealtimeStore(
      maxFramesPerSession: 10,
      maxTotalRealtimeFrames: 100,
      maxSessions: 2,
      onThrottledBatch: () {},
    );
    addTearDown(store.dispose);

    // Attach an active listener to s_0
    final session0Notifier = store.getFrameCountsNotifier('s_0');
    var listenerUpdates = 0;
    void activeListener() {
      listenerUpdates++;
    }

    session0Notifier.addListener(activeListener);

    store.recordFrameSync(
      RealtimeFrame(
        id: 'f_0_1',
        sessionId: 's_0',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: 'first',
      ),
    );
    await pollUntil(() => session0Notifier.value.total == 1);
    expect(session0Notifier.value.total, 1);

    // Exceed maxSessions with other sessions and notifiers
    for (var i = 1; i < 6; i++) {
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

    // Recording a second frame on s_0 must still update the existing notifier to 2
    store.recordFrameSync(
      RealtimeFrame(
        id: 'f_0_2',
        sessionId: 's_0',
        direction: FrameDirection.incoming,
        type: FrameType.text,
        textPayload: 'second',
      ),
    );
    await pollUntil(() => session0Notifier.value.total == 2);
    expect(session0Notifier.value.total, 2);
    expect(listenerUpdates, greaterThanOrEqualTo(2));

    // Once the listener is removed and s_0 is evicted, counts/notifiers stay bounded
    expect(
        () => session0Notifier.removeListener(activeListener), returnsNormally);
    expect(store.trackedCountsSessionCount, lessThanOrEqualTo(2));
    expect(store.trackedNotifierSessionCount, lessThanOrEqualTo(2));
  });

  test(
      'MasterSearchController async inline body search does not resurrect pruned entries or overwrite newer versions',
      () async {
    final search = MasterSearchController();
    addTearDown(search.dispose);

    await search.start(
      query: 'needle_token',
      allEntries: const [],
      filePath: null,
    );

    final largePrefix = 'x' * (BodyDecodeService.computeThreshold + 1024);
    final matchingBody =
        Uint8List.fromList(utf8.encode('$largePrefix needle_token'));
    final nonMatchingBody =
        Uint8List.fromList(utf8.encode('$largePrefix nothing_here'));

    IndexEntry buildEntry(String id, Uint8List body, {int statusCode = 200}) =>
        IndexEntry(
          id: id,
          method: 'POST',
          url: 'https://example.com/$id',
          statusCode: statusCode,
          durationMs: 10,
          timestamp: DateTime.now(),
          hasError: false,
          requestSizeBytes: 0,
          responseSizeBytes: body.length,
          bodyLocation: BodyLocation.memory,
          inlineResponseBody: body,
          responseContentType: 'text/plain',
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: BodyTruncation.complete(body.length),
        );

    // 1. Pruned entry while async body check is in flight must not resurrect
    search.updateOrAddEntry(buildEntry('pruned_req', matchingBody));
    expect(search.pendingAsyncEntryCount, 1);
    search.pruneMissing(const <String>{});
    expect(search.pendingAsyncEntryCount, 0);

    // 2. Newer version of an entry must not be overwritten by stale async body check
    search.updateOrAddEntry(
      buildEntry('updated_req', matchingBody, statusCode: 200),
    );
    search.updateOrAddEntry(
      buildEntry('updated_req', nonMatchingBody, statusCode: 201),
    );

    await pollUntil(() => search.pendingAsyncEntryCount == 0);

    expect(search.results, isEmpty);
    expect(search.pendingAsyncEntryCount, 0);
  });

  test(
      'SearchService preserves Unicode case-folding semantics (e.g. Kelvin sign K matches k)',
      () async {
    final entry = IndexEntry(
      id: 'unicode_kelvin',
      method: 'GET',
      url: 'https://example.com/temp',
      statusCode: 200,
      durationMs: 5,
      timestamp: DateTime.now(),
      hasError: false,
      requestSizeBytes: 0,
      responseSizeBytes: 10,
      bodyLocation: BodyLocation.memory,
      inlineResponseBody: Uint8List.fromList(utf8.encode('300\u212A')),
      responseContentType: 'text/plain',
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(6),
    );

    expect(SearchService.matchInlineBody(entry, 'k'), isTrue);
    expect(await SearchService.matchInlineBodyAsync(entry, 'k'), isTrue);
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

  test('concurrent clear and clearRealtime resolve correct scopes', () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    engine.recordPending(
      id: 'rest-1',
      method: 'GET',
      url: 'https://example.com/1',
      timestamp: DateTime.now(),
    );
    engine.recordRealtimeConnection(
      id: 'rt-1',
      url: 'wss://example.com',
    );
    expect(engine.byId('rest-1'), isNotNull);
    expect(engine.byId('rt-1'), isNotNull);
    final f1 = engine.clear();
    final f2 = engine.clearRealtime();
    expect(identical(f1, f2), isFalse);
    await Future.wait([f1, f2]);
    expect(engine.entries, isEmpty);
  });

  test('clearRest preserves realtime and clearRealtime preserves rest',
      () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    engine.recordPending(
      id: 'rest-1',
      method: 'GET',
      url: 'https://example.com/1',
      timestamp: DateTime.now(),
    );
    final rtHeaders = <String, String>{'x-rt': '1'};
    engine.recordRealtimeConnection(
      id: 'rt-1',
      url: 'wss://example.com',
      headers: rtHeaders,
    );
    rtHeaders['x-rt'] = 'mutated';
    expect(engine.byId('rt-1')?.requestHeaders['x-rt'], '1');
    await engine.clearRest();
    expect(engine.byId('rest-1'), isNull);
    expect(engine.byId('rt-1'), isNotNull);
    engine.recordPending(
      id: 'rest-2',
      method: 'GET',
      url: 'https://example.com/2',
      timestamp: DateTime.now(),
    );
    await engine.clearRealtime();
    expect(engine.byId('rt-1'), isNull);
    expect(engine.byId('rest-2'), isNotNull);
  });

  test('same-scope clear coalesces to identical future', () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    final a = engine.clear();
    final b = engine.clear();
    expect(identical(a, b), isTrue);
    await Future.wait([a, b]);
    final c = engine.clearRest();
    final d = engine.clearRest();
    expect(identical(c, d), isTrue);
    await Future.wait([c, d]);
  });

  test('resetFile failure does not falsely invalidate offsets', () async {
    final store = BodyStore();
    addTearDown(store.dispose);
    final fileAsDir = File('${dir.path}/not-a-dir');
    await fileAsDir.writeAsBytes([1, 2, 3]);
    await store.resetFile(fileAsDir.path, fileName: 'x.tmp');
    expect(store.rotationCount, 0);
    expect(store.currentOffset, 0);
    await store.initForWrite(dir.path, fileName: 'rot_ok.tmp');
    await store.append(Uint8List.fromList([1, 2, 3]));
    await store.rotate();
    expect(store.rotationCount, 1);
    expect(store.currentOffset, 0);
  });

  test('resetFile returns false and keeps rotation', () async {
    final store = BodyStore();
    addTearDown(store.dispose);
    final fileAsDir = File('${dir.path}/not-a-dir-bool');
    await fileAsDir.writeAsBytes([1, 2, 3]);
    final ok = await store.resetFile(fileAsDir.path, fileName: 'x.tmp');
    expect(ok, isFalse);
    expect(store.rotationCount, 0);
  });

  test('rotate failure returns false and keeps rotation', () async {
    final store = BodyStore();
    addTearDown(store.dispose);
    final ok = await store.rotate();
    expect(ok, isFalse);
    expect(store.rotationCount, 0);
    expect(store.currentOffset, 0);
  });

  test('restart queue bounded delivers at most maxQueuedEvents', () async {
    RawCapture cap(String id) => RawCapture(
          id: id,
          method: 'GET',
          url: 'https://example.com/$id',
          statusCode: 200,
          durationMs: 1,
          timestamp: DateTime.now(),
          requestHeaders: const {},
          responseHeaders: const {},
          responseBodyBytes: RawCapture.wrapBytes(
            Uint8List.fromList(utf8.encode('x')),
          ),
        );
    final writer = WriterIsolate(
      const InterceptlySettings(
        maxQueuedEvents: 5,
        bodyOffloadThreshold: 1000000,
      ),
    );
    addTearDown(() async {
      try {
        await writer.dispose();
      } catch (_) {}
    });
    await writer.start(
      tempDirPath: dir.path,
      fileName: 'restart_bound.tmp',
    );
    final delivered = <IndexEntry>[];
    final sub = writer.results.listen(delivered.add);
    addTearDown(sub.cancel);
    final restarting = writer.restart(
      tempDirPath: dir.path,
      fileName: 'restart_bound.tmp',
    );
    for (var i = 0; i < 20; i++) {
      writer.send(cap('q-$i'));
    }
    await restarting;
    await pollUntil(() => delivered.length == 5);
    expect(delivered.length, lessThanOrEqualTo(5));
    await writer.dispose();
  });

  test('dispose during restart kills just-started isolate', () async {
    final writer = WriterIsolate(const InterceptlySettings());
    addTearDown(() async {
      try {
        await writer.dispose();
      } catch (_) {}
    });
    await writer.start(tempDirPath: dir.path, fileName: 'd1.tmp');
    final r = writer.restart(tempDirPath: dir.path, fileName: 'd1.tmp');
    await writer.dispose();
    await r;
    expect(writer.isReady, isFalse);
    await writer.clear().timeout(const Duration(seconds: 5));
  });

  test('clear no-ops after dispose', () async {
    final writer = WriterIsolate(const InterceptlySettings());
    addTearDown(() async {
      try {
        await writer.dispose();
      } catch (_) {}
    });
    await writer.start(tempDirPath: dir.path, fileName: 'd1clear.tmp');
    await writer.dispose();
    expect(writer.isReady, isFalse);
    await writer.clear().timeout(const Duration(seconds: 5));
  });

  test('dispose clears pending async state', () async {
    final search = MasterSearchController();
    addTearDown(() {
      try {
        search.dispose();
      } catch (_) {}
    });
    await search.start(
      query: 'needle_token',
      allEntries: const [],
      filePath: null,
    );
    final largePrefix = 'x' * (BodyDecodeService.computeThreshold + 1024);
    final body = Uint8List.fromList(utf8.encode('$largePrefix needle_token'));
    final entry = IndexEntry(
      id: 'dispose_pending',
      method: 'POST',
      url: 'https://example.com/dispose_pending',
      statusCode: 200,
      durationMs: 10,
      timestamp: DateTime.now(),
      hasError: false,
      requestSizeBytes: 0,
      responseSizeBytes: body.length,
      bodyLocation: BodyLocation.memory,
      inlineResponseBody: body,
      responseContentType: 'text/plain',
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: BodyTruncation.complete(body.length),
    );
    search.updateOrAddEntry(entry);
    expect(search.pendingAsyncEntryCount, 1);
    search.dispose();
    expect(search.pendingAsyncEntryCount, 0);
  });

  test('stale generation capture does not resurrect after clear', () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(engine.dispose);
    await engine.initialize();
    final cap = RawCapture(
      id: 'stale-1',
      method: 'GET',
      url: 'https://example.com/stale',
      statusCode: 200,
      durationMs: 1,
      timestamp: DateTime.now(),
      requestHeaders: const {},
      responseHeaders: const {},
    );
    engine.record(cap);
    await engine.clear();
    engine.record(cap);
    final holdUntil = DateTime.now().add(const Duration(milliseconds: 500));
    while (DateTime.now().isBefore(holdUntil)) {
      expect(engine.entries.where((e) => e.id == 'stale-1'), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await pollUntil(
        () => engine.entries.where((e) => e.id == 'stale-1').isEmpty);
  });

  test('orphan notifier eviction keeps counts bounded', () async {
    final store = RealtimeStore(
      maxFramesPerSession: 2,
      maxTotalRealtimeFrames: 100,
      maxSessions: 2,
      onThrottledBatch: () {},
    );
    addTearDown(store.dispose);
    for (var i = 0; i < 5; i++) {
      final sid = 'o_$i';
      store.getFrameCountsNotifier(sid);
      store.recordFrameSync(
        RealtimeFrame(
          id: 'f_$i',
          sessionId: sid,
          direction: FrameDirection.incoming,
          type: FrameType.text,
          textPayload: 'hi',
        ),
      );
      store.markSessionClosed(sid);
    }
    store.getFrameCountsNotifier('o_new');
    expect(store.trackedNotifierSessionCount, lessThanOrEqualTo(2));
    expect(store.trackedCountsSessionCount, lessThanOrEqualTo(2));
  });

  test('part all applies offset window per body', () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(maxUiPreviewBytes: 8),
    );
    addTearDown(engine.dispose);
    engine.recordEntryForTesting(
      IndexEntry(
        id: 'body2',
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
    final res = await HttpExtensionHandlers.handleGetRequestDetail(
      engine: engine,
      parameters: {
        'id': 'body2',
        'part': 'all',
        'offset': '10',
        'max_chars': '8',
      },
    );
    expect(res['requestBody'], 'abcdef');
    expect(res['responseBody'], 'klmnop');
    expect(res['totalChars'], 32);
    expect(res['remainingChars'], 0);
  });

  test('catchError preserves newer same-id pending', () async {
    final search = MasterSearchController();
    addTearDown(search.dispose);
    addTearDown(() {
      SearchService.matchInlineBodyAsyncOverride = null;
    });
    SearchService.matchInlineBodyAsyncOverride =
        (IndexEntry entry, String queryLower) async {
      final text = utf8.decode(
        entry.inlineResponseBody ?? Uint8List(0),
        allowMalformed: true,
      );
      if (text.contains('trigger_error')) {
        throw StateError('forced async match failure');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return text.toLowerCase().contains(queryLower);
    };
    await search.start(
        query: 'needle_token', allEntries: const [], filePath: null);
    IndexEntry build(String id, Uint8List body) => IndexEntry(
          id: id,
          method: 'POST',
          url: 'https://example.com/$id',
          statusCode: 200,
          durationMs: 10,
          timestamp: DateTime.now(),
          hasError: false,
          requestSizeBytes: 0,
          responseSizeBytes: body.length,
          bodyLocation: BodyLocation.memory,
          inlineResponseBody: body,
          responseContentType: 'text/plain',
          requestTruncation: const BodyTruncation.complete(0),
          responseTruncation: BodyTruncation.complete(body.length),
        );
    final failBody = Uint8List.fromList(utf8.encode(
        '${'x' * (BodyDecodeService.computeThreshold + 16)} trigger_error'));
    final okBody = Uint8List.fromList(utf8.encode(
        '${'x' * (BodyDecodeService.computeThreshold + 16)} needle_token'));
    search.updateOrAddEntry(build('same_id', failBody));
    search.updateOrAddEntry(build('same_id', okBody));
    await pollUntil(() =>
        search.pendingAsyncEntryCount == 0 &&
        (search.results?.map((e) => e.id).contains('same_id') ?? false));
    expect(search.results?.map((e) => e.id), contains('same_id'));
    expect(search.pendingAsyncEntryCount, 0);
  });

  test('in-place refresh notifies and reconciles scopes', () async {
    final search = MasterSearchController();
    addTearDown(search.dispose);
    var notifies = 0;
    search.addListener(() => notifies++);
    await search.start(
        query: 'needle_token', allEntries: const [], filePath: null);
    search.updateOrAddEntry(matchingEntry('r1'));
    final before = notifies;
    search.updateOrAddEntry(newerVersion('r1'));
    expect(notifies, greaterThan(before));
    expect(search.getScopes('r1'), isNotEmpty);
  });

  test('respawn queue drops are counted', () async {
    RawCapture cap(String id) => RawCapture(
          id: id,
          method: 'GET',
          url: 'https://example.com/$id',
          statusCode: 200,
          durationMs: 1,
          timestamp: DateTime.now(),
          requestHeaders: const {},
          responseHeaders: const {},
        );
    final pipeline = CapturePipeline(
      settings: const InterceptlySettings(maxQueuedEvents: 2),
      sessionId: 'd',
      onEntryReady: (_) {},
    );
    addTearDown(pipeline.dispose);
    expect(pipeline.droppedCount, 0);

    final queue = BoundedEventQueue<RawCapture>(maxSize: 2);
    for (var i = 0; i < 5; i++) {
      queue.add(cap('q-$i'));
    }
    expect(queue.droppedCount, 3);
    queue.resetDroppedCount();
    expect(queue.droppedCount, 0);
    expect(queue.length, 2);

    for (var i = 0; i < 5; i++) {
      pipeline.record(cap('p-$i'));
    }
    await pipeline.initialize();
    expect(pipeline.droppedCount, 3);
  });

  test('manual pause survives configure and gates every capture path',
      () async {
    final engine = InterceptlyEngine(
      settings: const InterceptlySettings(persistToDisk: false),
    );
    addTearDown(() async {
      try {
        await engine.dispose();
      } catch (_) {}
    });
    await engine.initialize();

    engine.disable();
    engine.configure(
      const InterceptlySettings(persistToDisk: false, maxEntries: 10),
    );
    expect(engine.isEnabled, isFalse);

    engine.recordPending(
      id: 'paused-rest',
      method: 'GET',
      url: 'https://example.com/paused-rest',
      timestamp: DateTime.now(),
    );
    engine.recordRealtimeConnection(
      id: 'paused-realtime',
      url: 'wss://example.com/socket',
    );
    engine.record(
      RawCapture(
        id: 'paused-terminal',
        method: 'GET',
        url: 'https://example.com/paused-terminal',
        statusCode: 200,
        durationMs: 5,
        timestamp: DateTime.now(),
        requestHeaders: const {},
        responseHeaders: const {},
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(engine.entries, isEmpty);
    expect(engine.byId('paused-rest'), isNull);
    expect(engine.byId('paused-realtime'), isNull);
    expect(engine.byId('paused-terminal'), isNull);

    engine.enable();
    expect(engine.isEnabled, isTrue);
    engine.recordPending(
      id: 'resumed-rest',
      method: 'GET',
      url: 'https://example.com/resumed-rest',
      timestamp: DateTime.now(),
    );
    expect(engine.byId('resumed-rest'), isNotNull);
  });
}

IndexEntry matchingEntry(String id) => IndexEntry(
      id: id,
      method: 'GET',
      url: 'https://example.com/needle_token/$id',
      statusCode: 200,
      durationMs: 10,
      timestamp: DateTime.now(),
      hasError: false,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      bodyLocation: BodyLocation.memory,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
    );

IndexEntry newerVersion(String id) => IndexEntry(
      id: id,
      method: 'GET',
      url: 'https://example.com/needle_token/$id',
      statusCode: 201,
      durationMs: 20,
      timestamp: DateTime.now(),
      hasError: false,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      bodyLocation: BodyLocation.memory,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
    );
