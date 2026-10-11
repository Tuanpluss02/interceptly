import 'dart:convert';

import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

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

  // ── Basic Traffic (Replaces external endpoints) ──────────────────────

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

  // ── Stress Test & Heavy JSON Endpoints ──────────────────────────────

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
        preview: 'Received $count items. (Preview first 300 chars: ${bodyStr.substring(0, bodyStr.length.clamp(0, 300))}...)',
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
        preview: 'Received $count items (>2MB). Open Inspector to verify truncation banner & disk offload!',
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
        preview: 'Nested JSON with depth: $depth. (First 200 chars: ${bodyStr.substring(0, bodyStr.length.clamp(0, 200))}...)',
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
        preview: 'Wide text payload with $chars chars. Test horizontal scroll & copy.',
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
        'records': List.generate(items, (i) => {
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

