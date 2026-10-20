import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

void main() async {
  final requests = <Map<String, dynamic>>[
    {
      'id': '1',
      'method': 'GET',
      'url': 'https://api.example.com/users',
      'statusCode': 200,
      'durationMs': 120,
      'requestSizeBytes': 0,
      'responseSizeBytes': 250,
      'timestamp': DateTime.now().toIso8601String(),
      'hasError': false,
      'requestHeaders': {'Accept': 'application/json'},
      'responseHeaders': {'Content-Type': 'application/json'},
      'requestBody': null,
      'responseBody': '{"users":[{"id":1,"name":"Alice"}]}',
      'curl':
          "curl -X GET 'https://api.example.com/users' -H 'Accept: application/json'",
    },
    {
      'id': '2',
      'method': 'POST',
      'url': 'https://api.example.com/checkout',
      'statusCode': 500,
      'durationMs': 450,
      'requestSizeBytes': 150,
      'responseSizeBytes': 80,
      'timestamp': DateTime.now().toIso8601String(),
      'hasError': true,
      'errorType': 'HttpException',
      'errorMessage': 'Internal Server Error',
      'requestHeaders': {'Content-Type': 'application/json'},
      'responseHeaders': {'Content-Type': 'application/json'},
      'requestBody': '{"cartId":456,"items":[1,2,3]}',
      'responseBody': '{"error":"Internal server database timeout"}',
      'curl':
          "curl -X POST 'https://api.example.com/checkout' -d '{\"cartId\":456}'",
    },
  ];

  var networkSimulation = 'none';

  developer.registerExtension('ext.interceptly.ping', (
    method,
    parameters,
  ) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'ok',
        'extensionApiVersion': 1,
        'appName': 'E2ETestApp',
        'sessionId': 'session-1234',
        'entryCount': requests.length,
        'requestCount': requests.length,
        'droppedCount': 0,
        'networkSimulation': networkSimulation,
      }),
    );
  });

  developer.registerExtension('ext.interceptly.listRequests', (
    method,
    parameters,
  ) async {
    final sinceId = parameters['since_id'];
    var filtered = requests.toList();

    if (sinceId != null && sinceId.isNotEmpty) {
      final idx = filtered.indexWhere((r) => r['id'].toString() == sinceId);
      if (idx >= 0) {
        filtered = filtered.sublist(idx + 1);
      }
    }

    final statusFilter = parameters['status_filter'];
    if (statusFilter == 'failed') {
      filtered =
          filtered.where((r) => (r['statusCode'] as int) >= 400).toList();
    }

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'total': requests.length,
        'count': filtered.length,
        'requests': filtered,
      }),
    );
  });

  developer.registerExtension('ext.interceptly.getRequestDetail', (
    method,
    parameters,
  ) async {
    final id = parameters['id'];
    final req = requests.firstWhere(
      (r) => r['id'].toString() == id,
      orElse: () => throw ArgumentError('Not found: $id'),
    );

    final maxChars = int.tryParse(parameters['max_chars'] ?? '4000') ?? 4000;
    final offset = int.tryParse(parameters['offset'] ?? '0') ?? 0;
    final part = parameters['part'] ?? 'all';

    final body = (req['responseBody'] as String?) ?? '';
    final totalChars = body.length;
    final end = (offset + maxChars).clamp(0, totalChars);
    final slice = offset < totalChars ? body.substring(offset, end) : '';
    final remainingChars = totalChars - end;

    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'id': req['id'],
        'method': req['method'],
        'url': req['url'],
        'statusCode': req['statusCode'],
        'durationMs': req['durationMs'],
        'timestamp': req['timestamp'],
        'requestBody': req['requestBody'],
        'responseBody': slice,
        'isTruncated': remainingChars > 0,
        'totalChars': totalChars,
        'remainingChars': remainingChars,
        'part': part,
      }),
    );
  });

  developer.registerExtension('ext.interceptly.setNetworkSimulation', (
    method,
    parameters,
  ) async {
    final latency = parameters['latency_ms'] ?? '0';
    networkSimulation = 'simulation_latency_${latency}ms';
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'ok', 'networkSimulation': networkSimulation}),
    );
  });

  developer.registerExtension('ext.interceptly.clearTraffic', (
    method,
    parameters,
  ) async {
    requests.clear();
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'status': 'ok'}),
    );
  });

  developer.registerExtension('ext.interceptly.exportCurl', (
    method,
    parameters,
  ) async {
    final id = parameters['id'];
    final req = requests.firstWhere((r) => r['id'].toString() == id);
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'id': id, 'curl': req['curl']}),
    );
  });

  stderr.writeln('E2E_TARGET_APP_READY');

  final timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  ProcessSignal.sigterm.watch().listen((_) {
    timer.cancel();
    exit(0);
  });

  await Completer<void>().future;
}
