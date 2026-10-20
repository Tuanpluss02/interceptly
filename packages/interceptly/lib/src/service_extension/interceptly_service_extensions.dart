import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../engine/interceptly_engine.dart';
import '../export/curl_generator.dart';
import '../model/network_simulation.dart';
import '../model/realtime_frame.dart';
import '../model/request_summary.dart';

/// Thrown by service extension handlers when a parameter is missing,
/// malformed, or an operation fails.
class ServiceExtensionException implements Exception {
  const ServiceExtensionException(this.errorCode, this.message);

  /// Error code matching [developer.ServiceExtensionResponse] constants.
  final int errorCode;

  /// Error message explaining the failure.
  final String message;

  @override
  String toString() => 'ServiceExtensionException($errorCode): $message';
}

/// Registers and executes VM Service Protocol extensions (`ext.interceptly.*`)
/// allowing standalone tools (such as `interceptly_mcp`) to interact with
/// the running application via Dart VM Service.
class InterceptlyServiceExtensions {
  InterceptlyServiceExtensions._();

  /// Current schema revision of the Interceptly service extension contract.
  static const int extensionApiVersion = 1;

  static bool _isRegistered = false;
  static bool _enabled = true;
  static InterceptlyEngine? _engine;

  /// Whether extensions have been registered with [developer.registerExtension].
  static bool get isRegistered => _isRegistered;

  /// Whether extension RPC handlers are actively serving requests.
  static bool get isEnabled => _enabled;

  /// Enables serving extension requests.
  static void enable() => _enabled = true;

  /// Disables serving extension requests. When disabled, RPC calls return errors.
  static void disable() => _enabled = false;

  /// Idempotently registers Interceptly service extensions.
  ///
  /// Safe to call multiple times (e.g. during Hot Reload).
  /// Subsequent calls update the active [engine] reference without re-registering
  /// extension names, preventing `ArgumentError` duplicate registration crashes.
  static void register([InterceptlyEngine? engine]) {
    _engine = engine ?? InterceptlyEngine.instance;
    _enabled = true;

    if (_isRegistered) return;
    _isRegistered = true;

    _register(
        'ext.interceptly.ping',
        (params) async => handlePing(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.listRequests',
        (params) async => handleListRequests(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.getRequestDetail',
        (params) => handleGetRequestDetail(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.setNetworkSimulation',
        (params) async => handleSetNetworkSimulation(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.clearTraffic',
        (params) => handleClearTraffic(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.exportCurl',
        (params) => handleExportCurl(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.listRealtimeFrames',
        (params) async => handleListRealtimeFrames(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.getRealtimeFrameDetail',
        (params) => handleGetRealtimeFrameDetail(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));

    _register(
        'ext.interceptly.getTrafficSummary',
        (params) async => handleGetTrafficSummary(
              engine: _engine,
              parameters: params,
              isEnabled: _enabled,
            ));
  }

  static void _register(
    String name,
    Future<Map<String, dynamic>> Function(Map<String, String>) handler,
  ) {
    try {
      developer.registerExtension(name, (method, params) async {
        try {
          final result = await handler(params);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } on ServiceExtensionException catch (e) {
          return developer.ServiceExtensionResponse.error(
            e.errorCode,
            jsonEncode({'errorCode': e.errorCode, 'message': e.message}),
          );
        } catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            jsonEncode({'errorCode': -32000, 'message': e.toString()}),
          );
        }
      });
    } catch (_) {
      // In non-VM environments or if registration fails, ignore silently.
    }
  }

  // ===========================================================================
  // Pure handlers decoupled from dart:developer for testing
  // ===========================================================================

  static void _checkEnabled(bool isEnabled) {
    if (!isEnabled) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly extensions are disabled',
      );
    }
  }

  /// Handles `ext.interceptly.ping`.
  static Map<String, dynamic> handlePing({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    _checkEnabled(isEnabled);

    return {
      'status': 'ok',
      'appName': 'Interceptly',
      'extensionApiVersion': extensionApiVersion,
      'sessionId': engine?.engineId ?? 'unknown',
      'entryCount': engine?.entries.length ?? 0,
      'requestCount': engine?.entries.length ?? 0,
      'droppedCount': engine?.droppedCount ?? 0,
      'networkSimulation': engine?.networkSimulation.name ?? 'none',
    };
  }

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
    _checkEnabled(isEnabled);

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
    _checkEnabled(isEnabled);

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
      totalChars = raw.length;
      if (offset < raw.length) {
        final end = (offset + maxChars).clamp(0, raw.length);
        resBody = raw.substring(offset, end);
        remainingChars = raw.length - end;
        isTruncated = remainingChars > 0;
      } else {
        resBody = '';
        remainingChars = 0;
      }
    }

    if (part == 'request_body') {
      final raw = reqBody ?? '';
      totalChars = raw.length;
      if (offset < raw.length) {
        final end = (offset + maxChars).clamp(0, raw.length);
        reqBody = raw.substring(offset, end);
        remainingChars = raw.length - end;
        isTruncated = remainingChars > 0;
      } else {
        reqBody = '';
        remainingChars = 0;
      }
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

  /// Handles `ext.interceptly.setNetworkSimulation`.
  static Map<String, dynamic> handleSetNetworkSimulation({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    _checkEnabled(isEnabled);

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final profileStr = parameters['profile']?.toLowerCase();
    final enabledParam = parameters['enabled'];
    final latencyMsParam = parameters['latency_ms'];
    final offlineParam = parameters['offline'] == 'true';
    final downloadKbpsParam = parameters['download_kbps'];
    final uploadKbpsParam = parameters['upload_kbps'];

    NetworkSimulationProfile profile;
    if (enabledParam == 'false') {
      profile = NetworkSimulationProfile.none;
    } else if (profileStr != null && profileStr.isNotEmpty) {
      profile = switch (profileStr) {
        'offline' => NetworkSimulationProfile.offlineProfile,
        'slow3g' || 'slow_3g' => NetworkSimulationProfile.slow3G,
        'fast3g' || 'fast_3g' => NetworkSimulationProfile.fast3G,
        '4g' => NetworkSimulationProfile.fourG,
        'wifi' => NetworkSimulationProfile.wifi,
        'custom' => NetworkSimulationProfile(
            name: 'Custom',
            offline: offlineParam,
            latencyMs: int.tryParse(latencyMsParam ?? '0') ?? 0,
            downloadKbps: int.tryParse(downloadKbpsParam ?? '0') ?? 0,
            uploadKbps: int.tryParse(uploadKbpsParam ?? '0') ?? 0,
          ),
        _ => NetworkSimulationProfile.none,
      };
    } else if (latencyMsParam != null ||
        offlineParam ||
        downloadKbpsParam != null ||
        uploadKbpsParam != null) {
      profile = NetworkSimulationProfile(
        name: 'Custom',
        offline: offlineParam,
        latencyMs: int.tryParse(latencyMsParam ?? '0') ?? 0,
        downloadKbps: int.tryParse(downloadKbpsParam ?? '0') ?? 0,
        uploadKbps: int.tryParse(uploadKbpsParam ?? '0') ?? 0,
      );
    } else {
      profile = NetworkSimulationProfile.none;
    }

    engine.setNetworkSimulation(profile);

    return {
      'status': 'ok',
      'networkSimulation': profile.name,
    };
  }

  /// Handles `ext.interceptly.clearTraffic`.
  static Future<Map<String, dynamic>> handleClearTraffic({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    _checkEnabled(isEnabled);

    if (engine != null) {
      await engine.clear();
    }

    return {'status': 'ok'};
  }

  /// Handles `ext.interceptly.exportCurl`.
  static Future<Map<String, dynamic>> handleExportCurl({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    _checkEnabled(isEnabled);

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

  /// Handles `ext.interceptly.listRealtimeFrames`.
  ///
  /// Query parameters:
  /// - `session_id`: the realtime connection ID
  /// - `direction`: 'all' | 'incoming' | 'outgoing'
  /// - `type`: 'all' | 'text' | 'binary' | 'ping' | 'pong' | 'close' | 'ack'
  /// - `since_id`: cursor pagination (returns only frames strictly after [since_id])
  /// - `limit`: maximum number of frames to return (default 50, max 200)
  static Future<Map<String, dynamic>> handleListRealtimeFrames({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    _checkEnabled(isEnabled);

    final sessionId = parameters['session_id'];
    if (sessionId == null || sessionId.trim().isEmpty) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameter: session_id',
      );
    }

    if (engine == null) {
      return {
        'sessionId': sessionId,
        'total': 0,
        'count': 0,
        'frames': const <Map<String, dynamic>>[],
      };
    }

    final allFrames = engine.getRealtimeFrames(sessionId);
    final directionFilter = (parameters['direction'] ?? 'all').toLowerCase();
    final typeFilter = (parameters['type'] ?? 'all').toLowerCase();
    final sinceId = parameters['since_id'];
    final limit =
        int.tryParse(parameters['limit'] ?? '50')?.clamp(1, 200) ?? 50;

    var filtered = allFrames.where((f) {
      if (directionFilter != 'all' && f.direction.name != directionFilter) {
        return false;
      }
      if (typeFilter != 'all' && f.type.name != typeFilter) {
        return false;
      }
      return true;
    }).toList();

    if (sinceId != null) {
      final idx = filtered.indexWhere((f) => f.id == sinceId);
      if (idx != -1 && idx + 1 < filtered.length) {
        filtered = filtered.sublist(idx + 1);
      }
    }

    final paged = filtered
        .take(limit)
        .map((f) => {
              'id': f.id,
              'sessionId': f.sessionId,
              'direction': f.direction.name,
              'type': f.type.name,
              'eventName': f.eventName,
              'payloadSizeBytes': f.payloadSizeBytes,
              'shortPreview': f.shortPreview,
              'timestamp': f.timestamp.toIso8601String(),
            })
        .toList();

    return {
      'sessionId': sessionId,
      'total': allFrames.length,
      'count': paged.length,
      'frames': paged,
    };
  }

  /// Handles `ext.interceptly.getRealtimeFrameDetail`.
  ///
  /// Query parameters:
  /// - `session_id`: the connection session ID
  /// - `frame_id`: the unique frame ID
  /// - `offset`: character offset for reading large payloads (default 0)
  /// - `max_chars`: maximum characters to return before truncation (default 4000)
  static Future<Map<String, dynamic>> handleGetRealtimeFrameDetail({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    _checkEnabled(isEnabled);

    final sessionId = parameters['session_id'];
    final frameId = parameters['frame_id'];
    if (sessionId == null || frameId == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Missing required parameters: session_id and frame_id',
      );
    }

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final frames = engine.getRealtimeFrames(sessionId);
    final frame = frames.cast<RealtimeFrame?>().firstWhere(
          (f) => f?.id == frameId,
          orElse: () => null,
        );

    if (frame == null) {
      throw ServiceExtensionException(
        developer.ServiceExtensionResponse.invalidParams,
        'Frame not found: $frameId in session $sessionId',
      );
    }

    final dynamic rawPayload = await engine.loadRealtimePayload(frame);
    String payloadStr;
    bool isBinary = false;

    if (rawPayload is String) {
      payloadStr = rawPayload;
    } else if (rawPayload is Uint8List) {
      isBinary = true;
      payloadStr = base64Encode(rawPayload);
    } else {
      payloadStr = frame.shortPreview;
    }

    final offset = int.tryParse(parameters['offset'] ?? '0') ?? 0;
    final maxChars = int.tryParse(parameters['max_chars'] ?? '4000') ?? 4000;

    final totalChars = payloadStr.length;
    final safeOffset = offset.clamp(0, totalChars);
    final end = (safeOffset + maxChars).clamp(safeOffset, totalChars);
    final slice = payloadStr.substring(safeOffset, end);
    final isTruncated = end < totalChars;
    final remainingChars = totalChars - end;

    return {
      'id': frame.id,
      'sessionId': frame.sessionId,
      'direction': frame.direction.name,
      'type': frame.type.name,
      'eventName': frame.eventName,
      'isBinary': isBinary,
      'payloadSizeBytes': frame.payloadSizeBytes,
      'timestamp': frame.timestamp.toIso8601String(),
      'payload': slice,
      'isTruncated': isTruncated,
      'totalChars': totalChars,
      'offset': safeOffset,
      'remainingChars': remainingChars,
    };
  }

  /// Handles `ext.interceptly.getTrafficSummary`.
  ///
  /// Query parameters: None (computes aggregate metrics across recorded traffic).
  static Map<String, dynamic> handleGetTrafficSummary({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    _checkEnabled(isEnabled);

    if (engine == null) {
      return {
        'totalRequests': 0,
        'failedRequests': 0,
        'errorRate': 0.0,
        'statusDistribution': const <String, int>{
          '2xx': 0,
          '3xx': 0,
          '4xx': 0,
          '5xx': 0,
          'other': 0,
        },
        'latency': const {
          'p50Ms': 0,
          'p90Ms': 0,
          'p95Ms': 0,
          'p99Ms': 0,
          'avgMs': 0.0,
          'minMs': 0,
          'maxMs': 0,
        },
        'bandwidth': const {
          'totalBytesSent': 0,
          'totalBytesReceived': 0,
          'totalBytes': 0,
        },
        'realtime': const {
          'totalSessions': 0,
          'activeSessions': 0,
        },
        'simulation': 'none',
      };
    }

    final entries = engine.entries;
    final statusDist = <String, int>{
      '2xx': 0,
      '3xx': 0,
      '4xx': 0,
      '5xx': 0,
      'other': 0,
    };
    int totalBytesSent = 0;
    int totalBytesReceived = 0;
    int failedCount = 0;
    final durations = <int>[];

    int realtimeSessionsCount = 0;
    int activeRealtimeSessionsCount = 0;

    for (final e in entries) {
      if (e.method == 'WS' || e.method == 'SIO') {
        realtimeSessionsCount++;
        if (e.durationMs == 0) {
          activeRealtimeSessionsCount++;
        }
        continue;
      }

      final code = e.statusCode;
      if (code >= 200 && code < 300) {
        statusDist['2xx'] = (statusDist['2xx'] ?? 0) + 1;
      } else if (code >= 300 && code < 400) {
        statusDist['3xx'] = (statusDist['3xx'] ?? 0) + 1;
      } else if (code >= 400 && code < 500) {
        statusDist['4xx'] = (statusDist['4xx'] ?? 0) + 1;
        failedCount++;
      } else if (code >= 500 && code < 600) {
        statusDist['5xx'] = (statusDist['5xx'] ?? 0) + 1;
        failedCount++;
      } else {
        statusDist['other'] = (statusDist['other'] ?? 0) + 1;
        if (e.hasError || code == 0) failedCount++;
      }

      totalBytesSent += e.requestSizeBytes;
      totalBytesReceived += e.responseSizeBytes;
      durations.add(e.durationMs);
    }

    durations.sort();

    int p50 = 0, p90 = 0, p95 = 0, p99 = 0, minD = 0, maxD = 0;
    double avgD = 0.0;

    if (durations.isNotEmpty) {
      minD = durations.first;
      maxD = durations.last;
      avgD = durations.reduce((a, b) => a + b) / durations.length;
      p50 = durations[
          (durations.length * 0.50).clamp(0, durations.length - 1).toInt()];
      p90 = durations[
          (durations.length * 0.90).clamp(0, durations.length - 1).toInt()];
      p95 = durations[
          (durations.length * 0.95).clamp(0, durations.length - 1).toInt()];
      p99 = durations[
          (durations.length * 0.99).clamp(0, durations.length - 1).toInt()];
    }

    final totalHttp = durations.length;
    final errorRate = totalHttp > 0 ? (failedCount / totalHttp) : 0.0;

    return {
      'totalRequests': totalHttp,
      'failedRequests': failedCount,
      'errorRate': double.parse(errorRate.toStringAsFixed(4)),
      'statusDistribution': statusDist,
      'latency': {
        'p50Ms': p50,
        'p90Ms': p90,
        'p95Ms': p95,
        'p99Ms': p99,
        'avgMs': double.parse(avgD.toStringAsFixed(1)),
        'minMs': minD,
        'maxMs': maxD,
      },
      'bandwidth': {
        'totalBytesSent': totalBytesSent,
        'totalBytesReceived': totalBytesReceived,
        'totalBytes': totalBytesSent + totalBytesReceived,
      },
      'realtime': {
        'totalSessions': realtimeSessionsCount,
        'activeSessions': activeRealtimeSessionsCount,
      },
      'simulation': engine.networkSimulation.name,
    };
  }
}
