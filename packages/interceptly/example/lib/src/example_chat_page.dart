import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
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

/// Model representing a live stock / crypto instrument.
class StockItem {
  final String symbol;
  double price;
  String change;
  DateTime lastUpdated;
  bool isUp;

  StockItem({
    required this.symbol,
    required this.price,
    required this.change,
    required this.lastUpdated,
    this.isUp = true,
  });
}

/// Realtime showcase screen containing two parallel sub-tabs:
/// 1. Stock / Crypto high-frequency price feed over **WebSocket**.
/// 2. Interactive customer support chat over **Socket.IO**.
class ExampleChatPage extends StatefulWidget {
  final String baseUrl;
  final bool autoConnect;
  final bool showAppBar;

  const ExampleChatPage({
    super.key,
    required this.baseUrl,
    this.autoConnect = true,
    this.showAppBar = true,
  });

  @override
  State<ExampleChatPage> createState() => _ExampleChatPageState();
}

class _ExampleChatPageState extends State<ExampleChatPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // ---------------------------------------------------------------------------
  // Tab 1: WebSocket Stock / Crypto Ticker State
  // ---------------------------------------------------------------------------
  InterceptlyWebSocketChannel? _stockChannel;
  StreamSubscription? _stockSubscription;
  bool _stockConnected = false;
  bool _stockConnecting = false;
  bool _stockPaused = false;
  final Map<String, StockItem> _stocks = {
    'BTC/USDT': StockItem(
      symbol: 'BTC/USDT',
      price: 68420.50,
      change: '+3.42%',
      lastUpdated: DateTime.now(),
    ),
    'ETH/USDT': StockItem(
      symbol: 'ETH/USDT',
      price: 3540.20,
      change: '+1.85%',
      lastUpdated: DateTime.now(),
    ),
    'BDS/VND': StockItem(
      symbol: 'BDS/VND',
      price: 28500.00,
      change: '+5.12%',
      lastUpdated: DateTime.now(),
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

  bool get _isConnected => _stockConnected || _sioConnected;
  bool get _isConnecting => _stockConnecting || _sioConnecting;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.autoConnect) {
      _connectAll();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disconnectAll(updateState: false);
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
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

  void _connectAll() {
    _connectStockWebSocket();
    _connectSocketIo();
  }

  void _disconnectAll({bool updateState = true}) {
    _disconnectStockWebSocket(updateState: false);
    _disconnectSocketIo(updateState: false);
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _toggleConnections() {
    if (_isConnected) {
      _disconnectAll();
    } else {
      _connectAll();
    }
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
            0, '🖼️ Nhận binary tick (${rawData.length} bytes)');
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
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            final change = item['change']?.toString() ?? '+0.00%';
            _stocks[sym] = StockItem(
              symbol: sym,
              price: price,
              change: change,
              lastUpdated: DateTime.now(),
              isUp: change.startsWith('+'),
            );
          }
          _stockTicksLog.insert(
              0, '📦 Nhận snapshot ban đầu: ${_stocks.keys.join(', ')}');
        });
        return;
      }

      if (type == 'tick') {
        final sym = decoded['symbol']?.toString() ?? '';
        final price = (decoded['price'] as num?)?.toDouble() ?? 0.0;
        final change = decoded['change']?.toString() ?? '+0.00%';
        final isUp = change.startsWith('+');

        setState(() {
          final existing = _stocks[sym];
          _stocks[sym] = StockItem(
            symbol: sym,
            price: price,
            change: change,
            lastUpdated: DateTime.now(),
            isUp: isUp,
          );
          final diff = existing != null ? (price - existing.price) : 0.0;
          final diffStr = diff >= 0
              ? '+${diff.toStringAsFixed(2)}'
              : diff.toStringAsFixed(2);
          _stockTicksLog.insert(
            0,
            '$sym: \$${price.toStringAsFixed(2)} ($change, $diffStr)',
          );
          if (_stockTicksLog.length > 50) _stockTicksLog.removeLast();
        });
        return;
      }

      if (type == 'pong') {
        setState(() {
          _stockTicksLog.insert(0, '🏓 Nhận Pong từ WebSocket server!');
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
        _stockTicksLog.insert(0, '➡️ Gửi Ping lên WebSocket...');
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
        _stockTicksLog.insert(0, '➡️ Gửi 1KB binary buffer lên WebSocket...');
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
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              titleSpacing: 0,
              title: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    child:
                        const Icon(Icons.support_agent, color: Colors.indigo),
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
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: [
                            Container(
                              key: const ValueKey('chat_connection_status'),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isConnected
                                    ? Colors.green
                                    : _isConnecting
                                        ? Colors.orange
                                        : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isConnected
                                  ? 'Online (Connected)'
                                  : _isConnecting
                                      ? 'Đang kết nối...'
                                      : 'Offline',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isConnected
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  key: const ValueKey('chat_toggle_connection'),
                  icon: Icon(
                    _isConnected ? Icons.link_off : Icons.link,
                    color: _isConnected ? Colors.red.shade400 : Colors.indigo,
                  ),
                  tooltip: _isConnected ? 'Ngắt kết nối' : 'Kết nối lại',
                  onPressed: _toggleConnections,
                ),
                IconButton(
                  key: const ValueKey('chat_open_inspector'),
                  icon: const Icon(Icons.bug_report, color: Colors.indigo),
                  tooltip: 'Mở Interceptly Inspector',
                  onPressed: () => Interceptly.showInspector(context),
                ),
              ],
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.showAppBar)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.indigo.shade100,
                      child: const Icon(Icons.support_agent,
                          size: 16, color: Colors.indigo),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'StormX (Support Bot)',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('chat_connection_status'),
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isConnected
                                  ? Colors.green
                                  : _isConnecting
                                      ? Colors.orange
                                      : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isConnected
                                ? 'Online (Connected)'
                                : (_isConnecting ? 'Connecting' : 'Offline'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('chat_toggle_connection'),
                      icon: Icon(
                        _isConnected ? Icons.link_off : Icons.link,
                        size: 20,
                        color:
                            _isConnected ? Colors.red.shade400 : Colors.indigo,
                      ),
                      tooltip: _isConnected ? 'Ngắt kết nối' : 'Kết nối lại',
                      onPressed: _toggleConnections,
                    ),
                  ],
                ),
              ),

            // Dual connection status banner
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.25),
                border: Border(
                  bottom: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.12),
                  ),
                ),
              ),
              child: Row(
                children: [
                  _ProtocolStatusChip(
                    label: 'WebSocket',
                    protocolType: 'WS Stock',
                    isConnected: _stockConnected,
                    isConnecting: _stockConnecting,
                    onTap: _stockConnected
                        ? _disconnectStockWebSocket
                        : _connectStockWebSocket,
                  ),
                  const SizedBox(width: 8),
                  _ProtocolStatusChip(
                    label: 'Socket.IO',
                    protocolType: 'SIO Chat',
                    isConnected: _sioConnected,
                    isConnecting: _sioConnecting,
                    onTap:
                        _sioConnected ? _disconnectSocketIo : _connectSocketIo,
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sync_alt, size: 12, color: Colors.indigo),
                        SizedBox(width: 4),
                        Text(
                          'Song song',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tab bar: Stock (WebSocket) & Chat (Socket.IO)
            TabBar(
              controller: _tabController,
              labelColor: Colors.indigo,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.indigo,
              indicatorWeight: 3,
              tabs: const [
                Tab(
                  icon: Icon(Icons.trending_up, size: 18),
                  text: '📈 Stock (WebSocket)',
                ),
                Tab(
                  icon: Icon(Icons.chat_bubble_outline, size: 18),
                  text: '💬 Chat (Socket.IO)',
                ),
              ],
            ),

            // TabBar views
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
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // View 1: Stock Live Ticker (WebSocket)
  // ---------------------------------------------------------------------------
  Widget _buildStockTab() {
    return Column(
      children: [
        // Live Price Cards
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: _stocks.values.map((item) {
              return Expanded(
                child: Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: item.isUp
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  color: item.isUp
                      ? Colors.green.withValues(alpha: 0.05)
                      : Colors.red.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.symbol,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '\$${item.price.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: item.isUp
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                        Text(
                          item.change,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: item.isUp
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // Quick Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  key: const ValueKey('chip_ping_ws'),
                  avatar: const Icon(Icons.speed, size: 14),
                  label: const Text('🏓 Ping WS'),
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
                  label: const Text('🖼️ Binary 1KB'),
                  onPressed: _sendStockBinary,
                ),
              ],
            ),
          ),
        ),

        const Divider(height: 16),

        // Stream Log Feed
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.candlestick_chart, size: 14, color: Colors.cyan),
              const SizedBox(width: 6),
              Text(
                'Live WebSocket Stream Log (${_stockTicksLog.length} ticks)',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _stockTicksLog.isEmpty
              ? Center(
                  child: Text(
                    _stockConnected
                        ? 'Đang lắng nghe giá realtime từ WebSocket...'
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
                              color: Colors.cyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'WS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.cyan.shade900,
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

  // ---------------------------------------------------------------------------
  // View 2: Support Chat (Socket.IO)
  // ---------------------------------------------------------------------------
  Widget _buildChatTab() {
    return Column(
      children: [
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
                  label: const Text('🏓 Ping SIO'),
                  onPressed: () => _sendChatMessage('ping'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_bug'),
                  avatar: const Icon(Icons.bug_report, size: 14),
                  label: const Text('🐞 Báo lỗi'),
                  onPressed: () =>
                      _sendChatMessage('Ứng dụng bị lỗi kết nối timeout'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_order'),
                  avatar: const Icon(Icons.local_shipping, size: 14),
                  label: const Text('📦 Kiểm tra đơn hàng'),
                  onPressed: () => _sendChatMessage(
                      'Kiểm tra tình trạng đơn hàng #DH-20261014'),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  key: const ValueKey('chip_binary'),
                  avatar: const Icon(Icons.data_object, size: 14),
                  label: const Text('🖼️ Binary 1KB'),
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

class _ProtocolStatusChip extends StatelessWidget {
  const _ProtocolStatusChip({
    required this.label,
    required this.protocolType,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });

  final String label;
  final String protocolType;
  final bool isConnected;
  final bool isConnecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? Colors.green
        : (isConnecting ? Colors.orange : Colors.grey);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
