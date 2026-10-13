import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly_web_socket/interceptly_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Test double [WebSocketChannel] designed for high-concurrency stress testing.
class StressFakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final StreamController<dynamic> _streamController;
  final StreamController<dynamic> _sinkController;
  final Completer<void> _readyCompleter = Completer<void>();

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  int? sinkCloseCode;
  String? sinkCloseReason;
  bool sinkClosed = false;
  final List<dynamic> sentData = [];
  final List<Object> sinkErrors = [];

  StressFakeWebSocketChannel({
    StreamController<dynamic>? streamController,
    StreamController<dynamic>? sinkController,
    this.protocol,
    this.closeCode,
    this.closeReason,
  })  : _streamController = streamController ?? StreamController<dynamic>(),
        _sinkController = sinkController ?? StreamController<dynamic>() {
    _readyCompleter.complete();
    _sinkController.stream.listen(
      sentData.add,
      onError: sinkErrors.add,
    );
  }

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream get stream => _streamController.stream;

  @override
  late final WebSocketSink sink = _StressFakeWebSocketSink(this);

  void emitIncoming(dynamic data) {
    if (!_streamController.isClosed) {
      _streamController.add(data);
    }
  }

  void emitIncomingError(Object error, [StackTrace? stackTrace]) {
    if (!_streamController.isClosed) {
      _streamController.addError(error, stackTrace);
    }
  }

  Future<void> closeServer({int? code, String? reason}) async {
    closeCode = code;
    closeReason = reason;
    if (!_streamController.isClosed) {
      await _streamController.close();
    }
  }
}

class _StressFakeWebSocketSink implements WebSocketSink {
  final StressFakeWebSocketChannel _channel;

  _StressFakeWebSocketSink(this._channel);

  @override
  void add(dynamic data) {
    if (!_channel._sinkController.isClosed) {
      _channel._sinkController.add(data);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_channel._sinkController.isClosed) {
      _channel._sinkController.addError(error, stackTrace);
    }
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    return _channel._sinkController.addStream(stream);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _channel.sinkCloseCode = closeCode;
    _channel.sinkCloseReason = closeReason;
    _channel.sinkClosed = true;
    if (!_channel._sinkController.isClosed) {
      await _channel._sinkController.close();
    }
  }

  @override
  Future<void> get done => _channel._sinkController.done;
}

void main() {
  group('WebSocket Concurrency Stress & Load Tests', () {
    test(
      'Test 1: Multi-channel bidirectional message bombardment (10 channels x 1,000 messages = 10,000 messages)',
      () async {
        final session = InspectorSession(
          settings: const InterceptlySettings(maxFramesPerSession: 1500),
        );
        addTearDown(session.dispose);

        final interceptly = Interceptly(session: session);
        addTearDown(interceptly.dispose);

        const channelCount = 10;
        const messagesPerDirection = 500; // 500 out + 500 in = 1,000 per channel

        final fakes = <StressFakeWebSocketChannel>[];
        final channels = <InterceptlyWebSocketChannel>[];
        final receivedPerChannel = <int, List<dynamic>>{};
        final subs = <StreamSubscription>[];

        for (var c = 0; c < channelCount; c++) {
          final fake = StressFakeWebSocketChannel(protocol: 'stream-$c');
          fakes.add(fake);

          final channel = InterceptlyWebSocketChannel(
            fake,
            uri: Uri.parse('wss://stress.interceptly.dev/channel/$c'),
            sessionId: 'ws-stress-channel-$c',
            interceptly: interceptly,
            headers: {'X-Channel-Index': '$c'},
          );
          channels.add(channel);

          receivedPerChannel[c] = [];
          subs.add(channel.stream.listen(
            (data) => receivedPerChannel[c]!.add(data),
            onError: (_) {},
          ));
        }

        addTearDown(() async {
          for (final sub in subs) {
            await sub.cancel();
          }
        });

        // Bombard all 10 channels simultaneously
        await Future.wait(
          List.generate(channelCount, (chIndex) async {
            final channel = channels[chIndex];
            final fake = fakes[chIndex];

            await Future.wait([
              // Outgoing bombardment: 500 frames (alternating text & binary)
              () async {
                for (var m = 0; m < messagesPerDirection; m++) {
                  if (m.isEven) {
                    channel.sink.add('ch-$chIndex-out-text-$m');
                  } else {
                    channel.sink.add(
                      Uint8List.fromList([chIndex, m & 0xFF, (m >> 8) & 0xFF]),
                    );
                  }
                  if (m % 50 == 0) {
                    await Future<void>.delayed(Duration.zero);
                  }
                }
              }(),
              // Incoming bombardment: 500 frames (alternating text & binary)
              () async {
                for (var m = 0; m < messagesPerDirection; m++) {
                  if (m.isEven) {
                    fake.emitIncoming('ch-$chIndex-in-text-$m');
                  } else {
                    fake.emitIncoming(
                      Uint8List.fromList([0xFF, chIndex, m & 0xFF]),
                    );
                  }
                  if (m % 50 == 0) {
                    await Future<void>.delayed(Duration.zero);
                  }
                }
              }(),
            ]);
          }),
        );

        // Allow microtasks to settle
        await pumpEventQueue();

        // Verify across all 10 channels
        for (var chIndex = 0; chIndex < channelCount; chIndex++) {
          final sessionId = 'ws-stress-channel-$chIndex';
          final frames = session.getRealtimeFrames(sessionId);

          // 1. Total frame count = 1,000 per channel (500 in + 500 out)
          expect(
            frames.length,
            equals(1000),
            reason: 'Channel $chIndex must have recorded all 1,000 frames without loss',
          );

          // 2. Exact balance of directions
          final outgoingFrames = frames
              .where((f) => f.direction == FrameDirection.outgoing)
              .toList();
          final incomingFrames = frames
              .where((f) => f.direction == FrameDirection.incoming)
              .toList();

          expect(outgoingFrames.length, equals(messagesPerDirection));
          expect(incomingFrames.length, equals(messagesPerDirection));

          // 3. Payload integrity for outgoing frames
          for (var m = 0; m < messagesPerDirection; m++) {
            final frame = outgoingFrames[m];
            if (m.isEven) {
              expect(frame.type, equals(FrameType.text));
              expect(frame.textPayload, equals('ch-$chIndex-out-text-$m'));
            } else {
              expect(frame.type, equals(FrameType.binary));
              expect(
                frame.binaryPayload,
                equals(Uint8List.fromList([chIndex, m & 0xFF, (m >> 8) & 0xFF])),
              );
            }
          }

          // 4. Payload integrity for incoming frames
          for (var m = 0; m < messagesPerDirection; m++) {
            final frame = incomingFrames[m];
            if (m.isEven) {
              expect(frame.type, equals(FrameType.text));
              expect(frame.textPayload, equals('ch-$chIndex-in-text-$m'));
            } else {
              expect(frame.type, equals(FrameType.binary));
              expect(
                frame.binaryPayload,
                equals(Uint8List.fromList([0xFF, chIndex, m & 0xFF])),
              );
            }
          }

          // 5. Application layer received all incoming messages
          expect(
            receivedPerChannel[chIndex]!.length,
            equals(messagesPerDirection),
            reason: 'Stream listener must receive all 500 incoming frames',
          );

          // 6. Network socket received all outgoing messages
          expect(
            fakes[chIndex].sentData.length,
            equals(messagesPerDirection),
            reason: 'Underlying socket must receive all 500 outgoing frames',
          );
        }
      },
    );

    test(
      'Test 2: High concurrency stream closing & error recovery under in-flight messages',
      () async {
        final session = InspectorSession();
        addTearDown(session.dispose);

        final interceptly = Interceptly(session: session);
        addTearDown(interceptly.dispose);

        const channelCount = 20;
        final fakes = <StressFakeWebSocketChannel>[];
        final channels = <InterceptlyWebSocketChannel>[];
        final subs = <StreamSubscription>[];

        for (var i = 0; i < channelCount; i++) {
          final fake = StressFakeWebSocketChannel();
          fakes.add(fake);

          final channel = InterceptlyWebSocketChannel(
            fake,
            uri: Uri.parse('wss://closing.example.com/ch/$i'),
            sessionId: 'ws-close-$i',
            interceptly: interceptly,
          );
          channels.add(channel);

          subs.add(channel.stream.listen(
            (_) {},
            onError: (_) {},
          ));
        }

        addTearDown(() async {
          for (final sub in subs) {
            await sub.cancel();
          }
        });

        // Concurrently operate on all 20 channels under heavy load and varying close triggers
        await Future.wait(
          List.generate(channelCount, (idx) async {
            final channel = channels[idx];
            final fake = fakes[idx];

            // Send in-flight frames
            for (var m = 0; m < 50; m++) {
              channel.sink.add('msg-$m');
              fake.emitIncoming('reply-$m');
            }

            if (idx % 4 == 0) {
              // Scenario A: Client sink close (normal 1000)
              await channel.sink.close(1000, 'client normal closure');
            } else if (idx % 4 == 1) {
              // Scenario B: Server stream close (1001 going away)
              await fake.closeServer(code: 1001, reason: 'server going away');
            } else if (idx % 4 == 2) {
              // Scenario C: Simultaneous bidirectional close race condition
              await Future.wait([
                channel.sink.close(1000, 'client race close'),
                fake.closeServer(code: 1001, reason: 'server race close'),
              ]);
            } else {
              // Scenario D: In-flight error injection followed by abnormal close
              fake.emitIncomingError(Exception('remote socket dropped'));
              channel.sink.addError(Exception('local pipe error'));
              await channel.sink.close(1006, 'abnormal closure');
            }
          }),
        );

        await pumpEventQueue();

        // Verify clean lifecycle termination for every channel
        for (var idx = 0; idx < channelCount; idx++) {
          final sessionId = 'ws-close-$idx';
          final entries = session.entries.where((e) => e.id == sessionId).toList();

          expect(
            entries.length,
            equals(1),
            reason: 'Channel $idx connection must be recorded in session',
          );

          final entry = entries.first;
          expect(entry.method, equals('WS'));

          if (idx % 4 == 0) {
            expect(entry.statusCode, equals(1000));
            expect(entry.hasError, isFalse);
          } else if (idx % 4 == 1) {
            expect(entry.statusCode, equals(1001));
            expect(entry.hasError, isTrue); // 1001 is server going away
          } else if (idx % 4 == 2) {
            // One of the close codes was recorded cleanly
            expect([1000, 1001], contains(entry.statusCode));
          } else {
            expect(entry.statusCode, equals(1006));
            expect(entry.hasError, isTrue); // 1006 is abnormal error closure
          }
        }
      },
    );
  });
}
