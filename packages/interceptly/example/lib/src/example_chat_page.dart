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
  final String protocol; // 'WS' or 'Socket.IO'
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.from,
    required this.isMe,
    required this.protocol,
    this.isSystem = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// A realistic Customer Support Chat page demonstrating bidirectional
/// WebSocket and Socket.IO traffic running continuously in parallel,
/// agent responses, typing indicators, live ticker, and Interceptly inspection.
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

class _ExampleChatPageState extends State<ExampleChatPage> {
  // WebSocket state
  InterceptlyWebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _wsConnected = false;
  bool _wsConnecting = false;
  bool _wsTyping = false;

  // Socket.IO state
  io.Socket? _sioSocket;
  InterceptlySocketIoTracker? _sioTracker;
  bool _sioConnected = false;
  bool _sioConnecting = false;
  bool _sioTyping = false;

  // Unified message timeline
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Ticker timer
  Timer? _tickerTimer;
  bool _isTickerRunning = false;

  bool get _isConnected => _wsConnected || _sioConnected;
  bool get _isConnecting => _wsConnecting || _sioConnecting;
  bool get _isTyping => _wsTyping || _sioTyping;

  @override
  void initState() {
    super.initState();
    if (widget.autoConnect) {
      _connectAll();
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _disconnectAll(updateState: false);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _connectAll() {
    _connectWebSocket();
    _connectSocketIo();
  }

  void _disconnectAll({bool updateState = true}) {
    _tickerTimer?.cancel();
    _isTickerRunning = false;
    _disconnectWebSocket(updateState: false);
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
  // WebSocket connection handlers
  // ---------------------------------------------------------------------------
  void _connectWebSocket() {
    if (_wsConnected || _wsConnecting) return;

    setState(() {
      _wsConnecting = true;
    });

    try {
      final wsUri =
          Uri.parse('${widget.baseUrl}/ws/chat'.replaceFirst('http', 'ws'));
      final channel = InterceptlyWebSocketChannel.connect(wsUri);
      _wsChannel = channel;

      _wsSubscription = channel.stream.listen(
        (dynamic rawData) {
          _handleWsIncoming(rawData);
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _wsConnected = false;
            _wsConnecting = false;
            _wsTyping = false;
            _messages.add(
              ChatMessage(
                id: 'err_ws_${DateTime.now().millisecondsSinceEpoch}',
                text: 'Lỗi WebSocket: $error',
                from: 'System',
                isMe: false,
                isSystem: true,
                protocol: 'WS',
              ),
            );
          });
          _scrollToBottom();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _wsConnected = false;
            _wsConnecting = false;
            _wsTyping = false;
            _messages.add(
              ChatMessage(
                id: 'done_ws_${DateTime.now().millisecondsSinceEpoch}',
                text: 'Kết nối WebSocket đã đóng.',
                from: 'System',
                isMe: false,
                isSystem: true,
                protocol: 'WS',
              ),
            );
          });
          _scrollToBottom();
        },
      );

      setState(() {
        _wsConnected = true;
        _wsConnecting = false;
      });
    } catch (_) {
      setState(() {
        _wsConnected = false;
        _wsConnecting = false;
      });
    }
  }

  void _disconnectWebSocket({bool updateState = true}) {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsChannel?.sink.close(1000, 'User disconnected');
    _wsChannel = null;
    _wsConnected = false;
    _wsConnecting = false;
    _wsTyping = false;
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _handleWsIncoming(dynamic rawData) {
    if (!mounted) return;

    if (rawData is List<int>) {
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'bin_ws_${DateTime.now().millisecondsSinceEpoch}',
            text: 'Nhận binary buffer (${rawData.length} bytes) qua WebSocket',
            from: 'StormX (WS)',
            isMe: false,
            isSystem: true,
            protocol: 'WS',
          ),
        );
      });
      _scrollToBottom();
      return;
    }

    final text = rawData.toString();
    try {
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final type = decoded['type'];

      if (type == 'typing') {
        setState(() {
          _wsTyping = decoded['status'] == true;
        });
        _scrollToBottom();
        return;
      }

      if (type == 'ticker_quote') {
        setState(() {
          _messages.add(
            ChatMessage(
              id: 'tick_ws_${DateTime.now().millisecondsSinceEpoch}',
              text: 'Ticker ${decoded['symbol']}: ${decoded['price']}',
              from: 'StormX Ticker',
              isMe: false,
              protocol: 'WS',
            ),
          );
        });
        _scrollToBottom();
        return;
      }

      if (type == 'system') {
        setState(() {
          _messages.add(
            ChatMessage(
              id: 'sys_ws_${DateTime.now().millisecondsSinceEpoch}',
              text: decoded['message']?.toString() ?? text,
              from: 'System',
              isMe: false,
              isSystem: true,
              protocol: 'WS',
            ),
          );
        });
        _scrollToBottom();
        return;
      }

      if (type == 'agent_message') {
        setState(() {
          _wsTyping = false;
          _messages.add(
            ChatMessage(
              id: 'agent_ws_${DateTime.now().millisecondsSinceEpoch}',
              text: decoded['message']?.toString() ?? text,
              from: decoded['from']?.toString() ?? 'StormX (WS)',
              isMe: false,
              protocol: 'WS',
            ),
          );
        });
        _scrollToBottom();
        return;
      }
    } catch (_) {
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'raw_ws_${DateTime.now().millisecondsSinceEpoch}',
            text: text,
            from: 'StormX (WS)',
            isMe: false,
            protocol: 'WS',
          ),
        );
      });
      _scrollToBottom();
    }
  }

  // ---------------------------------------------------------------------------
  // Socket.IO connection handlers
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
          _messages.add(
            ChatMessage(
              id: 'err_sio_${DateTime.now().millisecondsSinceEpoch}',
              text: 'Lỗi Socket.IO: $err',
              from: 'System',
              isMe: false,
              isSystem: true,
              protocol: 'Socket.IO',
            ),
          );
        });
        _scrollToBottom();
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
        _scrollToBottom();
      });

      socket.on('ticker_quote', (dynamic data) {
        if (!mounted) return;
        if (data is Map) {
          setState(() {
            _messages.add(
              ChatMessage(
                id: 'tick_sio_${DateTime.now().millisecondsSinceEpoch}',
                text: 'Ticker ${data['symbol']}: ${data['price']}',
                from: 'StormX Ticker',
                isMe: false,
                protocol: 'Socket.IO',
              ),
            );
          });
          _scrollToBottom();
        }
      });

      socket.on('chat_message', (dynamic data) {
        if (!mounted) return;
        if (data is Map) {
          final type = data['type'];
          final text = data['message']?.toString() ?? data.toString();
          final from = data['from']?.toString() ?? 'StormX (Socket.IO)';

          if (type == 'system') {
            setState(() {
              _messages.add(
                ChatMessage(
                  id: 'sys_sio_${DateTime.now().millisecondsSinceEpoch}',
                  text: text,
                  from: 'System',
                  isMe: false,
                  isSystem: true,
                  protocol: 'Socket.IO',
                ),
              );
            });
          } else {
            setState(() {
              _sioTyping = false;
              _messages.add(
                ChatMessage(
                  id: 'agent_sio_${DateTime.now().millisecondsSinceEpoch}',
                  text: text,
                  from: from,
                  isMe: false,
                  protocol: 'Socket.IO',
                ),
              );
            });
          }
          _scrollToBottom();
        } else if (data != null) {
          setState(() {
            _sioTyping = false;
            _messages.add(
              ChatMessage(
                id: 'agent_sio_${DateTime.now().millisecondsSinceEpoch}',
                text: data.toString(),
                from: 'StormX (Socket.IO)',
                isMe: false,
                protocol: 'Socket.IO',
              ),
            );
          });
          _scrollToBottom();
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

  // ---------------------------------------------------------------------------
  // Message & feature actions
  // ---------------------------------------------------------------------------
  void _sendMessage([String? presetText]) {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng kết nối Realtime trước khi gửi tin nhắn!'),
        ),
      );
      return;
    }

    final now = DateTime.now();

    // Broadcast to WebSocket
    if (_wsConnected && _wsChannel != null) {
      final payload = jsonEncode({
        'type': 'chat',
        'message': text,
        'timestamp': now.toIso8601String(),
      });
      _wsChannel!.sink.add(payload);
      _messages.add(
        ChatMessage(
          id: 'me_ws_${now.millisecondsSinceEpoch}',
          text: text,
          from: 'Bạn',
          isMe: true,
          protocol: 'WS',
          timestamp: now,
        ),
      );
    }

    // Broadcast to Socket.IO
    if (_sioConnected && _sioSocket != null) {
      _sioSocket!.emit('chat_message', {
        'type': 'chat',
        'message': text,
        'timestamp': now.toIso8601String(),
      });
      _messages.add(
        ChatMessage(
          id: 'me_sio_${now.millisecondsSinceEpoch}',
          text: text,
          from: 'Bạn',
          isMe: true,
          protocol: 'Socket.IO',
          timestamp: now,
        ),
      );
    }

    setState(() {});
    if (presetText == null) {
      _textController.clear();
    }
    _scrollToBottom();
  }

  void _toggleLiveTicker() {
    if (_isTickerRunning) {
      _tickerTimer?.cancel();
      _tickerTimer = null;
      setState(() {
        _isTickerRunning = false;
      });
      return;
    }

    setState(() {
      _isTickerRunning = true;
    });

    _tickerTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_isTickerRunning || !mounted) return;

      if (_wsConnected && _wsChannel != null) {
        _wsChannel!.sink.add(jsonEncode({'type': 'ticker'}));
      }
      if (_sioConnected && _sioSocket != null) {
        _sioSocket!.emit('ticker', {'symbol': 'BTC/USDT'});
      }
    });
  }

  void _sendBinaryPayload() {
    final now = DateTime.now();
    final bytes = Uint8List(1024);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = i % 256;
    }

    if (_wsConnected && _wsChannel != null) {
      _wsChannel!.sink.add(bytes);
      _messages.add(
        ChatMessage(
          id: 'bin_tx_ws_${now.millisecondsSinceEpoch}',
          text: 'Gửi 1KB binary payload qua WebSocket',
          from: 'Bạn',
          isMe: true,
          protocol: 'WS',
          timestamp: now,
        ),
      );
    }

    if (_sioConnected && _sioSocket != null) {
      _sioSocket!.emit('binary_data', bytes);
      _messages.add(
        ChatMessage(
          id: 'bin_tx_sio_${now.millisecondsSinceEpoch}',
          text: 'Gửi 1KB binary payload qua Socket.IO',
          from: 'Bạn',
          isMe: true,
          protocol: 'Socket.IO',
          timestamp: now,
        ),
      );
    }

    setState(() {});
    _scrollToBottom();
  }

  void _simulateNetworkDrop() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Simulating network drop... reconnecting in 3 seconds'),
        duration: Duration(seconds: 2),
      ),
    );

    _disconnectAll();

    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _connectAll();
    });
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

            // Dual status bar (WebSocket & Socket.IO song song)
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
                    isConnected: _wsConnected,
                    isConnecting: _wsConnecting,
                    onTap:
                        _wsConnected ? _disconnectWebSocket : _connectWebSocket,
                  ),
                  const SizedBox(width: 8),
                  _ProtocolStatusChip(
                    label: 'Socket.IO',
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

            // Message list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, vertical: 12.0),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == _messages.length) {
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
                                  _wsTyping && _sioTyping
                                      ? 'StormX (WS & Socket.IO đang nhập...)'
                                      : (_wsTyping
                                          ? 'StormX (WS đang nhập...)'
                                          : 'StormX (Socket.IO đang nhập...)'),
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

                  final msg = _messages[index];
                  if (msg.isSystem) {
                    return Container(
                      alignment: Alignment.center,
                      margin: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MessageProtocolBadge(protocol: msg.protocol),
                            const SizedBox(width: 4),
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
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: _MessageProtocolBadge(
                                protocol: msg.protocol,
                                isDark: true,
                              ),
                            ),
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
                            margin:
                                const EdgeInsets.only(bottom: 8.0, right: 40.0),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14.0, vertical: 10.0),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius:
                                  BorderRadius.circular(16.0).copyWith(
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
                                    _MessageProtocolBadge(
                                        protocol: msg.protocol),
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

            // Quick chips
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      key: const ValueKey('chip_ping'),
                      avatar: const Icon(Icons.speed, size: 14),
                      label: const Text('🏓 Ping Both'),
                      onPressed: () => _sendMessage('ping'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_ticker'),
                      avatar: Icon(
                        _isTickerRunning ? Icons.stop : Icons.trending_up,
                        size: 14,
                        color: _isTickerRunning ? Colors.red : Colors.green,
                      ),
                      label: Text(_isTickerRunning
                          ? '⏹ Dừng Ticker'
                          : '📈 Live Ticker'),
                      onPressed: _toggleLiveTicker,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_binary'),
                      avatar: const Icon(Icons.data_object, size: 14),
                      label: const Text('🖼️ Binary 1KB'),
                      onPressed: _sendBinaryPayload,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_drop'),
                      avatar: const Icon(Icons.cloud_off, size: 14),
                      label: const Text('⚡ Drop (3s)'),
                      onPressed: _simulateNetworkDrop,
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_bug'),
                      avatar: const Icon(Icons.bug_report, size: 14),
                      label: const Text('🐞 Báo lỗi'),
                      onPressed: () =>
                          _sendMessage('Ứng dụng bị lỗi kết nối timeout'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_order'),
                      avatar: const Icon(Icons.local_shipping, size: 14),
                      label: const Text('📦 Kiểm tra đơn hàng'),
                      onPressed: () => _sendMessage(
                          'Kiểm tra tình trạng đơn hàng #DH-20261014'),
                    ),
                  ],
                ),
              ),
            ),

            // Chat input bar
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('chat_message_input'),
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Send message',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    key: const ValueKey('chat_send_button'),
                    icon: const Icon(Icons.send_rounded, color: Colors.indigo),
                    onPressed: () => _sendMessage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolStatusChip extends StatelessWidget {
  const _ProtocolStatusChip({
    required this.label,
    required this.isConnected,
    required this.isConnecting,
    required this.onTap,
  });

  final String label;
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

class _MessageProtocolBadge extends StatelessWidget {
  const _MessageProtocolBadge({
    required this.protocol,
    this.isDark = false,
  });

  final String protocol;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isWs = protocol == 'WS';
    final baseColor = isWs ? Colors.cyan : Colors.deepPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.2)
            : baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        protocol,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : baseColor.shade800,
        ),
      ),
    );
  }
}
