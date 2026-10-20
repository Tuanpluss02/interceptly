import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_socket_io/interceptly_socket_io.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// The realtime protocol flavor used by the chat page.
enum RealtimeProtocolMode {
  webSocket('WebSocket'),
  socketIo('Socket.IO'),
  parallel('Song song');

  const RealtimeProtocolMode(this.label);
  final String label;
}

/// Model representing a single chat message in the support room.
class ChatMessage {
  final String id;
  final String text;
  final String from;
  final bool isMe;
  final bool isSystem;
  final String? protocol;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.from,
    required this.isMe,
    this.isSystem = false,
    this.protocol,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// A realistic Customer Support Chat page demonstrating bidirectional
/// WebSocket and Socket.IO traffic running in parallel, agent responses,
/// typing indicators, and Interceptly inspection.
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
  RealtimeProtocolMode _protocolMode = RealtimeProtocolMode.parallel;

  // WebSocket state
  InterceptlyWebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _wsConnected = false;
  bool _wsConnecting = false;
  bool _wsTyping = false;
  final List<ChatMessage> _wsMessages = [];

  // Socket.IO state
  io.Socket? _sioSocket;
  InterceptlySocketIoTracker? _sioTracker;
  bool _sioConnected = false;
  bool _sioConnecting = false;
  bool _sioTyping = false;
  final List<ChatMessage> _sioMessages = [];

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool get _isConnected => _wsConnected || _sioConnected;
  bool get _isConnecting => _wsConnecting || _sioConnecting;

  bool get _isTyping {
    switch (_protocolMode) {
      case RealtimeProtocolMode.webSocket:
        return _wsTyping;
      case RealtimeProtocolMode.socketIo:
        return _sioTyping;
      case RealtimeProtocolMode.parallel:
        return _wsTyping || _sioTyping;
    }
  }

  List<ChatMessage> get _activeMessages {
    switch (_protocolMode) {
      case RealtimeProtocolMode.webSocket:
        return _wsMessages;
      case RealtimeProtocolMode.socketIo:
        return _sioMessages;
      case RealtimeProtocolMode.parallel:
        final combined = [..._wsMessages, ..._sioMessages];
        combined.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        return combined;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoConnect) {
      _connectAll();
    }
  }

  @override
  void dispose() {
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

  void _switchProtocolMode(RealtimeProtocolMode mode) {
    if (_protocolMode == mode) return;
    setState(() {
      _protocolMode = mode;
    });
    _scrollToBottom();
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
          _handleWsIncoming(rawData.toString());
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _wsConnected = false;
            _wsConnecting = false;
            _wsTyping = false;
            _wsMessages.add(
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
            _wsMessages.add(
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

  void _handleWsIncoming(String text) {
    if (!mounted) return;

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

      if (type == 'system') {
        setState(() {
          _wsMessages.add(
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
          _wsMessages.add(
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
        _wsMessages.add(
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
          _sioMessages.add(
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

      socket.on('chat_message', (dynamic data) {
        if (!mounted) return;
        if (data is Map) {
          final type = data['type'];
          final text = data['message']?.toString() ?? data.toString();
          final from = data['from']?.toString() ?? 'StormX (Socket.IO)';

          if (type == 'system') {
            setState(() {
              _sioMessages.add(
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
              _sioMessages.add(
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
            _sioMessages.add(
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
  // Message sending logic
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

    final sendToWs = (_protocolMode == RealtimeProtocolMode.webSocket ||
            _protocolMode == RealtimeProtocolMode.parallel) &&
        _wsConnected;
    final sendToSio = (_protocolMode == RealtimeProtocolMode.socketIo ||
            _protocolMode == RealtimeProtocolMode.parallel) &&
        _sioConnected;

    if (sendToWs && _wsChannel != null) {
      final payload = jsonEncode({
        'type': 'chat',
        'message': text,
        'timestamp': now.toIso8601String(),
      });
      _wsChannel!.sink.add(payload);
      _wsMessages.add(
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

    if (sendToSio && _sioSocket != null) {
      _sioSocket!.emit('chat_message', {
        'type': 'chat',
        'message': text,
        'timestamp': now.toIso8601String(),
      });
      _sioMessages.add(
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

  @override
  Widget build(BuildContext context) {
    final messages = _activeMessages;

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

            // Connection indicator badges (WS & Socket.IO song song)
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
                    label: 'WS',
                    isConnected: _wsConnected,
                    isConnecting: _wsConnecting,
                    onTap:
                        _wsConnected ? _disconnectWebSocket : _connectWebSocket,
                  ),
                  const SizedBox(width: 8),
                  _ProtocolStatusChip(
                    label: 'SIO',
                    isConnected: _sioConnected,
                    isConnecting: _sioConnecting,
                    onTap:
                        _sioConnected ? _disconnectSocketIo : _connectSocketIo,
                  ),
                  const Spacer(),
                  // Protocol selector
                  SegmentedButton<RealtimeProtocolMode>(
                    key: const ValueKey('chat_protocol_selector'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: RealtimeProtocolMode.webSocket,
                        label:
                            Text('WebSocket', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.cable, size: 13),
                      ),
                      ButtonSegment(
                        value: RealtimeProtocolMode.socketIo,
                        label:
                            Text('Socket.IO', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.hub_outlined, size: 13),
                      ),
                      ButtonSegment(
                        value: RealtimeProtocolMode.parallel,
                        label:
                            Text('Song song', style: TextStyle(fontSize: 11)),
                        icon: Icon(Icons.compare_arrows, size: 13),
                      ),
                    ],
                    selected: {_protocolMode},
                    onSelectionChanged: (selected) =>
                        _switchProtocolMode(selected.first),
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
                itemCount: messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == messages.length) {
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

                  final msg = messages[index];
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
                            if (msg.protocol != null) ...[
                              _MessageProtocolBadge(protocol: msg.protocol!),
                              const SizedBox(width: 4),
                            ],
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
                            if (_protocolMode ==
                                    RealtimeProtocolMode.parallel &&
                                msg.protocol != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: _MessageProtocolBadge(
                                  protocol: msg.protocol!,
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
                                    if (msg.protocol != null) ...[
                                      const SizedBox(width: 6),
                                      _MessageProtocolBadge(
                                          protocol: msg.protocol!),
                                    ],
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
                      label: Text(
                        _protocolMode == RealtimeProtocolMode.parallel
                            ? '🏓 Ping cả 2'
                            : '🏓 Ping test',
                      ),
                      onPressed: () => _sendMessage('ping'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_bug'),
                      avatar: const Icon(Icons.bug_report, size: 14),
                      label: const Text('🐞 Báo lỗi hệ thống'),
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
                      decoration: InputDecoration(
                        hintText: _protocolMode == RealtimeProtocolMode.parallel
                            ? 'Gửi đồng thời tới cả WS & Socket.IO...'
                            : 'Nhập tin nhắn (${_protocolMode.label})...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: const OutlineInputBorder(
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
            const SizedBox(width: 4),
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
