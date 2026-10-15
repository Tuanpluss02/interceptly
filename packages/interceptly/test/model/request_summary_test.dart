import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  RequestSummary createSummary({
    required String id,
    required String method,
    required String url,
    int statusCode = 200,
  }) {
    return RequestSummary(
      id: id,
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: 10,
      requestSizeBytes: 0,
      responseSizeBytes: 0,
      timestamp: DateTime(2026),
      hasError: false,
      requestTruncation: const BodyTruncation.complete(0),
      responseTruncation: const BodyTruncation.complete(0),
    );
  }

  group('RequestSummary.isRealtime', () {
    test('returns true for WS, SIO, and SSE methods', () {
      final ws = createSummary(
        id: '1',
        method: 'WS',
        url: 'ws://example.com/socket',
      );
      final sio = createSummary(
        id: '2',
        method: 'SIO',
        url: 'https://example.com/socket.io',
      );
      final sse = createSummary(
        id: '3',
        method: 'SSE',
        url: 'https://example.com/events',
      );

      expect(ws.isRealtime, isTrue);
      expect(sio.isRealtime, isTrue);
      expect(sse.isRealtime, isTrue);
    });

    test('returns false for HTTP/REST methods', () {
      final get = createSummary(
        id: '4',
        method: 'GET',
        url: 'https://example.com/api',
      );
      final post = createSummary(
        id: '5',
        method: 'POST',
        url: 'https://example.com/api',
      );

      expect(get.isRealtime, isFalse);
      expect(post.isRealtime, isFalse);
    });
  });
}
