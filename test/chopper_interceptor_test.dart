import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';

class _FakeChain<BodyType> implements Chain<BodyType> {
  _FakeChain(this.request, this.responseHandler);

  @override
  final Request request;
  final FutureOr<Response<BodyType>> Function(Request request) responseHandler;
  Request? proceededRequest;

  @override
  FutureOr<Response<BodyType>> proceed(Request request) {
    proceededRequest = request;
    return responseHandler(request);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late InspectorSession session;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('interceptly_chopper_test');
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

  group('InterceptlyChopperInterceptor', () {
    test(
      'InterceptlyChopperInterceptor does not alter outbound request.parameters',
      () async {
        final interceptor = InterceptlyChopperInterceptor(session);

        final originalParams = <String, dynamic>{
          'page': '1',
          'filter': 'active',
          'query': 'dart',
        };
        final request = Request(
          'GET',
          Uri.parse('https://api.example.com/items'),
          Uri.parse('https://api.example.com'),
          parameters: Map<String, dynamic>.from(originalParams),
        );

        final chain = _FakeChain<String>(
          request,
          (req) => Response(
            http.Response(
              '{"items":[]}',
              200,
              request: http.Request('GET', req.url),
            ),
            '{"items":[]}',
          ),
        );

        final response = await interceptor.intercept(chain);

        // 1. Verify outbound request.parameters was NOT altered
        expect(chain.proceededRequest, isNotNull);
        expect(chain.proceededRequest!.parameters, equals(originalParams));
        expect(
          chain.proceededRequest!.parameters.containsKey(
            'interceptly_started_at',
          ),
          isFalse,
        );
        expect(
          chain.proceededRequest!.parameters.containsKey(
            'interceptly_request_id',
          ),
          isFalse,
        );

        // 2. Response returned cleanly
        expect(response.statusCode, 200);
        expect(response.body, '{"items":[]}');

        // Wait for session writer isolate to complete entry processing
        final end = DateTime.now().add(const Duration(seconds: 3));
        while (session.entries.isEmpty ||
            session.entries.first.statusCode == 0) {
          if (DateTime.now().isAfter(end)) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }

        // 3. Verify entry recorded in session with correct metadata
        expect(session.entries.length, 1);
        final entry = session.entries.first;
        expect(entry.url, contains('https://api.example.com/items'));
        expect(entry.url, isNot(contains('interceptly_started_at')));
        expect(entry.url, isNot(contains('interceptly_request_id')));
        expect(entry.method, 'GET');
        expect(entry.id, isNotEmpty);
        expect(entry.statusCode, 200);
        expect(entry.hasError, isFalse);
      },
    );

    test('preserves empty parameters without adding tracking keys', () async {
      final interceptor = InterceptlyChopperInterceptor(session);

      final request = Request(
        'POST',
        Uri.parse('https://api.example.com/login'),
        Uri.parse('https://api.example.com'),
        body: '{"user":"alice"}',
        headers: {'content-type': 'application/json'},
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"token":"abc"}',
            201,
            request: http.Request('POST', req.url),
          ),
          '{"token":"abc"}',
        ),
      );

      final response = await interceptor.intercept(chain);

      expect(chain.proceededRequest!.parameters, isEmpty);
      expect(response.statusCode, 201);

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty ||
          session.entries.first.statusCode == 0) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.url, isNot(contains('interceptly_started_at')));
      expect(entry.url, isNot(contains('interceptly_request_id')));
    });

    test('captures transport exception when chain.proceed throws', () async {
      final interceptor = InterceptlyChopperInterceptor(session);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/broken'),
        Uri.parse('https://api.example.com'),
        parameters: {'retry': 'false'},
      );

      final chain = _FakeChain<String>(
        request,
        (req) => throw http.ClientException('Connection failed'),
      );

      await expectLater(
        () => interceptor.intercept(chain),
        throwsA(isA<http.ClientException>()),
      );

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty || !session.entries.first.hasError) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      expect(chain.proceededRequest!.parameters, equals({'retry': 'false'}));
      final entry = session.entries.first;
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'ClientException');
    });

    test('captures HTTP error responses from server', () async {
      final interceptor = InterceptlyChopperInterceptor(session);

      final request = Request(
        'GET',
        Uri.parse('https://api.example.com/missing'),
        Uri.parse('https://api.example.com'),
      );

      final chain = _FakeChain<String>(
        request,
        (req) => Response(
          http.Response(
            '{"error":"not_found"}',
            404,
            request: http.Request('GET', req.url),
          ),
          '{"error":"not_found"}',
          error: 'Not Found',
        ),
      );

      final response = await interceptor.intercept(chain);

      expect(response.statusCode, 404);
      expect(response.isSuccessful, isFalse);
      expect(chain.proceededRequest!.parameters, isEmpty);

      final end = DateTime.now().add(const Duration(seconds: 3));
      while (session.entries.isEmpty ||
          session.entries.first.statusCode == 0) {
        if (DateTime.now().isAfter(end)) break;
        await Future.delayed(const Duration(milliseconds: 50));
      }

      expect(session.entries.length, 1);
      final entry = session.entries.first;
      expect(entry.statusCode, 404);
      expect(entry.hasError, isTrue);
      expect(entry.errorType, 'ChopperError');
    });
  });
}
