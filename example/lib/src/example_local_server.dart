import 'dart:convert';
import 'dart:io';

/// Lightweight local HTTP server running inside the example app.
///
/// Binds to `127.0.0.1:0` (ephemeral port assigned by OS) to serve both standard
/// API endpoints (replacing external mocks) and stress-test endpoints (heavy JSON,
/// deep nesting, slow responses, large echo POST).
class ExampleLocalServer {
  HttpServer? _server;
  String? _baseUrl;

  /// Current base URL of the local server (e.g. `http://127.0.0.1:54321`).
  String get baseUrl => _baseUrl ?? '';

  /// Whether the server is actively listening.
  bool get isRunning => _server != null;

  /// Starts the server on loopback with an ephemeral port.
  Future<String> start() async {
    if (_server != null) return baseUrl;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _baseUrl = 'http://${_server!.address.host}:${_server!.port}';

    _server!.listen(
      _handleRequest,
      onError: (Object error) {
        // Silently ignore or log internal socket errors during shutdown.
      },
    );

    return baseUrl;
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _baseUrl = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;

    // CORS and JSON headers
    response.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/api/users') {
        _handleUsers(response);
      } else if (path == '/api/error') {
        _handleError(request, response);
      } else if (path == '/api/heavy-list') {
        _handleHeavyList(request, response);
      } else if (path == '/api/extreme-list') {
        _handleExtremeList(request, response);
      } else if (path == '/api/nested') {
        _handleNested(request, response);
      } else if (path == '/api/wide-text') {
        _handleWideText(request, response);
      } else if (path == '/api/echo') {
        await _handleEcho(request, response);
      } else if (path == '/api/delayed') {
        await _handleDelayed(request, response);
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write(
          jsonEncode({
            'error': 'Not Found',
            'path': path,
            'availableEndpoints': [
              '/api/users',
              '/api/error',
              '/api/heavy-list',
              '/api/extreme-list',
              '/api/nested',
              '/api/wide-text',
              '/api/echo',
              '/api/delayed',
            ],
          }),
        );
      }
    } catch (e, stack) {
      response.statusCode = HttpStatus.internalServerError;
      response.write(
        jsonEncode({
          'error': 'Internal Server Error',
          'details': e.toString(),
          'stack': stack.toString(),
        }),
      );
    } finally {
      await response.close();
    }
  }

  void _handleUsers(HttpResponse response) {
    response.statusCode = HttpStatus.ok;
    final users = [
      {
        'id': '1',
        'name': 'Alice Johnson',
        'email': 'alice@example.com',
        'role': 'Admin',
        'avatar': 'https://i.pravatar.cc/150?u=1',
        'createdAt': '2026-01-15T08:00:00Z',
      },
      {
        'id': '2',
        'name': 'Bob Smith',
        'email': 'bob@example.com',
        'role': 'Developer',
        'avatar': 'https://i.pravatar.cc/150?u=2',
        'createdAt': '2026-02-10T09:30:00Z',
      },
      {
        'id': '3',
        'name': 'Carol Williams',
        'email': 'carol@example.com',
        'role': 'Designer',
        'avatar': 'https://i.pravatar.cc/150?u=3',
        'createdAt': '2026-03-01T11:15:00Z',
      },
      {
        'id': '4',
        'name': 'David Brown',
        'email': 'david@example.com',
        'role': 'Product Manager',
        'avatar': 'https://i.pravatar.cc/150?u=4',
        'createdAt': '2026-03-12T14:45:00Z',
      },
      {
        'id': '5',
        'name': 'Eva Davis',
        'email': 'eva@example.com',
        'role': 'QA Engineer',
        'avatar': 'https://i.pravatar.cc/150?u=5',
        'createdAt': '2026-04-05T16:20:00Z',
      },
    ];
    response.write(jsonEncode(users));
  }

  void _handleError(HttpRequest request, HttpResponse response) {
    final statusStr = request.uri.queryParameters['status'];
    final status = int.tryParse(statusStr ?? '') ?? HttpStatus.serviceUnavailable;
    response.statusCode = status;
    response.write(
      jsonEncode({
        'error': 'Service Unavailable',
        'statusCode': status,
        'message': 'Simulated service failure from ExampleLocalServer',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  void _handleHeavyList(HttpRequest request, HttpResponse response) {
    final count = int.tryParse(request.uri.queryParameters['count'] ?? '') ?? 3000;
    response.statusCode = HttpStatus.ok;
    final items = List.generate(count, (i) => _generateItem(i));
    response.write(jsonEncode(items));
  }

  void _handleExtremeList(HttpRequest request, HttpResponse response) {
    // 20,000 items is ~6 MB, safely exceeding Interceptly's 2MB maxUiPreviewBytes limit
    final count = int.tryParse(request.uri.queryParameters['count'] ?? '') ?? 20000;
    response.statusCode = HttpStatus.ok;
    final items = List.generate(count, (i) => _generateItem(i));
    response.write(jsonEncode(items));
  }

  void _handleNested(HttpRequest request, HttpResponse response) {
    final depth = int.tryParse(request.uri.queryParameters['depth'] ?? '') ?? 35;
    response.statusCode = HttpStatus.ok;

    Map<String, dynamic> buildNode(int current, int max) {
      if (current >= max) {
        return {
          'level': current,
          'isLeaf': true,
          'message': 'You reached the deepest node ($max levels deep)!',
          'timestamp': DateTime.now().toIso8601String(),
        };
      }
      return {
        'level': current,
        'title': 'Node at level $current',
        'child': buildNode(current + 1, max),
      };
    }

    final root = {
      'type': 'deeply_nested_tree',
      'targetDepth': depth,
      'tree': buildNode(1, depth),
    };
    response.write(jsonEncode(root));
  }

  void _handleWideText(HttpRequest request, HttpResponse response) {
    final chars = int.tryParse(request.uri.queryParameters['chars'] ?? '') ?? 100000;
    response.statusCode = HttpStatus.ok;

    // Repeating structured sentence so it can be formatted and searched
    const sample = 'The quick brown fox jumps over the lazy dog. 1234567890 ';
    final repeatCount = (chars / sample.length).ceil();
    final bigText = (sample * repeatCount).substring(0, chars);

    response.write(
      jsonEncode({
        'title': 'Wide Text Payload',
        'charLength': chars,
        'sampleData': bigText,
      }),
    );
  }

  Future<void> _handleEcho(HttpRequest request, HttpResponse response) async {
    final content = await utf8.decoder.bind(request).join();
    dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (_) {
      parsed = content;
    }

    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'status': 'echo_received',
        'timestamp': DateTime.now().toIso8601String(),
        'method': request.method,
        'receivedHeaders': request.headers.contentType?.toString(),
        'body': parsed,
      }),
    );
  }

  Future<void> _handleDelayed(HttpRequest request, HttpResponse response) async {
    final delayMs = int.tryParse(request.uri.queryParameters['delayMs'] ?? '') ?? 1500;
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'status': 'delayed_response_complete',
        'delayMs': delayMs,
        'message': 'This request delayed for ${delayMs}ms to test pending state.',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  static Map<String, dynamic> _generateItem(int index) {
    final id = index + 1;
    return {
      'id': 'usr_$id',
      'index': id,
      'guid': 'f81d4fae-7dec-11d0-a765-00a0c91e6bf6_$id',
      'isActive': (id % 2 == 0),
      'name': 'User Number $id',
      'email': 'user_$id@stress-test.example.internal',
      'phone': '+1 (555) 019-${(id % 9000 + 1000)}',
      'address': '$id Enterprise Boulevard, Tech Park, CA',
      'tags': ['stress_test', 'heavy_json', 'item_${id % 10}'],
      'metadata': {
        'score': (id * 1.618) % 100,
        'verified': id % 3 == 0,
        'tier': id % 4 == 0 ? 'platinum' : 'gold',
      },
    };
  }
}
