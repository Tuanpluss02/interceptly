import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_chopper/interceptly_chopper.dart';

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
    await InspectorSession.resetForTesting();
    session = InspectorSession.instance;
    await session.initialize();
  });

  tearDown(() async {
    await session.dispose();
    await InspectorSession.resetForTesting();
  });

  Future<void> waitForSessionEntry({
    required String id,
    Duration timeout = const Duration(seconds: 3),
    bool requireTerminal = true,
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final entry = session.entries.cast<RequestSummary?>().firstWhere(
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
        final interceptor = InterceptlyChopperInterceptor();
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
            http.Response('{"ok":true}', 200,
                request: http.Request('GET', req.url)),
            '{"ok":true}',
          ),
        );

        final response = await interceptor.intercept(chain);

        expect(chain.proceededRequest, isNotNull);
        expect(chain.proceededRequest!.parameters, equals(complexParams));
        expect(
          identical(chain.proceededRequest!.parameters, request.parameters),
          isTrue,
        );
        expect(
          chain.proceededRequest!.parameters
              .containsKey('interceptly_started_at'),
          isFalse,
        );
        expect(
          chain.proceededRequest!.parameters
              .containsKey('interceptly_request_id'),
          isFalse,
        );
        expect(response.statusCode, 200);

        await waitForSessionEntry(id: session.entries.first.id);
        final entry = session.entries.first;
        expect(entry.hasError, isFalse);
        expect(entry.statusCode, 200);
      },
    );

    test('Empty, null, nested lists and primitive parameters', () async {
      final interceptor = InterceptlyChopperInterceptor();
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
          http.Response('{"ok":true}', 200,
              request: http.Request('POST', req.url)),
          '{"ok":true}',
        ),
      );

      await interceptor.intercept(chain);

      expect(chain.proceededRequest!.parameters, equals(diverseParams));
      expect(
        chain.proceededRequest!.parameters
            .containsKey('interceptly_started_at'),
        isFalse,
      );
      expect(
        chain.proceededRequest!.parameters
            .containsKey('interceptly_request_id'),
        isFalse,
      );
    });

    test(
      'Colliding parameter names: user explicitly passes interceptly_* keys',
      () async {
        final interceptor = InterceptlyChopperInterceptor();
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
            http.Response('{"ok":true}', 200,
                request: http.Request('GET', req.url)),
            '{"ok":true}',
          ),
        );

        await interceptor.intercept(chain);

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

    test('50 concurrent Chopper requests preserve unique IDs and parameters',
        () async {
      final interceptor = InterceptlyChopperInterceptor();
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
              http.Response('{"i":$index}', 200,
                  request: http.Request(r.method, r.url)),
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

      final end = DateTime.now().add(const Duration(seconds: 4));
      while (session.entries.length < 50) {
        if (DateTime.now().isAfter(end)) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(session.entries.length, 50);

      final idSet = session.entries.map((e) => e.id).toSet();
      expect(idSet.length, 50);
    });

    test('Transport exceptions rethrow and record RawCapture promptly',
        () async {
      final interceptor = InterceptlyChopperInterceptor();
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

}
