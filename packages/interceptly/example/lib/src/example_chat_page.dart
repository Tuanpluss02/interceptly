import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';

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

/// A realistic Customer Support Chat page demonstrating bidirectional
/// WebSocket traffic, agent responses, typing indicators, and Interceptly inspection.
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
  InterceptlyWebSocketChannel? _channel;
  StreamSubscription? _subscription;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isTyping = false;

  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.autoConnect) {
      _connect();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close(1000, 'Page disposed');
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

  void _connect() {
    if (_isConnected || _isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      final wsUri =
          Uri.parse('${widget.baseUrl}/ws/chat'.replaceFirst('http', 'ws'));
      final channel = InterceptlyWebSocketChannel.connect(wsUri);
      _channel = channel;

      _subscription = channel.stream.listen(
        (dynamic rawData) {
          _handleIncoming(rawData.toString());
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _isTyping = false;
            _messages.add(
              ChatMessage(
                id: 'err_${DateTime.now().millisecondsSinceEpoch}',
                text: 'Lỗi kết nối socket: $error',
                from: 'System',
                isMe: false,
                isSystem: true,
              ),
            );
          });
          _scrollToBottom();
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _isConnected = false;
            _isConnecting = false;
            _isTyping = false;
            _messages.add(
              ChatMessage(
                id: 'done_${DateTime.now().millisecondsSinceEpoch}',
                text: 'Kết nối WebSocket đã đóng.',
                from: 'System',
                isMe: false,
                isSystem: true,
              ),
            );
          });
          _scrollToBottom();
        },
      );

      setState(() {
        _isConnected = true;
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
      });
    }
  }

  void _disconnect() {
    _subscription?.cancel();
    _channel?.sink.close(1000, 'User disconnected');
    setState(() {
      _isConnected = false;
      _isConnecting = false;
      _isTyping = false;
    });
  }

  void _handleIncoming(String text) {
    if (!mounted) return;

    try {
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final type = decoded['type'];

      if (type == 'typing') {
        setState(() {
          _isTyping = decoded['status'] == true;
        });
        _scrollToBottom();
        return;
      }

      if (type == 'system') {
        setState(() {
          _messages.add(
            ChatMessage(
              id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
              text: decoded['message']?.toString() ?? text,
              from: 'System',
              isMe: false,
              isSystem: true,
            ),
          );
        });
        _scrollToBottom();
        return;
      }

      if (type == 'agent_message') {
        setState(() {
          _isTyping = false;
          _messages.add(
            ChatMessage(
              id: 'agent_${DateTime.now().millisecondsSinceEpoch}',
              text: decoded['message']?.toString() ?? text,
              from: decoded['from']?.toString() ?? 'StormX',
              isMe: false,
            ),
          );
        });
        _scrollToBottom();
        return;
      }
    } catch (_) {
      // Fallback for non-JSON or plain string echo
      setState(() {
        _messages.add(
          ChatMessage(
            id: 'raw_${DateTime.now().millisecondsSinceEpoch}',
            text: text,
            from: 'StormX',
            isMe: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  void _sendMessage([String? presetText]) {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty) return;

    if (!_isConnected || _channel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng kết nối WebSocket trước khi gửi tin nhắn!')),
      );
      return;
    }

    final payload = jsonEncode({
      'type': 'chat',
      'message': text,
      'timestamp': DateTime.now().toIso8601String(),
    });

    _channel!.sink.add(payload);

    setState(() {
      _messages.add(
        ChatMessage(
          id: 'me_${DateTime.now().millisecondsSinceEpoch}',
          text: text,
          from: 'Bạn',
          isMe: true,
        ),
      );
    });

    if (presetText == null) {
      _textController.clear();
    }
    _scrollToBottom();
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
                    child: const Icon(Icons.support_agent, color: Colors.indigo),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'StormX (Support Bot)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                                color: _isConnected ? Colors.green.shade700 : Colors.grey.shade600,
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
                  onPressed: _isConnected ? _disconnect : _connect,
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.indigo.shade100,
                      child: const Icon(Icons.support_agent, size: 16, color: Colors.indigo),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'StormX',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          Container(
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
                            _isConnected ? 'Online' : (_isConnecting ? 'Connecting' : 'Offline'),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _isConnected ? Icons.link_off : Icons.link,
                        size: 20,
                        color: _isConnected ? Colors.red.shade400 : Colors.indigo,
                      ),
                      tooltip: _isConnected ? 'Ngắt kết nối' : 'Kết nối lại',
                      onPressed: _isConnected ? _disconnect : _connect,
                    ),
                  ],
                ),
              ),

            // Message list
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isTyping && index == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.indigo.shade100,
                            child: const Icon(Icons.support_agent, size: 14, color: Colors.indigo),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            key: const ValueKey('chat_typing_indicator'),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'StormX đang gõ...',
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final msg = _messages[index];

                  if (msg.isSystem) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                        child: Text(
                          msg.text,
                          style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                        ),
                      ),
                    );
                  }

                  if (msg.isMe) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8.0, left: 50.0),
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                        decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(16.0).copyWith(
                            bottomRight: const Radius.circular(2.0),
                          ),
                        ),
                        child: Text(
                          msg.text,
                          style: const TextStyle(color: Colors.white, fontSize: 14.0),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.indigo.shade100,
                          child: const Icon(Icons.support_agent, size: 15, color: Colors.indigo),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8.0, right: 40.0),
                            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
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
                                Text(
                                  msg.from,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  msg.text,
                                  style: const TextStyle(fontSize: 14.0, color: Colors.black87),
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
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      key: const ValueKey('chip_ping'),
                      avatar: const Icon(Icons.speed, size: 14),
                      label: const Text('🏓 Ping test'),
                      onPressed: () => _sendMessage('ping'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_bug'),
                      avatar: const Icon(Icons.bug_report, size: 14),
                      label: const Text('🐞 Báo lỗi hệ thống'),
                      onPressed: () => _sendMessage('Ứng dụng bị lỗi kết nối timeout'),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      key: const ValueKey('chip_order'),
                      avatar: const Icon(Icons.local_shipping, size: 14),
                      label: const Text('📦 Kiểm tra đơn hàng'),
                      onPressed: () => _sendMessage('Kiểm tra tình trạng đơn hàng #DH-20261014'),
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
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Nhập tin nhắn hỗ trợ...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
