import 'dart:convert';
import 'dart:developer' as developer;

import '../engine/interceptly_engine.dart';
import '../export/curl_generator.dart';
import '../model/network_simulation.dart';
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
      'extensionApiVersion': extensionApiVersion,
      'sessionId': engine?.engineId ?? 'unknown',
      'entryCount': engine?.entries.length ?? 0,
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

    final profileStr = parameters['profile']?.toLowerCase() ?? 'none';

    final profile = switch (profileStr) {
      'offline' => NetworkSimulationProfile.offlineProfile,
      'slow3g' || 'slow_3g' => NetworkSimulationProfile.slow3G,
      'fast3g' || 'fast_3g' => NetworkSimulationProfile.fast3G,
      '4g' => NetworkSimulationProfile.fourG,
      'wifi' => NetworkSimulationProfile.wifi,
      'custom' => NetworkSimulationProfile(
          name: 'Custom',
          offline: parameters['offline'] == 'true',
          latencyMs: int.tryParse(parameters['latency_ms'] ?? '0') ?? 0,
          downloadKbps: int.tryParse(parameters['download_kbps'] ?? '0') ?? 0,
          uploadKbps: int.tryParse(parameters['upload_kbps'] ?? '0') ?? 0,
        ),
      _ => NetworkSimulationProfile.none,
    };

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
}
