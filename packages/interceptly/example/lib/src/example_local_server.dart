import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lightweight local HTTP server running inside the example app.
///
/// Binds to `127.0.0.1:0` (ephemeral port assigned by OS) to serve:
/// 1. Standard RESTful endpoints (GET, POST 201, PUT, PATCH, DELETE 204, 400, 401, 404, 503).
/// 2. Specialized formats (GraphQL, Multipart upload, Binary PNG, Vector SVG).
/// 3. URL filtering test (Analytics endpoint).
/// 4. Stress test endpoints (Heavy list 1MB, Extreme list 6MB, Deeply nested 35 lvls, Wide text, Delayed).
class ExampleLocalServer {
  HttpServer? _server;
  String? _baseUrl;

  /// Current base URL of the local server (e.g. `http://127.0.0.1:54321`).
  String get baseUrl => _baseUrl ?? '';

  /// Current base WebSocket URL (e.g. `ws://127.0.0.1:54321`).
  String get wsUrl => _baseUrl?.replaceFirst('http://', 'ws://') ?? '';

  /// Whether the server is actively listening.
  bool get isRunning => _server != null;

  /// Starts the server on loopback with an ephemeral port.
  Future<String> start() async {
    if (_server != null) return baseUrl;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _baseUrl = 'http://${_server!.address.host}:${_server!.port}';

    _server!.listen(
      _handleRequest,
      onError: (Object error) {},
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
    final path = request.uri.path;

    if (path.startsWith('/socket.io')) {
      await _handleSocketIoRequest(request);
      return;
    }

    if (path == '/ws/chat' && WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleChatSocket(socket);
      } catch (_) {}
      return;
    }

    if (path == '/ws/stock' && WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleStockSocket(socket);
      } catch (_) {}
      return;
    }

    if (path == '/ws/echo' && WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen(
          (dynamic message) {
            socket.add(message);
          },
          onError: (Object error) {
            socket.close(WebSocketStatus.unsupportedData, error.toString());
          },
        );
      } catch (_) {}
      return;
    }

    final response = request.response;

    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods',
          'GET, POST, PUT, PATCH, DELETE, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    try {
      if (path == '/api/users' || path == '/api/users/') {
        await _handleUsersRoot(request, response);
      } else if (path.startsWith('/api/users/')) {
        await _handleUserResource(request, response);
      } else if (path == '/api/graphql') {
        await _handleGraphQL(request, response);
      } else if (path == '/api/upload') {
        await _handleUpload(request, response);
      } else if (path == '/api/image/png') {
        _handleImagePng(response);
      } else if (path == '/api/image/svg') {
        _handleImageSvg(response);
      } else if (path == '/api/analytics/track') {
        _handleAnalytics(request, response);
      } else if (path == '/api/unauthorized') {
        _handleUnauthorized(response);
      } else if (path == '/api/not-found') {
        _handleNotFound(response);
      } else if (path == '/api/bad-request') {
        await _handleBadRequest(request, response);
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
        response.headers.contentType = ContentType.json;
        response.statusCode = HttpStatus.notFound;
        response.write(
          jsonEncode({
            'error': 'Not Found',
            'path': path,
          }),
        );
      }
    } catch (e, stack) {
      response.headers.contentType = ContentType.json;
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

  Future<void> _handleUsersRoot(
      HttpRequest request, HttpResponse response) async {
    response.headers.contentType = ContentType.json;

    if (request.method == 'GET') {
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
      return;
    }

    if (request.method == 'POST') {
      final content = await utf8.decoder.bind(request).join();
      dynamic body;
      try {
        body = jsonDecode(content);
      } catch (_) {
        body = {'raw': content};
      }

      response.statusCode = HttpStatus.created;
      response.write(
        jsonEncode({
          'id': '101',
          'status': 'created',
          'message': 'User successfully created',
          'createdData': body,
          'createdAt': DateTime.now().toIso8601String(),
        }),
      );
      return;
    }

    response.statusCode = HttpStatus.methodNotAllowed;
  }

  Future<void> _handleUserResource(
      HttpRequest request, HttpResponse response) async {
    final id = request.uri.pathSegments.last;
    response.headers.contentType = ContentType.json;

    if (request.method == 'PUT') {
      final content = await utf8.decoder.bind(request).join();
      response.statusCode = HttpStatus.ok;
      response.write(
        jsonEncode({
          'id': id,
          'status': 'updated_full',
          'action': 'PUT (Full Replace)',
          'receivedData': content,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
      return;
    }

    if (request.method == 'PATCH') {
      final content = await utf8.decoder.bind(request).join();
      response.statusCode = HttpStatus.ok;
      response.write(
        jsonEncode({
          'id': id,
          'status': 'patched',
          'action': 'PATCH (Partial Update)',
          'receivedDelta': content,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
      return;
    }

    if (request.method == 'DELETE') {
      response.statusCode = HttpStatus.noContent;
      return;
    }

    response.statusCode = HttpStatus.methodNotAllowed;
  }

  Future<void> _handleGraphQL(
      HttpRequest request, HttpResponse response) async {
    response.headers.contentType = ContentType.json;
    final content = await utf8.decoder.bind(request).join();

    dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (_) {
      parsed = {};
    }

    final query = (parsed is Map ? parsed['query'] : null)?.toString() ?? '';
    final operationName =
        (parsed is Map ? parsed['operationName'] : null)?.toString() ?? '';

    if (operationName == 'GetUser' ||
        query.contains('user(') ||
        query.contains('GetUser')) {
      response.statusCode = HttpStatus.ok;
      response.write(
        jsonEncode({
          'data': {
            'user': {
              'id': 'usr_42',
              'name': 'GraphQL Alice',
              'email': 'alice.gql@example.com',
              'role': 'GRAPHQL_ADMIN',
              'status': 'ACTIVE',
              'projects': [
                {'id': 'prj_1', 'name': 'Interceptly Flutter Inspector'},
                {'id': 'prj_2', 'name': 'GraphQL Performance Suite'},
              ],
            },
          },
        }),
      );
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'data': {
          'mutateUser': {
            'success': true,
            'operationName':
                operationName.isEmpty ? 'AnonymousOperation' : operationName,
            'timestamp': DateTime.now().toIso8601String(),
            'affectedId': 'usr_42',
          },
        },
      }),
    );
  }

  Future<void> _handleUpload(HttpRequest request, HttpResponse response) async {
    response.headers.contentType = ContentType.json;
    final contentType = request.headers.contentType?.toString() ?? 'unknown';

    final bytes = await request
        .fold<List<int>>([], (prev, element) => prev..addAll(element));

    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'status': 'upload_received',
        'contentType': contentType,
        'bytesReceived': bytes.length,
        'message':
            'Inspect the Request tab in Interceptly to see the parsed Multipart summary and file parts!',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  void _handleImagePng(HttpResponse response) {
    response.headers.contentType = ContentType('image', 'png');
    response.statusCode = HttpStatus.ok;
    response.add(_samplePngBytes);
  }

  void _handleImageSvg(HttpResponse response) {
    response.headers.contentType = ContentType('image', 'svg+xml');
    response.statusCode = HttpStatus.ok;
    response.write('''
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 200 200">
  <circle cx="100" cy="100" r="90" fill="#2196F3" opacity="0.15" stroke="#2196F3" stroke-width="4"/>
  <circle cx="100" cy="100" r="50" fill="#2196F3"/>
  <text x="100" y="105" font-family="sans-serif" font-size="14" fill="#ffffff" text-anchor="middle" font-weight="bold">INTERCEPTLY</text>
</svg>
''');
  }

  void _handleAnalytics(HttpRequest request, HttpResponse response) {
    response.headers.contentType = ContentType.json;
    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'status': 'tracked',
        'event': 'user_engagement',
        'note':
            'This request was processed by server, but SHOULD NOT appear in Interceptly if shouldCapture is active.',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  void _handleUnauthorized(HttpResponse response) {
    response.headers.contentType = ContentType.json;
    response.statusCode = HttpStatus.unauthorized;
    response.write(
      jsonEncode({
        'error': 'Unauthorized',
        'statusCode': 401,
        'message': 'Missing or expired Bearer token.',
      }),
    );
  }

  void _handleNotFound(HttpResponse response) {
    response.headers.contentType = ContentType.json;
    response.statusCode = HttpStatus.notFound;
    response.write(
      jsonEncode({
        'error': 'Resource Not Found',
        'statusCode': 404,
        'message': 'The requested user or document does not exist.',
      }),
    );
  }

  Future<void> _handleBadRequest(
      HttpRequest request, HttpResponse response) async {
    response.headers.contentType = ContentType.json;
    response.statusCode = HttpStatus.badRequest;
    response.write(
      jsonEncode({
        'error': 'Validation Failed',
        'statusCode': 400,
        'invalidFields': {
          'email': 'Must be a valid organizational email address.',
          'age': 'Must be an integer >= 18.',
          'terms': 'Terms and conditions must be accepted.',
        },
      }),
    );
  }

  void _handleError(HttpRequest request, HttpResponse response) {
    response.headers.contentType = ContentType.json;
    final statusStr = request.uri.queryParameters['status'];
    final status =
        int.tryParse(statusStr ?? '') ?? HttpStatus.serviceUnavailable;
    response.statusCode = status;
    response.write(
      jsonEncode({
        'error': 'Service Unavailable',
        'statusCode': status,
        'message': 'Simulated server error from ExampleLocalServer',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  }

  void _handleHeavyList(HttpRequest request, HttpResponse response) {
    response.headers.contentType = ContentType.json;
    final count =
        int.tryParse(request.uri.queryParameters['count'] ?? '') ?? 3000;
    response.statusCode = HttpStatus.ok;
    final items = List.generate(count, (i) => _generateItem(i));
    response.write(jsonEncode(items));
  }

  void _handleExtremeList(HttpRequest request, HttpResponse response) {
    response.headers.contentType = ContentType.json;
    final count =
        int.tryParse(request.uri.queryParameters['count'] ?? '') ?? 20000;
    response.statusCode = HttpStatus.ok;
    final items = List.generate(count, (i) => _generateItem(i));
    response.write(jsonEncode(items));
  }

  void _handleNested(HttpRequest request, HttpResponse response) {
    response.headers.contentType = ContentType.json;
    final depth =
        int.tryParse(request.uri.queryParameters['depth'] ?? '') ?? 35;
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
    response.headers.contentType = ContentType.json;
    final chars =
        int.tryParse(request.uri.queryParameters['chars'] ?? '') ?? 100000;
    response.statusCode = HttpStatus.ok;

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
    response.headers.contentType = ContentType.json;
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
        'body': parsed,
      }),
    );
  }

  Future<void> _handleDelayed(
      HttpRequest request, HttpResponse response) async {
    response.headers.contentType = ContentType.json;
    final delayMs =
        int.tryParse(request.uri.queryParameters['delayMs'] ?? '') ?? 1500;
    await Future<void>.delayed(Duration(milliseconds: delayMs));

    response.statusCode = HttpStatus.ok;
    response.write(
      jsonEncode({
        'status': 'delayed_response_complete',
        'delayMs': delayMs,
        'message':
            'This request delayed for ${delayMs}ms to test pending state.',
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

  /// 8x8 transparent/blue pixel valid PNG byte array
  static final Uint8List _samplePngBytes = Uint8List.fromList([
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
    0x00,
    0x00,
    0x00,
    0x08,
    0x00,
    0x00,
    0x00,
    0x08,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
    0x4B,
    0x6D,
    0x29,
    0xDC,
    0x00,
    0x00,
    0x00,
    0x24,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x64,
    0xF8,
    0xCF,
    0xC0,
    0x40,
    0x10,
    0xE7,
    0x7F,
    0x06,
    0x33,
    0xA1,
    0x8D,
    0x6C,
    0x64,
    0x48,
    0x62,
    0x08,
    0x82,
    0x10,
    0x23,
    0x46,
    0x8C,
    0x18,
    0x31,
    0x62,
    0xC4,
    0x88,
    0x11,
    0x23,
    0x00,
    0x00,
    0x00,
    0xFF,
    0xFF,
    0x03,
    0x00,
    0x5A,
    0x91,
    0x0A,
    0x13,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  void _handleStockSocket(WebSocket socket) {
    var vcbPrice = 92500.0;
    var fptPrice = 138200.0;
    var hpgPrice = 28600.0;
    var mwgPrice = 65400.0;

    if (socket.readyState == WebSocket.open) {
      socket.add(jsonEncode({
        'type': 'snapshot',
        'stocks': [
          {
            'symbol': 'VCB',
            'name': 'Vietcombank',
            'price': vcbPrice,
            'change': '+1.20%',
          },
          {
            'symbol': 'FPT',
            'name': 'FPT Corp',
            'price': fptPrice,
            'change': '+2.45%',
          },
          {
            'symbol': 'HPG',
            'name': 'Hòa Phát',
            'price': hpgPrice,
            'change': '-0.85%',
          },
          {
            'symbol': 'MWG',
            'name': 'Thế Giới Di Động',
            'price': mwgPrice,
            'change': '+1.71%',
          },
        ],
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    }

    var tickCount = 0;
    final tickTimer = Timer.periodic(const Duration(milliseconds: 600), (_) {
      if (socket.readyState != WebSocket.open) return;
      tickCount++;

      final symbolIndex = tickCount % 4;
      String symbol;
      String name;
      double price;
      double changeVal;

      if (symbolIndex == 0) {
        vcbPrice += (tickCount % 2 == 0 ? 300.0 : -200.0);
        symbol = 'VCB';
        name = 'Vietcombank';
        price = vcbPrice;
        changeVal = 1.20 + (tickCount % 5) * 0.08;
      } else if (symbolIndex == 1) {
        fptPrice += (tickCount % 2 == 0 ? 500.0 : -300.0);
        symbol = 'FPT';
        name = 'FPT Corp';
        price = fptPrice;
        changeVal = 2.45 + (tickCount % 4) * 0.12;
      } else if (symbolIndex == 2) {
        hpgPrice += (tickCount % 2 == 0 ? -150.0 : 100.0);
        symbol = 'HPG';
        name = 'Hòa Phát';
        price = hpgPrice;
        changeVal = -0.85 - (tickCount % 3) * 0.06;
      } else {
        mwgPrice += (tickCount % 2 == 0 ? 400.0 : -250.0);
        symbol = 'MWG';
        name = 'Thế Giới Di Động';
        price = mwgPrice;
        changeVal = 1.71 + (tickCount % 4) * 0.09;
      }

      socket.add(jsonEncode({
        'type': 'tick',
        'symbol': symbol,
        'name': name,
        'price': price,
        'change':
            '${changeVal >= 0 ? '+' : ''}${changeVal.toStringAsFixed(2)}%',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    });

    socket.listen(
      (dynamic message) {
        final text = message.toString();
        if (text.contains('ping')) {
          socket.add(jsonEncode({
            'type': 'pong',
            'serverTime': DateTime.now().toIso8601String(),
          }));
        }
      },
      onError: (_) => tickTimer.cancel(),
      onDone: () => tickTimer.cancel(),
    );
  }

  void _handleChatSocket(WebSocket socket) {
    socket.add(
      jsonEncode({
        'type': 'system',
        'event': 'connected',
        'room': 'support_channel',
        'message':
            'Kết nối thành công đến Support Hub. Trợ lý StormX đã sẵn sàng!',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );

    Timer(const Duration(milliseconds: 400), () {
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({
            'type': 'agent_message',
            'from': 'StormX (Support Bot)',
            'message':
                'Xin chào! Mình là StormX từ Interceptly. Bạn cần mình hỗ trợ gì hôm nay?',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      }
    });

    final heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({
            'type': 'heartbeat',
            'serverTime': DateTime.now().toIso8601String(),
          }),
        );
      }
    });

    socket.listen(
      (dynamic rawMessage) {
        if (rawMessage is List<int>) {
          socket.add(rawMessage);
          return;
        }

        final text = rawMessage.toString().trim();
        String userQuery = text;
        try {
          final dynamic decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic> && decoded['message'] != null) {
            userQuery = decoded['message'].toString();
          }
        } catch (_) {}

        if (userQuery == 'ticker') {
          final price =
              138200.0 + (DateTime.now().millisecondsSinceEpoch % 1000);
          socket.add(
            jsonEncode({
              'type': 'ticker_quote',
              'from': 'StormX Ticker',
              'symbol': 'FPT',
              'price': '${price.toStringAsFixed(0)} đ',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          return;
        }

        Timer(const Duration(milliseconds: 150), () {
          if (socket.readyState != WebSocket.open) return;
          socket.add(
            jsonEncode({
              'type': 'typing',
              'from': 'StormX',
              'status': true,
            }),
          );

          Timer(const Duration(milliseconds: 400), () {
            if (socket.readyState != WebSocket.open) return;

            final lower = userQuery.toLowerCase();
            String reply;

            if (lower.contains('ping')) {
              reply =
                  'Pong! Kết nối WebSocket đang phản hồi rất nhanh (~10ms).';
            } else if (lower.contains('lỗi') ||
                lower.contains('bug') ||
                lower.contains('error') ||
                lower.contains('fail')) {
              reply =
                  'Để kiểm tra lỗi này, bạn hãy mở Interceptly Inspector, chọn tab Realtime để xem chi tiết frame nhé.';
            } else if (lower.contains('đơn hàng') || lower.contains('order')) {
              reply =
                  'Đơn hàng #DH-20261014 của bạn đã được tiếp nhận và xử lý thành công.';
            } else {
              reply = 'StormX đã nhận được tin nhắn của bạn: "$userQuery".';
            }

            socket.add(
              jsonEncode({
                'type': 'agent_message',
                'from': 'StormX (Support Bot)',
                'message': reply,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }),
            );
          });
        });
      },
      onError: (Object error) {
        heartbeatTimer.cancel();
        socket.close(WebSocketStatus.unsupportedData, error.toString());
      },
      onDone: () {
        heartbeatTimer.cancel();
      },
    );
  }

  Future<void> _handleSocketIoRequest(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        _handleSocketIoSocket(socket);
      } catch (_) {}
      return;
    }

    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      await response.close();
      return;
    }

    if (request.method == 'GET') {
      final sid = 'sio_${DateTime.now().millisecondsSinceEpoch}';
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.text;
      response.write('0${jsonEncode({
            "sid": sid,
            "upgrades": <String>['websocket'],
            "pingInterval": 25000,
            "pingTimeout": 20000,
          })}');
      await response.close();
      return;
    }

    if (request.method == 'POST') {
      response.statusCode = HttpStatus.ok;
      response.write('ok');
      await response.close();
      return;
    }
  }

  void _handleSocketIoSocket(WebSocket socket) {
    final sid = 'sio_${DateTime.now().millisecondsSinceEpoch}';
    socket.add('0${jsonEncode({
          "sid": sid,
          "upgrades": <String>[],
          "pingInterval": 25000,
          "pingTimeout": 20000,
        })}');

    final pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (socket.readyState == WebSocket.open) {
        socket.add('2');
      }
    });

    socket.listen(
      (dynamic rawMessage) {
        if (rawMessage is List<int>) {
          socket.add(rawMessage);
          return;
        }

        final text = rawMessage.toString();
        if (text.isEmpty) return;

        if (text == '3' || text == '3probe') {
          return;
        }

        if (text == '2' || text.startsWith('2probe')) {
          if (text == '2probe') {
            socket.add('3probe');
          } else {
            socket.add('3');
          }
          return;
        }

        if (text == '5') {
          return;
        }

        if (text.startsWith('40')) {
          socket.add('40${jsonEncode({"sid": sid})}');

          Timer(const Duration(milliseconds: 100), () {
            if (socket.readyState != WebSocket.open) return;
            socket.add('42${jsonEncode([
                  'chat_message',
                  {
                    'type': 'system',
                    'from': 'System',
                    'message':
                        'Đã kết nối Socket.IO thành công với StormX Support Bot.',
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                  }
                ])}');

            Timer(const Duration(milliseconds: 300), () {
              if (socket.readyState != WebSocket.open) return;
              socket.add('42${jsonEncode([
                    'chat_message',
                    {
                      'type': 'agent_message',
                      'from': 'StormX (Socket.IO Bot)',
                      'message':
                          'Xin chào! Tôi là StormX trên kết nối Socket.IO. Hãy thử gửi tin nhắn hoặc mở Interceptly Inspector để xem các event Socket.IO nhé!',
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    }
                  ])}');
            });
          });
          return;
        }

        if (text.startsWith('41')) {
          socket.close(WebSocketStatus.normalClosure, 'Client disconnected');
          return;
        }

        if (text.startsWith('42')) {
          final jsonStr = text.substring(2);
          try {
            final dynamic parsed = jsonDecode(jsonStr);
            if (parsed is List && parsed.isNotEmpty) {
              final eventName = parsed[0].toString();
              final eventData = parsed.length > 1 ? parsed[1] : null;

              if (eventName == 'ticker') {
                final price = 68400.0 +
                    (DateTime.now().millisecondsSinceEpoch % 1000) / 10;
                socket.add('42${jsonEncode([
                      'ticker_quote',
                      {
                        'symbol': 'BTC/USDT',
                        'price': '\$${price.toStringAsFixed(2)}',
                        'timestamp': DateTime.now().millisecondsSinceEpoch,
                      }
                    ])}');
                return;
              }

              if (eventName == 'binary_data') {
                final count = eventData is List ? eventData.length : 1024;
                socket.add('42${jsonEncode([
                      'chat_message',
                      {
                        'type': 'agent_message',
                        'from': 'StormX (Socket.IO Bot)',
                        'message':
                            'Nhận thành công binary payload ($count bytes) qua Socket.IO!',
                        'timestamp': DateTime.now().millisecondsSinceEpoch,
                      }
                    ])}');
                return;
              }

              if (eventName == 'chat_message') {
                String userQuery = '';
                if (eventData is Map && eventData['message'] != null) {
                  userQuery = eventData['message'].toString();
                } else if (eventData != null) {
                  userQuery = eventData.toString();
                }

                Timer(const Duration(milliseconds: 150), () {
                  if (socket.readyState != WebSocket.open) return;
                  socket.add('42${jsonEncode([
                        'typing',
                        {
                          'from': 'StormX (Socket.IO Bot)',
                          'status': true,
                        }
                      ])}');

                  Timer(const Duration(milliseconds: 400), () {
                    if (socket.readyState != WebSocket.open) return;

                    final lower = userQuery.toLowerCase();
                    String reply;
                    if (lower.contains('ping')) {
                      reply =
                          '🏓 Pong từ Socket.IO! Handshake và event frame hoạt động chuẩn xác.';
                    } else if (lower.contains('lỗi') ||
                        lower.contains('bug') ||
                        lower.contains('error')) {
                      reply =
                          'Mở Interceptly Inspector -> Realtime Tab để xem chi tiết packet Socket.IO nhé!';
                    } else if (lower.contains('đơn hàng') ||
                        lower.contains('order')) {
                      reply =
                          'Đơn hàng Socket.IO #SIO-20261020 của bạn đang ở trạng thái chuẩn bị giao.';
                    } else {
                      reply =
                          'StormX (Socket.IO) đã nhận được tin nhắn: "$userQuery".';
                    }

                    socket.add('42${jsonEncode([
                          'chat_message',
                          {
                            'type': 'agent_message',
                            'from': 'StormX (Socket.IO Bot)',
                            'message': reply,
                            'timestamp': DateTime.now().millisecondsSinceEpoch,
                          }
                        ])}');
                  });
                });
              }
            }
          } catch (_) {}
        }
      },
      onError: (Object _) {
        pingTimer.cancel();
        socket.close(WebSocketStatus.unsupportedData);
      },
      onDone: () {
        pingTimer.cancel();
      },
    );
  }
}
