import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:flutter/material.dart';
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

      expect(proceededParams.length, 100);
      for (var i = 0; i < 100; i++) {
        final params = proceededParams[i]!;
        expect(params['index'], '$i');
        expect(params.containsKey('interceptly_started_at'), isFalse,
            reason: 'Leaked interceptly_started_at in request $i');
        expect(params.containsKey('interceptly_request_id'), isFalse,
            reason: 'Leaked interceptly_request_id in request $i');
      }

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

        final url = tc['url'] as String;
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        RequestSummary? matched;
        while (DateTime.now().isBefore(deadline)) {
          matched = session.entries.cast<RequestSummary?>().firstWhere(
                (e) => e != null && e.url.contains(url) && e.hasError,
                orElse: () => null,
              );
          if (matched != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        if (matched == null) {
          debugPrint(
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

        final urlPart = '/status/$code';
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        RequestSummary? entry;
        while (DateTime.now().isBefore(deadline)) {
          entry = session.entries.cast<RequestSummary?>().firstWhere(
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

}
