import 'dart:developer' as developer;

import '../engine/interceptly_engine.dart';
import '../export/curl_generator.dart';
import '../model/request_summary.dart';
import 'service_extension_exception.dart';

/// Handlers for HTTP traffic inspection service extensions.
abstract final class HttpExtensionHandlers {
  /// Handles `ext.interceptly.listRequests`.
  ///
  /// Query parameters:
  /// - `status_filter`: 'all' | 'failed' | '2xx' | '3xx' | '4xx' | '5xx'
  /// - `search`: search substring across URL, method, headers, error, and body
  /// - `search_body`: whether to search body content ('true' | 'false', default: 'true')
  /// - `since_id`: cursor pagination (returns only entries created after [since_id])
  /// - `limit`: maximum number of entries to return (default 20, max 100)
  static Future<Map<String, dynamic>> handleListRequests({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    final entries = engine?.entries ?? <RequestSummary>[];
    final statusFilter = (parameters['status_filter'] ?? 'all').toLowerCase();
    final search = parameters['search']?.trim();
    final searchBody = parameters['search_body'] != 'false';
    final sinceId = parameters['since_id'];
    final limit =
        int.tryParse(parameters['limit'] ?? '20')?.clamp(1, 100) ?? 20;

    if (engine == null) {
      return {
        'total': 0,
        'count': 0,
        'requests': const <Map<String, dynamic>>[],
      };
    }

    // 1. When search query is present, delegate to multi-phase engine search
    if (search != null && search.isNotEmpty) {
      final searchResults = await engine.search(
        query: search,
        searchBody: searchBody,
        statusFilter: statusFilter,
        sinceId: sinceId,
        limit: limit,
      );

      final mapped = searchResults.map((r) {
        final e = r.summary;
        return {
          'id': e.id,
          'method': e.method,
          'url': e.url,
          'statusCode': e.statusCode,
          'durationMs': e.durationMs,
          'requestSizeBytes': e.requestSizeBytes,
          'responseSizeBytes': e.responseSizeBytes,
          'timestamp': e.timestamp.toIso8601String(),
          'hasError': e.hasError,
          'errorType': e.errorType,
          'errorMessage': e.errorMessage,
          'matchScopes': r.matchScopes.map((s) => s.name).toList(),
        };
      }).toList();

      return {
        'total': entries.length,
        'count': mapped.length,
        'requests': mapped,
      };
    }

    // 2. Fast path when no search query
    var filtered = entries.toList();

    // since_id cursor: find index of sinceId and take entries before it (entries are newest-first)
    if (sinceId != null && sinceId.isNotEmpty) {
      final index = filtered.indexWhere((e) => e.id == sinceId);
      if (index > 0) {
        filtered = filtered.sublist(0, index);
      } else if (index == 0) {
        filtered = <RequestSummary>[];
      } else {
        // Cursor not found in ring buffer (evicted or non-existent)
        filtered = <RequestSummary>[];
      }
    }

    // Status filter
    if (statusFilter != 'all') {
      filtered = filtered.where((e) {
        final code = e.statusCode;
        return switch (statusFilter) {
          'failed' => e.hasError || code >= 400,
          '2xx' => code >= 200 && code < 300,
          '3xx' => code >= 300 && code < 400,
          '4xx' => code >= 400 && code < 500,
          '5xx' => code >= 500 && code < 600,
          _ => true,
        };
      }).toList();
    }

    // Limit
    if (filtered.length > limit) {
      filtered = filtered.sublist(0, limit);
    }

    final mapped = filtered
        .map((e) => {
              'id': e.id,
              'method': e.method,
              'url': e.url,
              'statusCode': e.statusCode,
              'durationMs': e.durationMs,
              'requestSizeBytes': e.requestSizeBytes,
              'responseSizeBytes': e.responseSizeBytes,
              'timestamp': e.timestamp.toIso8601String(),
              'hasError': e.hasError,
              'errorType': e.errorType,
              'errorMessage': e.errorMessage,
              'matchScopes': const <String>[],
            })
        .toList();

    return {
      'total': entries.length,
      'count': mapped.length,
      'requests': mapped,
    };
  }

  /// Handles `ext.interceptly.getRequestDetail`.
  ///
  /// Query parameters:
  /// - `id`: request ID (required)
  /// - `part`: 'all' | 'request_body' | 'response_body' | 'request_headers' | 'response_headers'
  /// - `max_chars`: maximum character count for body preview (default 4000)
  /// - `offset`: character offset for continuation
  static Future<Map<String, dynamic>> handleGetRequestDetail({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    final id = parameters['id'];
    if (id == null || id.isEmpty) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameter: id',
      );
    }

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final record = await engine.loadDetailById(id);
    final part = (parameters['part'] ?? 'all').toLowerCase();
    final maxChars =
        int.tryParse(parameters['max_chars'] ?? '4000')?.clamp(1, 100000) ??
            4000;
    final offset =
        int.tryParse(parameters['offset'] ?? '0')?.clamp(0, 10000000) ?? 0;

    String? reqBody = record.requestBodyPreview;
    String? resBody = record.responseBodyPreview;
    bool isTruncated = false;
    int totalChars = 0;
    int remainingChars = 0;

    if (part == 'response_body' || part == 'all') {
      final raw = resBody ?? '';
      if (part == 'response_body') {
        totalChars = raw.length;
      }
      if (offset < raw.length) {
        final end = (offset + maxChars).clamp(0, raw.length);
        resBody = raw.substring(offset, end);
        final rem = raw.length - end;
        if (rem > 0) isTruncated = true;
        if (part == 'response_body') remainingChars = rem;
      } else {
        resBody = '';
        if (part == 'response_body') remainingChars = 0;
      }
    }

    if (part == 'request_body' || part == 'all') {
      final raw = reqBody ?? '';
      if (part == 'request_body') {
        totalChars = raw.length;
      }
      if (offset < raw.length) {
        final end = (offset + maxChars).clamp(0, raw.length);
        reqBody = raw.substring(offset, end);
        final rem = raw.length - end;
        if (rem > 0) isTruncated = true;
        if (part == 'request_body') remainingChars = rem;
      } else {
        reqBody = '';
        if (part == 'request_body') remainingChars = 0;
      }
    }

    if (part == 'all') {
      final totalReq = (record.requestBodyPreview ?? '').length;
      final totalRes = (record.responseBodyPreview ?? '').length;
      totalChars = totalReq + totalRes;
      final remReq = (totalReq - offset - maxChars).clamp(0, totalReq);
      final remRes = (totalRes - offset - maxChars).clamp(0, totalRes);
      remainingChars = remReq + remRes;
    }

    return {
      'id': record.id,
      'method': record.method,
      'url': record.url,
      'statusCode': record.statusCode,
      'durationMs': record.durationMs,
      'requestSizeBytes': record.requestSizeBytes,
      'responseSizeBytes': record.responseSizeBytes,
      'timestamp': record.timestamp.toIso8601String(),
      if (part == 'all' || part == 'request_headers')
        'requestHeaders': record.requestHeaders,
      if (part == 'all' || part == 'response_headers')
        'responseHeaders': record.responseHeaders,
      if (part == 'all' || part == 'request_body') 'requestBody': reqBody,
      if (part == 'all' || part == 'response_body') 'responseBody': resBody,
      'isTruncated': isTruncated,
      'totalChars': totalChars,
      'remainingChars': remainingChars,
      'errorType': record.errorType,
      'errorMessage': record.errorMessage,
    };
  }

  /// Handles `ext.interceptly.exportCurl`.
  static Future<Map<String, dynamic>> handleExportCurl({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    final id = parameters['id'];
    if (id == null || id.isEmpty) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameter: id',
      );
    }

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final record = await engine.loadDetailById(id);
    final curl = CurlGenerator.fromRecord(record);

    return {
      'id': id,
      'curl': curl,
    };
  }
}
