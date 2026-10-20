import '../engine/interceptly_engine.dart';
import 'service_extension_exception.dart';

/// Handlers for aggregate traffic summary metrics service extensions.
abstract final class SummaryExtensionHandlers {
  /// Handles `ext.interceptly.getTrafficSummary`.
  ///
  /// Query parameters: None (computes aggregate metrics across recorded traffic).
  static Map<String, dynamic> handleGetTrafficSummary({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    checkServiceExtensionEnabled(isEnabled);

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
    int inFlightCount = 0;

    for (final e in entries) {
      if (e.isRealtime) {
        realtimeSessionsCount++;
        if (e.statusCode == 0 && !e.hasError) {
          activeRealtimeSessionsCount++;
        }
        continue;
      }

      final code = e.statusCode;
      if (code == 0 && !e.hasError) {
        inFlightCount++;
        statusDist['other'] = (statusDist['other'] ?? 0) + 1;
        continue;
      }

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
        if (e.hasError) failedCount++;
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
      'totalRequests': totalHttp + inFlightCount,
      'completedRequests': totalHttp,
      'inFlightRequests': inFlightCount,
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
