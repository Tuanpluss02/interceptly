@Tags(['stress'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebSocket Concurrency Stress & Load Tests', () {
    test(
      'Test 1: Multi-channel bidirectional message bombardment (10 channels x 1,000 messages = 10,000 messages)',
      () async {
        await InspectorSession.resetForTesting();
        final session = InspectorSession.instance;
        session.configureSession(
          const InterceptlySettings(
            maxFramesPerSession: 1500,
            maxTotalRealtimeFrames: 15000,
          ),
        );
        addTearDown(() async {
          await session.dispose();
          await InspectorSession.resetForTesting();
        });

        const channelCount = 10;
        const messagesPerDirection =
            500; // 500 out + 500 in = 1,000 per channel

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
            reason:
                'Channel $chIndex must have recorded all 1,000 frames without loss',
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
                equals(
                    Uint8List.fromList([chIndex, m & 0xFF, (m >> 8) & 0xFF])),
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
        await InspectorSession.resetForTesting();
        final session = InspectorSession.instance;
        addTearDown(() async {
          await session.dispose();
          await InspectorSession.resetForTesting();
        });

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
          final entries =
              session.entries.where((e) => e.id == sessionId).toList();

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

    test(
      'Test 3: Massive multi-connection stress test (25 active + 15 closed, mixed payloads 100B - 200KB, zero offset corruption, closed session eviction priority)',
      () async {
        await InspectorSession.resetForTesting();
        final session = InspectorSession.instance;

        const maxTotalRealtimeFrames = 400;
        session.configureSession(
          const InterceptlySettings(
            maxFramesPerSession: 200,
            maxTotalRealtimeFrames: maxTotalRealtimeFrames,
            realtimeBodyOffloadThreshold: 32 * 1024,
            persistToDisk: true,
          ),
        );
        addTearDown(() async {
          await session.dispose();
          await InspectorSession.resetForTesting();
        });

        const closedCount = 15;
        const activeCount = 25;

        // Deterministic text generator with embedded key and target size
        String makeTextPayload(String key, int targetBytes) {
          final prefix = 'TAG:$key:LEN:$targetBytes:';
          if (targetBytes <= prefix.length) {
            return prefix.substring(0, targetBytes);
          }
          final fill = 'X' * (targetBytes - prefix.length);
          return '$prefix$fill';
        }

        // Deterministic binary generator with magic header and embedded key
        Uint8List makeBinaryPayload(String key, int targetBytes) {
          final data = Uint8List(targetBytes);
          final bd = ByteData.sublistView(data);
          data[0] = 0xAA;
          data[1] = 0xBB;
          data[2] = 0xCC;
          data[3] = 0xDD;
          bd.setUint32(4, targetBytes);
          final keyBytes = utf8.encode(key);
          data[8] = keyBytes.length;
          for (var i = 0; i < keyBytes.length && i < 20; i++) {
            data[9 + i] = keyBytes[i];
          }
          final seed = key.hashCode.abs() & 0xFF;
          for (var i = 29; i < targetBytes; i++) {
            data[i] = (seed + (i * 17)) & 0xFF;
          }
          return data;
        }

        // Mixed payload sizes spanning 100 B to 200 KB (crossing the 32 KB threshold)
        final mixedSizes = <int>[
          100, // 100 B (in-memory)
          500, // 500 B (in-memory)
          2 * 1024, // 2 KB (in-memory)
          8 * 1024, // 8 KB (in-memory)
          16 * 1024, // 16 KB (in-memory)
          35 * 1024, // 35 KB (offloaded to disk)
          48 * 1024, // 48 KB (offloaded to disk)
          64 * 1024, // 64 KB (offloaded to disk)
          100 * 1024, // 100 KB (offloaded to disk)
          130 * 1024, // 130 KB (offloaded to disk)
          160 * 1024, // 160 KB (offloaded to disk)
          200 * 1024, // 200 KB (offloaded to disk)
        ];

        final payloadStore = <String, dynamic>{};
        final subs = <StreamSubscription>[];
        addTearDown(() async {
          for (final sub in subs) {
            await sub.cancel();
          }
        });

        // ==========================================
        // Phase A: Setup and traffic 15 closed connections
        // ==========================================
        final closedFakes = <StressFakeWebSocketChannel>[];
        final closedChannels = <InterceptlyWebSocketChannel>[];
        var closedIncomingCount = 0;
        final closedIncomingCompleter = Completer<void>();
        const closedMessagesPerChannel = 6;
        const closedIncomingExpected =
            closedCount * (closedMessagesPerChannel ~/ 2);

        for (var c = 0; c < closedCount; c++) {
          final fake = StressFakeWebSocketChannel(protocol: 'closed-$c');
          closedFakes.add(fake);
          final channel = InterceptlyWebSocketChannel(
            fake,
            uri: Uri.parse('wss://stress.interceptly.dev/closed/$c'),
            sessionId: 'ws-closed-$c',
          );
          closedChannels.add(channel);
          subs.add(channel.stream.listen((_) {
            closedIncomingCount++;
            if (closedIncomingCount >= closedIncomingExpected &&
                !closedIncomingCompleter.isCompleted) {
              closedIncomingCompleter.complete();
            }
          }, onError: (_) {}));
        }

        // Send initial traffic through the 15 connections (6 messages each = 90 frames total)
        await Future.wait(
          List.generate(closedCount, (c) async {
            final channel = closedChannels[c];
            final fake = closedFakes[c];
            for (var m = 0; m < closedMessagesPerChannel; m++) {
              final size = mixedSizes[m % mixedSizes.length];
              final isText = m.isEven;
              final key = 'closed-c$c-m$m';
              if (m % 2 == 0) {
                final dynamic payload = isText
                    ? makeTextPayload(key, size)
                    : makeBinaryPayload(key, size);
                payloadStore[key] = payload;
                channel.sink.add(payload);
              } else {
                final dynamic payload = isText
                    ? makeTextPayload(key, size)
                    : makeBinaryPayload(key, size);
                payloadStore[key] = payload;
                fake.emitIncoming(payload);
              }
            }
          }),
        );

        await closedIncomingCompleter.future;
        await session.flushRealtimeBodyStoreForTesting();
        await pumpEventQueue();

        // Verify initial frames were recorded
        var closedInitialTotal = 0;
        for (var c = 0; c < closedCount; c++) {
          final count = session.getRealtimeFrames('ws-closed-$c').length;
          expect(count, equals(closedMessagesPerChannel));
          closedInitialTotal += count;
        }
        expect(
          closedInitialTotal,
          equals(closedCount * closedMessagesPerChannel),
        );
        expect(
            session.totalRealtimeFramesForTesting, equals(closedInitialTotal));

        // Close all 15 connections (half via client sink, half via server stream)
        await Future.wait(
          List.generate(closedCount, (c) async {
            if (c.isEven) {
              await closedChannels[c].sink.close(1000, 'client closed');
            } else {
              await closedFakes[c]
                  .closeServer(code: 1000, reason: 'server closed');
            }
          }),
        );

        await pumpEventQueue();

        // ==========================================
        // Phase B: Concurrently bombard 25 active connections
        // ==========================================
        final activeFakes = <StressFakeWebSocketChannel>[];
        final activeChannels = <InterceptlyWebSocketChannel>[];
        var activeIncomingCount = 0;
        final activeIncomingCompleter = Completer<void>();
        const activeMessagesPerDirection = 12;
        const activeIncomingExpected = activeCount * activeMessagesPerDirection;

        for (var c = 0; c < activeCount; c++) {
          final fake = StressFakeWebSocketChannel(protocol: 'active-$c');
          activeFakes.add(fake);
          final channel = InterceptlyWebSocketChannel(
            fake,
            uri: Uri.parse('wss://stress.interceptly.dev/active/$c'),
            sessionId: 'ws-active-$c',
          );
          activeChannels.add(channel);
          subs.add(channel.stream.listen((_) {
            activeIncomingCount++;
            if (activeIncomingCount >= activeIncomingExpected &&
                !activeIncomingCompleter.isCompleted) {
              activeIncomingCompleter.complete();
            }
          }, onError: (_) {}));
        }

        // Bombard across all 25 active channels concurrently
        // 24 messages per channel (12 out + 12 in) = 600 frames total.
        // 90 (closed) + 600 (active) = 690 total frames attempted.
        // Cap is 400. This exerts heavy eviction pressure!
        await Future.wait(
          List.generate(activeCount, (c) async {
            final channel = activeChannels[c];
            final fake = activeFakes[c];

            await Future.wait([
              // Outgoing bombardment
              () async {
                for (var m = 0; m < activeMessagesPerDirection; m++) {
                  final size = mixedSizes[m % mixedSizes.length];
                  final isText = m.isEven;
                  final key = 'active-c$c-out-m$m';
                  final dynamic payload = isText
                      ? makeTextPayload(key, size)
                      : makeBinaryPayload(key, size);
                  payloadStore[key] = payload;
                  channel.sink.add(payload);
                  if (m % 3 == 0) {
                    await Future<void>.delayed(Duration.zero);
                  }
                }
              }(),
              // Incoming bombardment
              () async {
                for (var m = 0; m < activeMessagesPerDirection; m++) {
                  final size = mixedSizes[(m + 6) % mixedSizes.length];
                  final isText = m.isOdd;
                  final key = 'active-c$c-in-m$m';
                  final dynamic payload = isText
                      ? makeTextPayload(key, size)
                      : makeBinaryPayload(key, size);
                  payloadStore[key] = payload;
                  fake.emitIncoming(payload);
                  if (m % 3 == 0) {
                    await Future<void>.delayed(Duration.zero);
                  }
                }
              }(),
            ]);
          }),
        );

        // Allow microtasks and sequential disk offloading queue to settle
        await activeIncomingCompleter.future;
        await session.flushRealtimeBodyStoreForTesting();
        await pumpEventQueue();
        await session.flushRealtimeBodyStoreForTesting();

        // ==========================================
        // Phase C: Assertions
        // ==========================================

        // 1. Total frame count across the system is strictly capped at maxTotalRealtimeFrames
        expect(
          session.totalRealtimeFramesForTesting,
          lessThanOrEqualTo(maxTotalRealtimeFrames),
          reason:
              'Global frame count must never exceed coordinator budget ($maxTotalRealtimeFrames)',
        );

        var countedAcrossBuffers = 0;
        for (var c = 0; c < closedCount; c++) {
          countedAcrossBuffers +=
              session.getRealtimeFrames('ws-closed-$c').length;
        }
        for (var c = 0; c < activeCount; c++) {
          countedAcrossBuffers +=
              session.getRealtimeFrames('ws-active-$c').length;
        }
        expect(countedAcrossBuffers,
            equals(session.totalRealtimeFramesForTesting));

        // 2. Closed sessions are evicted first under global memory pressure
        // Because 690 > 400, all 90 frames of the 15 closed sessions must be fully evicted
        for (var c = 0; c < closedCount; c++) {
          final frames = session.getRealtimeFrames('ws-closed-$c');
          expect(
            frames.isEmpty,
            isTrue,
            reason:
                'Closed session ws-closed-$c must be prioritized for eviction under memory pressure',
          );
        }

        // Active sessions retain frames
        for (var c = 0; c < activeCount; c++) {
          final frames = session.getRealtimeFrames('ws-active-$c');
          expect(
            frames.isNotEmpty,
            isTrue,
            reason: 'Active session ws-active-$c must retain frames',
          );
        }

        // 3. Zero offset corruption in RealtimeBodyStore:
        // Reading payloads back via session.loadRealtimePayload yields exact data for all retained frames.
        var memoryFramesVerified = 0;
        var offloadedFramesVerified = 0;

        for (var c = 0; c < activeCount; c++) {
          final frames = session.getRealtimeFrames('ws-active-$c');
          for (final frame in frames) {
            String? foundKey;
            final loaded = await session.loadRealtimePayload(frame);

            expect(
              loaded,
              isNotNull,
              reason: 'Payload must load cleanly without failure',
            );
            expect(
              loaded.toString().startsWith('[Error'),
              isFalse,
              reason: 'Payload loading must not fail with error: $loaded',
            );
            expect(
              loaded.toString().startsWith('[Payload expired'),
              isFalse,
              reason: 'Payload must not expire prematurely: $loaded',
            );

            if (frame.type == FrameType.text) {
              expect(loaded, isA<String>());
              final text = loaded as String;
              expect(text.length, equals(frame.payloadSizeBytes));
              if (text.startsWith('TAG:')) {
                final endIdx = text.indexOf(':LEN:');
                if (endIdx != -1) {
                  foundKey = text.substring(4, endIdx);
                }
              }
              expect(foundKey, isNotNull);
              final expected = payloadStore[foundKey];
              expect(expected, isNotNull);
              expect(text, equals(expected));
            } else if (frame.type == FrameType.binary) {
              expect(loaded, isA<Uint8List>());
              final bytes = loaded as Uint8List;
              expect(bytes.length, equals(frame.payloadSizeBytes));
              expect(bytes[0], equals(0xAA));
              expect(bytes[1], equals(0xBB));
              expect(bytes[2], equals(0xCC));
              expect(bytes[3], equals(0xDD));
              final keyLen = bytes[8];
              foundKey = utf8.decode(bytes.sublist(9, 9 + keyLen));
              final expected = payloadStore[foundKey];
              expect(expected, isNotNull);
              expect(listEquals(bytes, expected as Uint8List), isTrue);
            }

            if (frame.location == BodyLocation.file) {
              offloadedFramesVerified++;
              expect(frame.fileOffset, isNotNull);
              expect(frame.fileLength, isNotNull);
              expect(frame.fileLength, equals(frame.payloadSizeBytes));
            } else {
              memoryFramesVerified++;
            }
          }
        }

        expect(
          offloadedFramesVerified,
          greaterThan(50),
          reason:
              'Must have verified substantial offloaded payloads crossing 32 KB threshold',
        );
        expect(
          memoryFramesVerified,
          greaterThan(50),
          reason: 'Must have verified in-memory payloads < 32 KB',
        );
      },
    );
  });
}
