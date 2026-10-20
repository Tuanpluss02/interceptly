import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Model representing a single chat message in the support room.
class ChatMessage {
  final String id;
  final String text;
  final String from;
  final bool isMe;
  final bool isSystem;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.from,
    required this.isMe,
    this.isSystem = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Model representing a live stock instrument.
class StockItem {
  final String symbol;
  final String name;
  double price;
  String change;
  DateTime lastUpdated;
  bool isUp;

  StockItem({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.lastUpdated,
    this.isUp = true,
  });
}

/// Realtime showcase screen containing two separate sub-tabs:
/// 1. Stock price feed over **WebSocket**.
/// 2. Interactive customer support chat over **Socket.IO**.
class ExampleChatPage extends StatefulWidget {
  final String baseUrl;
  final bool autoConnect;
  final bool showAppBar;

  const ExampleChatPage({
    super.key,
    required this.baseUrl,
    this.autoConnect = true,
    this.showAppBar = false,
  });

  @override
  State<ExampleChatPage> createState() => _ExampleChatPageState();
}

class _ExampleChatPageState extends State<ExampleChatPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ---------------------------------------------------------------------------
  // Tab 1: WebSocket Stock Ticker State
  // ---------------------------------------------------------------------------
  InterceptlyWebSocketChannel? _stockChannel;
  StreamSubscription? _stockSubscription;
  bool _stockConnected = false;
  bool _stockConnecting = false;
  bool _stockPaused = false;
  final Map<String, StockItem> _stocks = {
    'VCB': StockItem(
      symbol: 'VCB',
      name: 'Vietcombank',
      price: 92500.00,
      change: '+1.20%',
      lastUpdated: DateTime.now(),
      isUp: true,
    ),
    'FPT': StockItem(
      symbol: 'FPT',
      name: 'FPT Corp',
      price: 138200.00,
      change: '+2.45%',
      lastUpdated: DateTime.now(),
      isUp: true,
    ),
    'HPG': StockItem(
      symbol: 'HPG',
      name: 'Hòa Phát',
      price: 28600.00,
      change: '-0.85%',
      lastUpdated: DateTime.now(),
      isUp: false,
    ),
    'MWG': StockItem(
      symbol: 'MWG',
      name: 'Thế Giới Di Động',
      price: 65400.00,
      change: '+1.71%',
      lastUpdated: DateTime.now(),
      isUp: true,
    ),
  };
  final List<String> _stockTicksLog = [];

  // ---------------------------------------------------------------------------
  // Tab 2: Socket.IO Support Chat State
  // ---------------------------------------------------------------------------
  io.Socket? _sioSocket;
  InterceptlySocketIoTracker? _sioTracker;
  bool _sioConnected = false;
  bool _sioConnecting = false;
  bool _sioTyping = false;
  final List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.autoConnect) {
      _connectStockWebSocket();
      _connectSocketIo();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disconnectStockWebSocket(updateState: false);
    _disconnectSocketIo(updateState: false);
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  String _formatPrice(double price) {
    final intPrice = price.round();
    final str = intPrice.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return '${buffer.toString()} đ';
  }

  void _scrollToChatBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // WebSocket Stock Ticker Handlers
  // ---------------------------------------------------------------------------
  void _connectStockWebSocket() {
    if (_stockConnected || _stockConnecting) return;

    setState(() {
      _stockConnecting = true;
    });

    try {
      final wsUri =
          Uri.parse('${widget.baseUrl}/ws/stock'.replaceFirst('http', 'ws'));
      final channel = InterceptlyWebSocketChannel.connect(wsUri);
      _stockChannel = channel;

      _stockSubscription = channel.stream.listen(
        (dynamic rawData) {
          _handleStockMessage(rawData);
        },
        onError: (Object _) {
          if (!mounted) return;
          setState(() {
            _stockConnected = false;
            _stockConnecting = false;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _stockConnected = false;
            _stockConnecting = false;
          });
        },
      );

      setState(() {
        _stockConnected = true;
        _stockConnecting = false;
      });
    } catch (_) {
      setState(() {
        _stockConnected = false;
        _stockConnecting = false;
      });
    }
  }

  void _disconnectStockWebSocket({bool updateState = true}) {
    _stockSubscription?.cancel();
    _stockSubscription = null;
    _stockChannel?.sink.close(1000, 'User disconnected');
    _stockChannel = null;
    _stockConnected = false;
    _stockConnecting = false;
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _handleStockMessage(dynamic rawData) {
    if (!mounted || _stockPaused) return;

    if (rawData is List<int>) {
      setState(() {
        _stockTicksLog.insert(
            0, '[Binary] Nhận payload (${rawData.length} bytes)');
        if (_stockTicksLog.length > 50) _stockTicksLog.removeLast();
      });
      return;
    }

    try {
      final text = rawData.toString();
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final type = decoded['type'];

      if (type == 'snapshot' && decoded['stocks'] is List) {
        setState(() {
          for (final item in decoded['stocks'] as List) {
            final sym = item['symbol']?.toString() ?? '';
            final name = item['name']?.toString() ?? sym;
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            final change = item['change']?.toString() ?? '+0.00%';
            _stocks[sym] = StockItem(
              symbol: sym,
              name: name,
              price: price,
              change: change,
              lastUpdated: DateTime.now(),
              isUp: change.startsWith('+'),
            );
          }
          _stockTicksLog.insert(
              0, '[Snapshot] Khởi tạo ${_stocks.keys.join(', ')}');
        });
        return;
      }

      if (type == 'tick') {
        final sym = decoded['symbol']?.toString() ?? '';
        final name = decoded['name']?.toString() ?? sym;
        final price = (decoded['price'] as num?)?.toDouble() ?? 0.0;
        final change = decoded['change']?.toString() ?? '+0.00%';
        final isUp = change.startsWith('+');

        setState(() {
          final existing = _stocks[sym];
          _stocks[sym] = StockItem(
            symbol: sym,
            name: name,
            price: price,
            change: change,
            lastUpdated: DateTime.now(),
            isUp: isUp,
          );
          final diff = existing != null ? (price - existing.price) : 0.0;
          final diffStr = diff >= 0
              ? '+${diff.toStringAsFixed(0)}'
              : diff.toStringAsFixed(0);
          _stockTicksLog.insert(
            0,
            '$sym: ${_formatPrice(price)} ($change, $diffStr)',
          );
          if (_stockTicksLog.length > 50) _stockTicksLog.removeLast();
        });
        return;
      }

      if (type == 'pong') {
        setState(() {
          _stockTicksLog.insert(0, '[Pong] Nhận phản hồi từ WebSocket');
        });
        return;
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  void _pingStockWebSocket() {
    if (_stockConnected && _stockChannel != null) {
      _stockChannel!.sink.add(jsonEncode({'action': 'ping'}));
      setState(() {
        _stockTicksLog.insert(0, '[Send] Ping -> WebSocket');
      });
    }
  }

  void _sendStockBinary() {
    if (_stockConnected && _stockChannel != null) {
      final bytes = Uint8List(1024);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 256;
      }
      _stockChannel!.sink.add(bytes);
      setState(() {
        _stockTicksLog.insert(0, '[Send] 1KB binary buffer -> WebSocket');
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Socket.IO Support Chat Handlers
  // ---------------------------------------------------------------------------
  void _connectSocketIo() {
    if (_sioConnected || _sioConnecting) return;

    setState(() {
      _sioConnecting = true;
    });

    try {
      final socket = io.io(
        widget.baseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );
      _sioSocket = socket;
      _sioTracker = socket.attachInterceptly();

      socket.onConnect((_) {
        if (!mounted) return;
        setState(() {
          _sioConnected = true;
          _sioConnecting = false;
        });
      });

      socket.onDisconnect((_) {
        if (!mounted) return;
        setState(() {
          _sioConnected = false;
          _sioConnecting = false;
          _sioTyping = false;
        });
      });

      socket.onConnectError((err) {
        if (!mounted) return;
        setState(() {
          _sioConnected = false;
          _sioConnecting = false;
          _sioTyping = false;
          _chatMessages.add(
            ChatMessage(
              id: 'err_${DateTime.now().millisecondsSinceEpoch}',
              text: 'Lỗi Socket.IO: $err',
              from: 'System',
              isMe: false,
              isSystem: true,
            ),
          );
        });
        _scrollToChatBottom();
      });

      socket.on('typing', (dynamic data) {
        if (!mounted) return;
        bool isTyping = false;
        if (data is Map && data['status'] == true) {
          isTyping = true;
        }
        setState(() {
          _sioTyping = isTyping;
        });
        _scrollToChatBottom();
      });

      socket.on('chat_message', (dynamic data) {
        if (!mounted) return;
        if (data is Map) {
          final type = data['type'];
          final text = data['message']?.toString() ?? data.toString();
          final from = data['from']?.toString() ?? 'StormX';

          if (type == 'system') {
            setState(() {
              _chatMessages.add(
                ChatMessage(
                  id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
                  text: text,
                  from: 'System',
                  isMe: false,
                  isSystem: true,
                ),
              );
            });
          } else {
            setState(() {
              _sioTyping = false;
              _chatMessages.add(
                ChatMessage(
                  id: 'agent_${DateTime.now().millisecondsSinceEpoch}',
                  text: text,
                  from: from,
                  isMe: false,
                ),
              );
            });
          }
          _scrollToChatBottom();
        } else if (data != null) {
          setState(() {
            _sioTyping = false;
            _chatMessages.add(
              ChatMessage(
                id: 'agent_${DateTime.now().millisecondsSinceEpoch}',
                text: data.toString(),
                from: 'StormX',
                isMe: false,
              ),
            );
          });
          _scrollToChatBottom();
        }
      });

      socket.connect();
    } catch (_) {
      setState(() {
        _sioConnected = false;
        _sioConnecting = false;
      });
    }
  }

  void _disconnectSocketIo({bool updateState = true}) {
    _sioTracker?.detach();
    _sioTracker = null;
    _sioSocket?.disconnect();
    _sioSocket?.dispose();
    _sioSocket = null;
    _sioConnected = false;
    _sioConnecting = false;
    _sioTyping = false;
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _sendChatMessage([String? presetText]) {
    final text = presetText ?? _chatController.text.trim();
    if (text.isEmpty) return;

    if (_sioSocket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng kết nối Socket.IO trước khi gửi tin nhắn!'),
        ),
      );
      return;
    }

    final now = DateTime.now();
    _sioSocket!.emit('chat_message', {
      'type': 'chat',
      'message': text,
      'timestamp': now.toIso8601String(),
    });

    setState(() {
      _chatMessages.add(
        ChatMessage(
          id: 'me_${now.millisecondsSinceEpoch}',
          text: text,
          from: 'Bạn',
          isMe: true,
          timestamp: now,
        ),
      );
    });

    if (presetText == null) {
      _chatController.clear();
    }
    _scrollToChatBottom();
  }

  void _sendChatBinary() {
    if (_sioConnected && _sioSocket != null) {
      final bytes = Uint8List(1024);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 256;
      }
      _sioSocket!.emit('binary_data', bytes);
      setState(() {
        _chatMessages.add(
          ChatMessage(
            id: 'bin_${DateTime.now().millisecondsSinceEpoch}',
            text: 'Gửi 1KB binary payload qua Socket.IO',
            from: 'Bạn',
            isMe: true,
          ),
        );
      });
      _scrollToChatBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab selection header
        Material(
          color: Theme.of(context).cardColor,
          elevation: 1,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Theme.of(context).colorScheme.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Stock (WebSocket)'),
              Tab(text: 'Chat (Socket.IO)'),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildStockTab(),
              _buildChatTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // View 1: Stock Live Ticker (WebSocket)
  // ---------------------------------------------------------------------------
  Widget _buildStockTab() {
    return Column(
      children: [
        // Tab 1 Dedicated Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.candlestick_chart,
                    size: 18, color: Colors.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Thị trường chứng khoán',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          key: const ValueKey('stock_connection_status'),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _stockConnected
                                ? Colors.green
                                : _stockConnecting
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _stockConnected
                              ? 'WebSocket Live'
                              : _stockConnecting
                                  ? 'Đang kết nối...'
                                  : 'Disconnected',
                          style: TextStyle(
                            fontSize: 12,
                            color: _stockConnected
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('stock_toggle_connection'),
                icon: Icon(
                  _stockConnected ? Icons.link_off : Icons.link,
                  size: 20,
                  color: _stockConnected ? Colors.red.shade400 : Colors.teal,
                ),
                tooltip: _stockConnected ? 'Ngắt kết nối WS' : 'Kết nối WS',
                onPressed: () {
                  if (_stockConnected) {
                    _disconnectStockWebSocket();
                  } else {
                    _connectStockWebSocket();
                  }
                },
              ),
            ],
          ),
        ),

        // Live Stock Grid (2x2)
        _buildStockGrid(),

        // Quick Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  key: const ValueKey('chip_ping_ws'),
                  avatar: const Icon(Icons.speed, size: 14),
                  label: const Text('Ping WS'),
                  onPressed: _pingStockWebSocket,
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: Icon(
                    _stockPaused ? Icons.play_arrow : Icons.pause,
                    size: 14,
                    color: _stockPaused ? Colors.green : Colors.orange,
                  ),
                  label: Text(_stockPaused ? 'Tiếp tục' : 'Tạm dừng'),
                  onPressed: () {
                    setState(() {
                      _stockPaused = !_stockPaused;
                    });
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.data_object, size: 14),
                  label: const Text('Send Binary'),
                  onPressed: _sendStockBinary,
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 14),
                  label: const Text('Xóa log'),
                  onPressed: () {
                    setState(() {
                      _stockTicksLog.clear();
                    });
                  },
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 12),

        // Stream Log Feed Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  size: 14, color: Colors.indigo),
              const SizedBox(width: 6),
              Text(
                'WebSocket Stream Log (${_stockTicksLog.length} ticks)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),

        // Log Items
        Expanded(
          child: _stockTicksLog.isEmpty
              ? Center(
                  child: Text(
                    _stockConnected
                        ? 'Đang lắng nghe dữ liệu thị trường từ WebSocket...'
                        : 'WebSocket chưa kết nối.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14.0, vertical: 6.0),
                  itemCount: _stockTicksLog.length,
                  itemBuilder: (context, index) {
                    final log = _stockTicksLog[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'WS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              log,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStockGrid() {
    final items = _stocks.values.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              if (items.isNotEmpty) Expanded(child: _buildStockCard(items[0])),
              const SizedBox(width: 8),
              if (items.length > 1) Expanded(child: _buildStockCard(items[1])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (items.length > 2) Expanded(child: _buildStockCard(items[2])),
              const SizedBox(width: 8),
              if (items.length > 3) Expanded(child: _buildStockCard(items[3])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(StockItem item) {
    final upColor = const Color(0xFF059669);
    final downColor = const Color(0xFFDC2626);
    final color = item.isUp ? upColor : downColor;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.symbol,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: Colors.white,
                      size: 14,
                    ),
                    Text(
                      item.change,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatPrice(item.price),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View 2: Support Chat (Socket.IO)
  // ---------------------------------------------------------------------------
  Widget _buildChatTab() {
    return Column(
      children: [
        // Tab 2 Dedicated Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.indigo.shade100,
                child: const Icon(Icons.support_agent,
                    size: 18, color: Colors.indigo),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'StormX (Support Bot)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          key: const ValueKey('chat_connection_status'),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _sioConnected
                                ? Colors.green
                                : _sioConnecting
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _sioConnected
                              ? 'Socket.IO Online'
                              : _sioConnecting
                                  ? 'Đang kết nối...'
                                  : 'Disconnected',
                          style: TextStyle(
                            fontSize: 12,
                            color: _sioConnected
                                ? Colors.green.shade700
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('chat_toggle_connection'),
                icon: Icon(
                  _sioConnected ? Icons.link_off : Icons.link,
                  size: 20,
                  color: _sioConnected ? Colors.red.shade400 : Colors.indigo,
                ),
                tooltip: _sioConnected
                    ? 'Ngắt kết nối Socket.IO'
                    : 'Kết nối Socket.IO',
                onPressed: () {
                  if (_sioConnected) {
                    _disconnectSocketIo();
                  } else {
                    _connectSocketIo();
                  }
                },
              ),
            ],
          ),
        ),

        // Message list
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding:
                const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
            itemCount: _chatMessages.length + (_sioTyping ? 1 : 0),
            itemBuilder: (context, index) {
              if (_sioTyping && index == _chatMessages.length) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.indigo.shade50,
                        child: const Icon(Icons.support_agent,
                            size: 14, color: Colors.indigo),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.indigo.shade400,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'StormX đang nhập...',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              final msg = _chatMessages[index];
              if (msg.isSystem) {
                return Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'Socket.IO',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            msg.text,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (msg.isMe) {
                return Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8.0, left: 40.0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14.0, vertical: 10.0),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade600,
                      borderRadius: BorderRadius.circular(16.0).copyWith(
                        bottomRight: const Radius.circular(2.0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'Socket.IO',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          msg.text,
                          style: const TextStyle(
                              fontSize: 14.0, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Agent message
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: Colors.indigo.shade100,
                      child: const Icon(Icons.support_agent,
                          size: 15, color: Colors.indigo),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8.0, right: 40.0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14.0, vertical: 10.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(16.0).copyWith(
                            bottomLeft: const Radius.circular(2.0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  msg.from,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade800,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'Socket.IO',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple.shade800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              msg.text,
                              style: const TextStyle(
                                  fontSize: 14.0, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Quick action chips for chat
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  key: const ValueKey('chip_ping'),
                  avatar: const Icon(Icons.speed, size: 14),
                  label: const Text('Ping SIO'),
                  onPressed: () => _sendChatMessage('ping'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_bug'),
                  avatar: const Icon(Icons.bug_report, size: 14),
                  label: const Text('Báo lỗi'),
                  onPressed: () =>
                      _sendChatMessage('Ứng dụng bị lỗi kết nối timeout'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_order'),
                  avatar: const Icon(Icons.local_shipping, size: 14),
                  label: const Text('Kiểm tra đơn hàng'),
                  onPressed: () => _sendChatMessage(
                      'Kiểm tra tình trạng đơn hàng #DH-20261014'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_binary'),
                  avatar: const Icon(Icons.data_object, size: 14),
                  label: const Text('Send Binary'),
                  onPressed: _sendChatBinary,
                ),
              ],
            ),
          ),
        ),

        // Chat input bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat_message_input'),
                  controller: _chatController,
                  decoration: const InputDecoration(
                    hintText: 'Send message',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                  ),
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: const ValueKey('chat_send_button'),
                icon: const Icon(Icons.send_rounded, color: Colors.indigo),
                onPressed: () => _sendChatMessage(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
