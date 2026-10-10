import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';

class _CapturingChain<BodyType> implements Chain<BodyType> {
  _CapturingChain(this.request, this.handler);

  @override
  final Request request;
  final FutureOr<Response<BodyType>> Function(Request request) handler;
  Request? proceededRequest;

  @override
  FutureOr<Response<BodyType>> proceed(Request request) {
    proceededRequest = request;
    return handler(request);
  }
}

class _MockStreamingClient extends http.BaseClient {
  _MockStreamingClient(this.handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return await handler(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('challenger_m2_instance2_test');
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
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<IndexEntry?> waitForTerminalEntry(
    String id, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final entry = session.entries.cast<IndexEntry?>().firstWhere(
            (e) => e?.id == id,
            orElse: () => null,
          );
      if (entry != null && (entry.statusCode != 0 || entry.hasError)) {
        return entry;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return null;
  }

  group('Challenger M2 Instance 2 - Chopper Interceptor Adversarial Tests', () {
    test(
        'Burst invocation: 100 rapid requests with diverse methods, bodies, and parameters',
        () async {
      final interceptor = InterceptlyChopperInterceptor(session);
      final methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD'];
      final futures = <Future<void>>[];
      final proceededParams = <int, Map<String, dynamic>>{};

      for (var i = 0; i < 100; i++) {
        final idx = i;
        final method = methods[idx % methods.length];
        final initialParams = <String, dynamic>{
          'index': '$idx',
          'method': method,
          'token': 'tok_$idx',
          'nested_key': 'val_${idx * 2}',
        };

        dynamic body;
        if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
          if (idx % 2 == 0) {
            body = '{"name":"item_$idx","value":$idx}';
          } else {
            body = Uint8List.fromList([idx, idx + 1, idx + 2]);
          }
        }

        final req = Request(
          method,
          Uri.parse('https://api.example.com/burst/$idx'),
          Uri.parse('https://api.example.com'),
          parameters: Map<String, dynamic>.from(initialParams),
          body: body,
          headers: {'x-request-num': '$idx'},
        );

        final chain = _CapturingChain<dynamic>(
          req,
          (r) async {
            // Minimal async yield to simulate network micro-delay
            if (idx % 5 == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            return Response(
              http.Response(
                '{"result":"ok_$idx"}',
                200,
                request: http.Request(r.method, r.url),
                headers: {'content-type': 'application/json'},
              ),
              '{"result":"ok_$idx"}',
            );
          },
        );

        futures.add(() async {
          final res = await interceptor.intercept(chain);
          expect(res.statusCode, 200);
          proceededParams[idx] = chain.proceededRequest!.parameters;
        }());
      }

      await Future.wait(futures);

      // Verify outbound parameter purity for ALL 100 requests
      expect(proceededParams.length, 100);
      for (var i = 0; i < 100; i++) {
        final params = proceededParams[i]!;
        expect(params['index'], '$i');
        expect(params.containsKey('interceptly_started_at'), isFalse,
            reason: 'Leaked interceptly_started_at in request $i');
        expect(params.containsKey('interceptly_request_id'), isFalse,
            reason: 'Leaked interceptly_request_id in request $i');
      }

      // Wait for all 100 requests to be processed in InspectorSession
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (session.entries.where((e) => e.statusCode != 0).length < 100) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 100);
      final uniqueIds = session.entries.map((e) => e.id).toSet();
      expect(uniqueIds.length, 100, reason: 'All request IDs must be distinct');
      for (final entry in session.entries) {
        expect(entry.url, isNot(contains('interceptly_started_at')));
        expect(entry.url, isNot(contains('interceptly_request_id')));
        expect(entry.statusCode, 200);
        expect(entry.hasError, isFalse);
      }
    });

    test(
        'Exception matrix: rethrows synchronous and asynchronous transport exceptions without leaking state',
        () async {
      final interceptor = InterceptlyChopperInterceptor(session);

      final testCases = <Map<String, dynamic>>[
        {
          'url': 'https://api.example.com/socket-err',
          'error': const SocketException('Connection refused'),
          'matcher': isA<SocketException>(),
          'expectedErrorType': 'SocketException',
        },
        {
          'url': 'https://api.example.com/http-err',
          'error': const HttpException('Connection closed prematurely'),
          'matcher': isA<HttpException>(),
          'expectedErrorType': 'HttpException',
        },
        {
          'url': 'https://api.example.com/client-err',
          'error': http.ClientException('Client timeout occurred'),
          'matcher': isA<http.ClientException>(),
          'expectedErrorType': 'ClientException',
        },
        {
          'url': 'https://api.example.com/state-err',
          'error': StateError('Bad state in downstream interceptor'),
          'matcher': isA<StateError>(),
          'expectedErrorType': 'StateError',
        },
        {
          'url': 'https://api.example.com/async-timeout-err',
          'error': TimeoutException('Asynchronous timeout'),
          'matcher': isA<TimeoutException>(),
          'async': true,
          'expectedErrorType': 'TimeoutException',
        },
      ];

      for (final tc in testCases) {
        final req = Request(
          'GET',
          Uri.parse(tc['url'] as String),
          Uri.parse('https://api.example.com'),
          parameters: {'scope': 'test'},
        );

        final chain = _CapturingChain<String>(
          req,
          (_) async {
            if (tc['async'] == true) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            throw tc['error'] as Object;
          },
        );

        await expectLater(
          () => interceptor.intercept(chain),
          throwsA(tc['matcher']),
        );

        expect(chain.proceededRequest!.parameters, equals({'scope': 'test'}));
        expect(
          chain.proceededRequest!.parameters
              .containsKey('interceptly_started_at'),
          isFalse,
        );

        // Find session entry for this test case
        final url = tc['url'] as String;
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        IndexEntry? matched;
        while (DateTime.now().isBefore(deadline)) {
          matched = session.entries.cast<IndexEntry?>().firstWhere(
                (e) => e != null && e.url.contains(url) && e.hasError,
                orElse: () => null,
              );
          if (matched != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        if (matched == null) {
          // ignore: avoid_print
          print(
              'DEBUG tc url: $url, session entries: ${session.entries.map((e) => 'id:${e.id} url:${e.url} err:${e.hasError} type:${e.errorType} status:${e.statusCode}').toList()}');
        }

        expect(matched, isNotNull, reason: 'Failed to record error for $url');
        expect(matched!.hasError, isTrue);
        expect(matched.errorType, contains(tc['expectedErrorType'] as String));
        expect(matched.statusCode, 0);
      }
    });

    test(
        'Chopper HTTP error codes (400, 401, 403, 404, 500, 502, 503) record ChopperError and preserve status code',
        () async {
      final interceptor = InterceptlyChopperInterceptor(session);
      final errorStatuses = [400, 401, 403, 404, 500, 502, 503];

      for (final code in errorStatuses) {
        final req = Request(
          'GET',
          Uri.parse('https://api.example.com/status/$code'),
          Uri.parse('https://api.example.com'),
          parameters: {'code': '$code'},
        );

        final chain = _CapturingChain<String>(
          req,
          (r) => Response(
            http.Response(
              '{"error":"fail_$code"}',
              code,
              request: http.Request('GET', r.url),
            ),
            '{"error":"fail_$code"}',
            error: 'HTTP $code Error',
          ),
        );

        final response = await interceptor.intercept(chain);
        expect(response.statusCode, code);
        expect(response.isSuccessful, isFalse);
        expect(chain.proceededRequest!.parameters, equals({'code': '$code'}));

        // Wait for session entry
        final urlPart = '/status/$code';
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        IndexEntry? entry;
        while (DateTime.now().isBefore(deadline)) {
          entry = session.entries.cast<IndexEntry?>().firstWhere(
                (e) =>
                    e != null &&
                    e.url.contains(urlPart) &&
                    e.statusCode == code,
                orElse: () => null,
              );
          if (entry != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(entry, isNotNull);
        expect(entry!.statusCode, code);
        expect(entry.hasError, isTrue);
        expect(entry.errorType, 'ChopperError');
        expect(entry.errorMessage, contains('HTTP $code Error'));
      }
    });
  });

  group(
      'Challenger M2 Instance 2 - HTTP Client Stream Teeing Adversarial Stress Tests',
      () {
    test(
        'Cancel after 0 bytes: cancel subscription before any data chunk emitted',
        () async {
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/zero-bytes')),
      );

      // Verify pending entry created
      expect(session.entries.length, 1);
      final entryId = session.entries.first.id;
      expect(session.entries.first.statusCode, 0);

      // Listen and CANCEL immediately without source emitting anything
      final sub = response.stream.listen((chunk) {
        fail('No chunk should be emitted on zero-byte cancellation');
      });
      await sub.cancel();

      // Ensure source was cancelled
      expect(sourceCancelled, isTrue,
          reason: 'Source stream controller onCancel was not called');

      // Verify session entry is updated promptly to CancellationException
      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');
      expect(terminalEntry.errorMessage,
          'Stream subscription was canceled by client.');
      expect(terminalEntry.responseSizeBytes, 0);
      expect(terminalEntry.inlineResponseBody, isNull);

      await sourceController.close();
    });

    test(
        'Cancel mid-stream: stops further chunks and records partial body bytes',
        () async {
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/mid-stream')),
      );

      final entryId = session.entries.first.id;
      final receivedChunks = <List<int>>[];
      late StreamSubscription<List<int>> sub;

      final cancelCompleter = Completer<void>();
      sub = response.stream.listen(
        (chunk) async {
          receivedChunks.add(chunk);
          if (receivedChunks.length == 3) {
            // Cancel on 3rd chunk
            await sub.cancel();
            cancelCompleter.complete();
          }
        },
      );

      // Emit 6 chunks
      sourceController.add([1, 2, 3]);
      sourceController.add([4, 5, 6]);
      sourceController.add([7, 8, 9]);

      await cancelCompleter.future;

      // Source should be cancelled
      expect(sourceCancelled, isTrue);
      expect(receivedChunks.length, 3);

      // Even if more chunks are added to source controller, consumer must receive none
      sourceController.add([10, 11, 12]);
      sourceController.add([13, 14, 15]);

      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');

      // Partial body must reflect the 3 chunks captured (9 bytes)
      expect(terminalEntry.responseSizeBytes, 9);

      await sourceController.close();
    });

    test(
        'Cancel on final byte/chunk: consumer cancels on receiving the final payload chunk before onDone',
        () async {
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/final-chunk')),
      );

      final entryId = session.entries.first.id;
      final chunks = <List<int>>[];
      late StreamSubscription<List<int>> sub;
      final cancelCompleter = Completer<void>();

      sub = response.stream.listen((chunk) async {
        chunks.add(chunk);
        if (chunks.length == 2) {
          // Chunk 2 is the final chunk; client cancels before source close()
          await sub.cancel();
          cancelCompleter.complete();
        }
      });

      sourceController.add([1, 2]);
      sourceController.add([3, 4]);

      await cancelCompleter.future;
      expect(sourceCancelled, isTrue);

      // Source now closes
      await sourceController.close();

      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');
      expect(terminalEntry.responseSizeBytes, 4);
    });

    test(
        'Simultaneous read + cancel stress: 20 concurrent streams with random reads and concurrent cancellations',
        () async {
      final controllers = <int, StreamController<List<int>>>{};
      final sourceCancelled = <int, bool>{};

      final client = InterceptlyHttpClient(
        _MockStreamingClient((req) {
          final id = int.parse(req.url.pathSegments.last);
          final ctrl = StreamController<List<int>>(
            onCancel: () {
              sourceCancelled[id] = true;
            },
          );
          controllers[id] = ctrl;
          return http.StreamedResponse(ctrl.stream, 200, request: req);
        }),
        session,
      );

      final futures = <Future<void>>[];

      for (var i = 0; i < 20; i++) {
        final idx = i;
        futures.add(() async {
          final response = await client.send(
            http.Request(
                'GET', Uri.parse('https://api.example.com/simultaneous/$idx')),
          );

          final ctrl = controllers[idx]!;
          final received = <List<int>>[];

          late StreamSubscription<List<int>> sub;
          final doneCompleter = Completer<void>();

          sub = response.stream.listen(
            (c) => received.add(c),
            onDone: () {
              if (!doneCompleter.isCompleted) doneCompleter.complete();
            },
          );

          // Emit chunks concurrently with an asynchronous cancel trigger
          final cancelFuture = Future<void>.delayed(
            Duration(milliseconds: 5 + (idx % 15)),
            () async {
              if (idx % 2 == 0) {
                // Half the streams are cancelled concurrently while reading
                await sub.cancel();
                if (!doneCompleter.isCompleted) doneCompleter.complete();
              }
            },
          );

          // Emit bursts
          for (var c = 0; c < 5; c++) {
            if (!ctrl.isClosed) {
              ctrl.add([c, c + 1, c + 2]);
            }
            await Future<void>.delayed(const Duration(milliseconds: 3));
          }

          if (!ctrl.isClosed) {
            await ctrl.close();
          }

          await cancelFuture;
          await doneCompleter.future;
        }());
      }

      await Future.wait(futures);

      // Verify all 20 entries reached terminal states cleanly
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (
          session.entries.where((e) => e.statusCode != 0 || e.hasError).length <
              20) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 20);
      final cancelledEntries =
          session.entries.where((e) => e.errorType == 'CancellationException');
      final completedEntries =
          session.entries.where((e) => !e.hasError && e.statusCode == 200);

      // All 20 entries must be in a clean terminal state
      expect(cancelledEntries.length + completedEntries.length, 20);
    });

    test(
        'Slow server stream cancellation: client cancels while chunk delay is pending during network simulation throttling',
        () async {
      // Set high download throttling so each chunk incurs significant delay
      session.setNetworkSimulation(NetworkSimulationProfile.slow3G);

      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/slow-throttle-cancel')),
      );

      final entryId = session.entries.first.id;

      final sub = response.stream.listen((chunk) {});

      // Add a chunk of 300 bytes: this triggers session.throughputDelayForChunk(300) > 0
      sourceController.add(List.generate(300, (i) => i % 256));

      // Cancel while the throttle Future.delayed is active
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      expect(sourceCancelled, isTrue);

      // Verify that cancellation resolves promptly (< 1s) and does not hang
      final stopwatch = Stopwatch()..start();
      final terminalEntry = await waitForTerminalEntry(entryId);
      stopwatch.stop();

      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));

      await sourceController.close();
      // Restore simulation profile
      session.clearNetworkSimulation();
    });

    test(
        'Error preservation: server stream errors are not masked by subsequent client cancellations',
        () async {
      final sourceController = StreamController<List<int>>();
      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/error-priority')),
      );

      final entryId = session.entries.first.id;
      final errorCompleter = Completer<void>();
      late StreamSubscription<List<int>> sub;

      sub = response.stream.listen(
        (_) {},
        onError: (e) async {
          // Consumer receives the error, then calls sub.cancel()
          await sub.cancel();
          errorCompleter.complete();
        },
      );

      sourceController.addError(const SocketException('Remote host closed'));
      await sourceController.close();
      await errorCompleter.future;

      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      // Must preserve the real error (SocketException), NOT overwrite it with CancellationException!
      expect(terminalEntry.errorType, contains('SocketException'));
      expect(terminalEntry.errorMessage, contains('Remote host closed'));
    });

    test(
        'Pause and resume cycle prior to cancellation propagates cleanly to source',
        () async {
      var sourceCancelled = false;
      final sourceController = StreamController<List<int>>(
        onCancel: () {
          sourceCancelled = true;
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/pause-resume-cancel')),
      );

      final entryId = session.entries.first.id;
      final sub = response.stream.listen((_) {});

      sub.pause();
      expect(sourceController.isPaused, isTrue);

      sub.resume();
      expect(sourceController.isPaused, isFalse);

      sourceController.add([1, 2, 3]);

      sub.pause();
      expect(sourceController.isPaused, isTrue);

      // Cancel while paused
      await sub.cancel();
      expect(sourceCancelled, isTrue);

      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');

      await sourceController.close();
    });

    test('Standard Stream operators: stream.first auto-cancels cleanly',
        () async {
      final sourceController = StreamController<List<int>>();
      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/stream-first')),
      );

      final entryId = session.entries.first.id;

      // Emit multiple chunks in background
      scheduleMicrotask(() {
        sourceController.add([10, 20]);
        sourceController.add([30, 40]);
        sourceController.add([50, 60]);
      });

      // stream.first consumes the first element and cancels the stream
      final firstChunk = await response.stream.first;
      expect(firstChunk, [10, 20]);

      // CancellationException recorded cleanly
      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');

      await sourceController.close();
    });

    test(
        'Post-cancellation source events: source emits chunks after onCancel without throwing Bad state',
        () async {
      late StreamController<List<int>> sourceController;
      sourceController = StreamController<List<int>>(
        onCancel: () {
          // Downstream transport socket stubbornly emits a trailing packet
          sourceController.add([99, 100]);
        },
      );

      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request(
            'GET', Uri.parse('https://api.example.com/trailing-events')),
      );

      final entryId = session.entries.first.id;
      final sub = response.stream.listen((_) {});

      // Consumer cancels
      await sub.cancel();

      // No unhandled exceptions thrown; session entry remains CancellationException
      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isTrue);
      expect(terminalEntry.errorType, 'CancellationException');

      await sourceController.close();
    });

    test(
        'Large streaming response exceeding maxBodyBytes buffers capped size and forwards full stream',
        () async {
      final sourceController = StreamController<List<int>>();
      final client = InterceptlyHttpClient(
        _MockStreamingClient(
          (req) =>
              http.StreamedResponse(sourceController.stream, 200, request: req),
        ),
        session,
      );

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/large-stream')),
      );

      final entryId = session.entries.first.id;
      final maxBytes = session.settings.maxBodyBytes;

      // Stream exceeds maxBodyBytes
      final totalStreamSize = maxBytes + 5000;
      final chunkSize = 1000;
      var totalReceived = 0;

      final completer = Completer<void>();
      response.stream.listen(
        (chunk) {
          totalReceived += chunk.length;
        },
        onDone: completer.complete,
      );

      for (var b = 0; b < totalStreamSize; b += chunkSize) {
        final currentChunkSize = (totalStreamSize - b) < chunkSize
            ? (totalStreamSize - b)
            : chunkSize;
        sourceController.add(List.filled(currentChunkSize, 42));
      }
      await sourceController.close();
      await completer.future;

      expect(totalReceived, totalStreamSize);

      final terminalEntry = await waitForTerminalEntry(entryId);
      expect(terminalEntry, isNotNull);
      expect(terminalEntry!.hasError, isFalse);
      expect(terminalEntry.statusCode, 200);
      expect(terminalEntry.responseSizeBytes, maxBytes);
    });
  });
}
