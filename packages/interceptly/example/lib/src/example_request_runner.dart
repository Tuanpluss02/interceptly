import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

class ExampleRequestRunner {
  const ExampleRequestRunner({
    required this.baseUrl,
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
  });

  final String baseUrl;
  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;

  Future<ExampleRequestResult> runDioGet() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('/api/users');
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.response?.data?.toString() ?? e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<ExampleRequestResult> runHttpGet() async {
    final sw = Stopwatch()..start();
    try {
      final response = await httpClient.get(
        Uri.parse('$baseUrl/api/users'),
        headers: {'Accept': 'application/json'},
      );
      sw.stop();
      return ExampleRequestResult(
        statusCode: response.statusCode,
        preview: response.body,
        bytesReceived: response.bodyBytes.length,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      final preview = e.toString();
      return ExampleRequestResult(
        statusCode: 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  Future<ExampleRequestResult> runChopperGet() async {
    final sw = Stopwatch()..start();
    try {
      final response = await chopperClient.get<dynamic, dynamic>(
        Uri.parse('$baseUrl/api/users'),
        headers: {'Accept': 'application/json'},
      );
      sw.stop();
      final bodyStr = response.body.toString();
      return ExampleRequestResult(
        statusCode: response.statusCode,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      final preview = e.toString();
      return ExampleRequestResult(
        statusCode: 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/users -> 201 Created
  Future<ExampleRequestResult> runPostUser() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.post<dynamic>(
        '/api/users',
        data: {
          'name': 'Grace Hopper',
          'email': 'grace@navy.mil',
          'role': 'Rear Admiral & Pioneer',
        },
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 201,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// PUT /api/users/1 -> 200 OK (Full Update)
  Future<ExampleRequestResult> runPutUser() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.put<dynamic>(
        '/api/users/1',
        data: {
          'id': '1',
          'name': 'Alice Johnson (Updated)',
          'email': 'alice.new@example.com',
          'role': 'Principal Admin',
        },
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// PATCH /api/users/1 -> 200 OK (Partial Update)
  Future<ExampleRequestResult> runPatchUser() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.patch<dynamic>(
        '/api/users/1',
        data: {'role': 'Lead Software Architect'},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// DELETE /api/users/1 -> 204 No Content
  Future<ExampleRequestResult> runDeleteUser() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.delete<dynamic>('/api/users/1');
      sw.stop();
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 204,
        preview: '[204 No Content] Resource deleted successfully.',
        bytesReceived: 0,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/bad-request -> 400 Bad Request
  Future<ExampleRequestResult> run400BadRequest() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.post<dynamic>(
        '/api/bad-request',
        data: {'email': 'not_an_email', 'age': 12},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final bodyStr = jsonEncode(e.response?.data);
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 400,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /api/unauthorized -> 401 Unauthorized
  Future<ExampleRequestResult> run401Unauthorized() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('/api/unauthorized');
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final bodyStr = jsonEncode(e.response?.data);
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 401,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /api/not-found -> 404 Not Found
  Future<ExampleRequestResult> run404NotFound() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('/api/not-found');
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final bodyStr = jsonEncode(e.response?.data);
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 404,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /api/error?status=503 -> 503 Service Unavailable
  Future<ExampleRequestResult> runError() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>('/api/error?status=503');
      sw.stop();
      final bodyStr = response.data.toString();
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.response?.data != null
          ? jsonEncode(e.response!.data)
          : (e.message ?? e.type.name);
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 503,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/graphql (Query with variables)
  Future<ExampleRequestResult> runGraphQLQuery() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.post<dynamic>(
        '/api/graphql',
        data: {
          'operationName': 'GetUser',
          'query': '''
query GetUser(\$id: ID!) {
  user(id: \$id) {
    id
    name
    email
    role
    status
    projects {
      id
      name
    }
  }
}''',
          'variables': {'id': 'usr_42'},
        },
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/graphql (Mutation)
  Future<ExampleRequestResult> runGraphQLMutation() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.post<dynamic>(
        '/api/graphql',
        data: {
          'operationName': 'UpdateUserStatus',
          'query': '''
mutation UpdateUserStatus(\$id: ID!, \$status: String!) {
  mutateUser(id: \$id, status: \$status) {
    success
    operationName
    timestamp
    affectedId
  }
}''',
          'variables': {'id': 'usr_42', 'status': 'VERIFIED'},
        },
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/upload (Dio FormData with fields and files)
  Future<ExampleRequestResult> runMultipartUpload() async {
    final sw = Stopwatch()..start();
    try {
      final fakeImageBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
      ]);
      final fakeTextDoc = utf8
          .encode('Hello Interceptly multipart upload demonstration document.');

      final formData = FormData.fromMap({
        'username': 'johndoe',
        'accountType': 'ENTERPRISE',
        'notes': 'Uploaded via Interceptly Example App',
        'avatar': MultipartFile.fromBytes(
          fakeImageBytes,
          filename: 'user_avatar.png',
          contentType: DioMediaType('image', 'png'),
        ),
        'document': MultipartFile.fromBytes(
          fakeTextDoc,
          filename: 'attachment.txt',
          contentType: DioMediaType('text', 'plain'),
        ),
      });

      final response = await dio.post<dynamic>(
        '/api/upload',
        data: formData,
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: bodyStr,
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /api/image/png -> Binary image preview
  Future<ExampleRequestResult> runGetImage() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<List<int>>(
        '/api/image/png',
        options: Options(responseType: ResponseType.bytes),
      );
      sw.stop();
      final length = response.data?.length ?? 0;
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            '[Binary PNG Image: $length bytes received]. Check Request Detail > Response tab for binary inspection.',
        bytesReceived: length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// GET /api/image/svg -> Vector image
  Future<ExampleRequestResult> runGetSvg() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<String>(
        '/api/image/svg',
      );
      sw.stop();
      final length = utf8.encode(response.data ?? '').length;
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: response.data ?? '',
        bytesReceived: length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// POST /api/analytics/track -> URL blacklisted by shouldCapture
  Future<ExampleRequestResult> runAnalyticsRequest() async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.post<dynamic>(
        '/api/analytics/track',
        data: {
          'eventType': 'button_click',
          'screen': 'example_home',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            'Request completed with 200 OK! Note: Notice that Interceptly DID NOT capture this call because url contains "/analytics" (shouldCapture filter).',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Heavy JSON (~1MB, ~3,000 items, ~25k lines)
  Future<ExampleRequestResult> runHeavyListGet({int count = 3000}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '/api/heavy-list',
        queryParameters: {'count': count},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            'Received $count items. (Preview first 300 chars: ${bodyStr.substring(0, bodyStr.length.clamp(0, 300))}...)',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Extreme JSON (~6MB, ~20,000 items, >140k lines) -> Triggers Interceptly's 2MB UI truncate
  Future<ExampleRequestResult> runExtremeListGet({int count = 20000}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '/api/extreme-list',
        queryParameters: {'count': count},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            'Received $count items (>2MB). Open Inspector to verify truncation banner & disk offload!',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Deeply nested JSON (e.g. 35 levels deep)
  Future<ExampleRequestResult> runDeepNestedGet({int depth = 35}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '/api/nested',
        queryParameters: {'depth': depth},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            'Nested JSON with depth: $depth. (First 200 chars: ${bodyStr.substring(0, bodyStr.length.clamp(0, 200))}...)',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Wide text object with large single string field (e.g. 100k characters)
  Future<ExampleRequestResult> runWideTextGet({int chars = 100000}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '/api/wide-text',
        queryParameters: {'chars': chars},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview:
            'Wide text payload with $chars chars. Test horizontal scroll & copy.',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Heavy POST request (Uploads 1,000 items in request body)
  Future<ExampleRequestResult> runHeavyPost({int items = 1000}) async {
    final sw = Stopwatch()..start();
    try {
      final payload = {
        'action': 'bulk_upload',
        'itemCount': items,
        'submittedAt': DateTime.now().toIso8601String(),
        'records': List.generate(
            items,
            (i) => {
                  'index': i,
                  'token': 'auth_token_sample_${i * 42}',
                  'data': 'Record details for entry $i',
                }),
      };
      final response = await dio.post<dynamic>('/api/echo', data: payload);
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: 'Uploaded $items items in POST body. Echo response received.',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Delayed response to test loading spinner in Interceptly
  Future<ExampleRequestResult> runDelayedGet({int delayMs = 1500}) async {
    final sw = Stopwatch()..start();
    try {
      final response = await dio.get<dynamic>(
        '/api/delayed',
        queryParameters: {'delayMs': delayMs},
      );
      sw.stop();
      final bodyStr = jsonEncode(response.data);
      return ExampleRequestResult(
        statusCode: response.statusCode ?? 200,
        preview: 'Delayed request finished after ${sw.elapsedMilliseconds}ms.',
        bytesReceived: utf8.encode(bodyStr).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } on DioException catch (e) {
      sw.stop();
      final preview = e.message ?? e.type.name;
      return ExampleRequestResult(
        statusCode: e.response?.statusCode ?? 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Connects to /ws/echo via InterceptlyWebSocketChannel, sends text and JSON
  /// frames, receives echoes, and cleanly closes the connection.
  Future<ExampleRequestResult> runWebSocketEcho() async {
    final sw = Stopwatch()..start();
    try {
      final wsUri = Uri.parse('$baseUrl/ws/chat'.replaceFirst('http', 'ws'));
      final channel = InterceptlyWebSocketChannel.connect(wsUri);

      final completer = Completer<String>();
      final receivedMessages = <String>[];

      final sub = channel.stream.listen(
        (dynamic message) {
          receivedMessages.add(message.toString());
          if (receivedMessages.length >= 3 && !completer.isCompleted) {
            completer.complete('Received chat stream messages');
          }
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
      );

      // Send chat message
      channel.sink.add(
        jsonEncode({
          'type': 'chat',
          'message': 'ping',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      // Await responses (welcome, agent greeting, typing/pong)
      await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => 'Timeout waiting for chat messages',
      );

      await channel.sink.close(1000, 'Normal closure');
      await sub.cancel();
      sw.stop();

      final preview = 'WebSocket Live Chat Test Completed:\n'
          '• Endpoint: /ws/chat\n'
          '• Received: ${receivedMessages.length} frames (System welcome, StormX greeting, Pong)\n'
          '• Frames: ${receivedMessages.join("\n")}';

      return ExampleRequestResult(
        statusCode: 101,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      final preview = 'WebSocket error: $e';
      return ExampleRequestResult(
        statusCode: 0,
        preview: preview,
        bytesReceived: utf8.encode(preview).length,
        durationMs: sw.elapsedMilliseconds,
      );
    }
  }

  void dispose() {
    httpClient.close();
    chopperClient.dispose();
  }
}

class ExampleRequestResult {
  const ExampleRequestResult({
    required this.statusCode,
    required this.preview,
    required this.bytesReceived,
    required this.durationMs,
  });

  final int statusCode;
  final String preview;
  final int bytesReceived;
  final int durationMs;

  String get formattedBytes {
    if (bytesReceived < 1024) return '$bytesReceived B';
    if (bytesReceived < 1024 * 1024) {
      return '${(bytesReceived / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesReceived / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
