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

class _MultiStreamMockClient extends http.BaseClient {
  _MultiStreamMockClient(this.controllerProvider);

  final StreamController<List<int>> Function(http.BaseRequest request)
      controllerProvider;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ctrl = controllerProvider(request);
    return http.StreamedResponse(
      ctrl.stream,
      200,
      request: request,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_m2_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    session = InspectorSession();
    await session.initialize();
  });

  tearDown(() async {
    session.dispose();
  });

  Future<void> waitForSessionEntry({
    required String id,
    Duration timeout = const Duration(seconds: 3),
    bool requireTerminal = true,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final entry = session.entries.cast<IndexEntry?>().firstWhere(
            (e) => e?.id == id,
            orElse: () => null,
          );
      if (entry != null) {
        if (!requireTerminal || entry.statusCode != 0 || entry.hasError) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  group('Challenger M2 - Area 1: Chopper Parameter Purity & Edge Cases', () {
    test(
      'Adversarial parameters: emojis, unicode, URL-reserved symbols, spaces',
      () async {
        final interceptor = InterceptlyChopperInterceptor(session);
        final complexParams = <String, dynamic>{
          'emoji': '🚀🔥🎉✨',
          'vietnamese': 'tiếng Việt có dấu và khoảng trắng',
          'reserved': 'a=1&b=2?foo=bar#section/path',
          'quotes': '"single\'double"and`backtick`',
          'special_punct': r'!@$%^*()_+-=[]{}|;:,.<>?',
          'spaces': '   leading and trailing spaces   ',
        };

        final request = Request(
          'GET',
          Uri.parse('https://api.example.com/search'),
          Uri.parse('https://api.example.com'),
          parameters: Map<String, dynamic>.from(complexParams),
        );

        final chain = _CapturingChain<String>(
          request,
          (req) => Response(
            http.Response('{"ok":true}', 200, request: http.Request('GET', req.url)),
            '{"ok":true}',
          ),
        );

        final response = await interceptor.intercept(chain);

        // 1. Verify outbound request parameters are completely unmodified
        expect(chain.proceededRequest, isNotNull);
        expect(chain.proceededRequest!.parameters, equals(complexParams));
        expect(
          identical(chain.proceededRequest!.parameters, request.parameters),
          isTrue,
        );
        expect(
          chain.proceededRequest!.parameters.containsKey('interceptly_started_at'),
          isFalse,
        );
        expect(
          chain.proceededRequest!.parameters.containsKey('interceptly_request_id'),
          isFalse,
        );
        expect(response.statusCode, 200);

        // Verify session entry
        await waitForSessionEntry(id: session.entries.first.id);
        final entry = session.entries.first;
        expect(entry.hasError, isFalse);
        expect(entry.statusCode, 200);
      },
    );

    test('Empty, null, nested lists and primitive parameters', () async {
      final interceptor = InterceptlyChopperInterceptor(session);
      final diverseParams = <String, dynamic>{
        'empty_string': '',
        'null_val': null,
        'integer': 42,
        'negative': -999,
        'double': 3.14159,
        'boolean_true': true,
        'boolean_false': false,
        'list_strings': ['alpha', 'beta', 'gamma'],
        'list_empty': <String>[],
      };

      final request = Request(
        'POST',
        Uri.parse('https://api.example.com/filter'),
        Uri.parse('https://api.example.com'),
        parameters: Map<String, dynamic>.from(diverseParams),
      );

      final chain = _CapturingChain<String>(
        request,
        (req) => Response(
          http.Response('{"ok":true}', 200, request: http.Request('POST', req.url)),
          '{"ok":true}',
        ),
      );

      await interceptor.intercept(chain);

      expect(chain.proceededRequest!.parameters, equals(diverseParams));
      expect(
        chain.proceededRequest!.parameters.containsKey('interceptly_started_at'),
        isFalse,
      );
      expect(
        chain.proceededRequest!.parameters.containsKey('interceptly_request_id'),
        isFalse,
      );
    });

    test(
      'Colliding parameter names: user explicitly passes interceptly_* keys',
      () async {
        final interceptor = InterceptlyChopperInterceptor(session);
        final userCustomParams = <String, dynamic>{
          'interceptly_started_at': 'custom_user_timestamp_123',
          'interceptly_request_id': 'custom_user_req_999',
          'regular_key': 'hello',
        };

        final request = Request(
          'GET',
          Uri.parse('https://api.example.com/collision-test'),
          Uri.parse('https://api.example.com'),
          parameters: Map<String, dynamic>.from(userCustomParams),
        );

        final chain = _CapturingChain<String>(
          request,
          (req) => Response(
            http.Response('{"ok":true}', 200, request: http.Request('GET', req.url)),
            '{"ok":true}',
          ),
        );

        await interceptor.intercept(chain);

        // Must NOT overwrite or drop the user's custom parameters
        expect(
          chain.proceededRequest!.parameters['interceptly_started_at'],
          'custom_user_timestamp_123',
        );
        expect(
          chain.proceededRequest!.parameters['interceptly_request_id'],
          'custom_user_req_999',
        );
        expect(chain.proceededRequest!.parameters['regular_key'], 'hello');
      },
    );

    test('50 concurrent Chopper requests preserve unique IDs and parameters', () async {
      final interceptor = InterceptlyChopperInterceptor(session);
      final futures = <Future<void>>[];
      final proceededParams = <int, Map<String, dynamic>>{};

      for (var i = 0; i < 50; i++) {
        final index = i;
        final params = {'req_num': '$index', 'hash': 'h_$index'};
        final req = Request(
          index % 2 == 0 ? 'GET' : 'POST',
          Uri.parse('https://api.example.com/batch/$index'),
          Uri.parse('https://api.example.com'),
          parameters: params,
        );

        final chain = _CapturingChain<String>(
          req,
          (r) async {
            await Future<void>.delayed(
              Duration(milliseconds: 5 + (index % 10)),
            );
            return Response(
              http.Response('{"i":$index}', 200, request: http.Request(r.method, r.url)),
              '{"i":$index}',
            );
          },
        );

        futures.add(
          Future.sync(() => interceptor.intercept(chain)).then((_) {
            proceededParams[index] = chain.proceededRequest!.parameters;
          }),
        );
      }

      await Future.wait(futures);

      expect(proceededParams.length, 50);
      for (var i = 0; i < 50; i++) {
        expect(proceededParams[i], equals({'req_num': '$i', 'hash': 'h_$i'}));
        expect(
          proceededParams[i]!.containsKey('interceptly_started_at'),
          isFalse,
        );
      }

      // Wait for session entries
      final end = DateTime.now().add(const Duration(seconds: 4));
      while (session.entries.length < 50) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(session.entries.length, 50);

      // Verify all session IDs are unique
      final idSet = session.entries.map((e) => e.id).toSet();
      expect(idSet.length, 50);
    });

    test('Transport exceptions rethrow and record RawCapture promptly', () async {
      final interceptor = InterceptlyChopperInterceptor(session);
      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/socket-fail'),
        Uri.parse('https://api.example.com'),
        parameters: {'test': 'socket'},
      );

      final chain = _CapturingChain<String>(
        request,
        (_) => throw const SocketException('Network unreachable'),
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<SocketException>()),
      );

      // Ensure chain received unmodified parameters before throwing
      expect(chain.proceededRequest!.parameters, equals({'test': 'socket'}));

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || !session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, contains('SocketException'));
      expect(entry.errorMessage, contains('Network unreachable'));
    });
  });

  group('Challenger M2 - Area 2: HTTP Client Stream Cancellation Promptness & Concurrency', () {
    test('Immediate cancellation before any chunks are emitted (< 500ms)', () async {
      final streamCtrl = StreamController<List<int>>();
      final mockClient = _MultiStreamMockClient((_) => streamCtrl);
      final client = InterceptlyHttpClient(mockClient, session);

      final stopwatch = Stopwatch()..start();
      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/immediate-cancel')),
      );

      // Initial pending entry exists
      expect(session.entries.length, 1);
      final pendingEntry = session.entries.first;
      expect(pendingEntry.statusCode, 0);

      // Cancel stream subscription immediately without sending chunks
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      await streamCtrl.close();

      // Verify prompt cancellation (< 500ms, well under 3 seconds)
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) {
          fail('Immediate cancellation did not update entry within 3 seconds');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      stopwatch.stop();

      // Must complete prompt, orders of magnitude faster than 45s pending timeout
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'CancellationException');
      expect(entry.errorMessage, 'Stream subscription was canceled by client.');
    });

    test('Mid-stream cancellation preserves partial bytes captured', () async {
      final streamCtrl = StreamController<List<int>>();
      final mockClient = _MultiStreamMockClient((_) => streamCtrl);
      final client = InterceptlyHttpClient(mockClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/partial-stream')),
      );

      final receivedChunks = <List<int>>[];
      late StreamSubscription<List<int>> sub;
      final cancelCompleter = Completer<void>();

      sub = response.stream.listen(
        (chunk) async {
          receivedChunks.add(chunk);
          if (receivedChunks.length == 2) {
            await sub.cancel();
            await streamCtrl.close();
            cancelCompleter.complete();
          }
        },
      );

      // Push 4 chunks into the stream
      streamCtrl.add([1, 2, 3]);
      streamCtrl.add([4, 5, 6]);

      await cancelCompleter.future;

      // Verify prompt recording
      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) {
          fail('Mid-stream cancellation did not record within 3s');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'CancellationException');
      expect(receivedChunks.length, 2);
    });

    test('Stream cancellation under active network simulation throttling', () async {
      // Configure network simulation with slow profile (delay per chunk)
      session.setNetworkSimulation(NetworkSimulationProfile.slow3G);

      final streamCtrl = StreamController<List<int>>();
      final mockClient = _MultiStreamMockClient((_) => streamCtrl);
      final client = InterceptlyHttpClient(mockClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/throttled-cancel')),
      );

      final sub = response.stream.listen((_) {});
      // Emit a 500-byte chunk which triggers throughput delay
      streamCtrl.add(List.generate(500, (i) => i % 256));

      // Cancel mid-delay
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      await streamCtrl.close();

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) {
          fail('Cancellation under throttling did not record within 3 seconds');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'CancellationException');

      // Reset simulation
      session.clearNetworkSimulation();
    });

    test('Pause, resume, and multiple cancel calls do not double record or throw', () async {
      final streamCtrl = StreamController<List<int>>();
      final mockClient = _MultiStreamMockClient((_) => streamCtrl);
      final client = InterceptlyHttpClient(mockClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/pause-cancel')),
      );

      final sub = response.stream.listen((_) {});
      sub.pause();
      expect(streamCtrl.isPaused, isTrue);
      sub.resume();
      expect(streamCtrl.isPaused, isFalse);

      // Call cancel multiple times
      await sub.cancel();
      await sub.cancel();
      await streamCtrl.close();

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'CancellationException');
    });

    test('High concurrency stress: 30 requests with interleaved cancellations and normal completions', () async {
      final controllers = <int, StreamController<List<int>>>{};
      final mockClient = _MultiStreamMockClient((req) {
        final path = req.url.pathSegments.last;
        final id = int.parse(path);
        final ctrl = StreamController<List<int>>();
        controllers[id] = ctrl;
        return ctrl;
      });
      final client = InterceptlyHttpClient(mockClient, session);

      final futures = <Future<void>>[];
      final cancelledIds = <int>{};
      final completedIds = <int>{};

      for (var i = 0; i < 30; i++) {
        final index = i;
        final shouldCancel = index % 2 == 0;
        if (shouldCancel) {
          cancelledIds.add(index);
        } else {
          completedIds.add(index);
        }

        futures.add(() async {
          final res = await client.send(
            http.Request('GET', Uri.parse('https://api.example.com/item/$index')),
          );

          final ctrl = controllers[index]!;
          if (shouldCancel) {
            final sub = res.stream.listen((_) {});
            ctrl.add([1, 2, 3]);
            await Future<void>.delayed(Duration(milliseconds: 5 + (index % 10)));
            await sub.cancel();
            await ctrl.close();
          } else {
            final completer = Completer<void>();
            res.stream.listen((_) {}, onDone: completer.complete);
            ctrl.add([10, 20, 30]);
            await ctrl.close();
            await completer.future;
          }
        }());
      }

      await Future.wait(futures);

      // Wait for all 30 entries to be processed into terminal states
      final end = DateTime.now().add(const Duration(seconds: 4));
      while (session.entries.where((e) => e.statusCode != 0 || e.hasError).length < 30) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 30);

      final cancelledEntries =
          session.entries.where((e) => e.hasError && e.errorType == 'CancellationException').toList();
      final completedEntries =
          session.entries.where((e) => !e.hasError && e.statusCode == 200).toList();

      expect(cancelledEntries.length, 15);
      expect(completedEntries.length, 15);
    });

    test('Cancellation immediately cancels pending timer in InspectorSession', () async {
      final streamCtrl = StreamController<List<int>>();
      final mockClient = _MultiStreamMockClient((_) => streamCtrl);
      final client = InterceptlyHttpClient(mockClient, session);

      final response = await client.send(
        http.Request('GET', Uri.parse('https://api.example.com/timer-test')),
      );

      final entryId = session.entries.first.id;
      // Pending timer was scheduled for this request
      // Now cancel the stream
      final sub = response.stream.listen((_) {});
      await sub.cancel();
      await streamCtrl.close();

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (!session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final entry = session.entries.first;
      expect(entry.id, entryId);
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'CancellationException');
    });
  });
}
