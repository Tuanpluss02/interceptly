import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';

void main() {
  group('RealtimeProtocolType', () {
    test('contains expected protocol types', () {
      expect(RealtimeProtocolType.values,
          contains(RealtimeProtocolType.webSocket));
      expect(
          RealtimeProtocolType.values, contains(RealtimeProtocolType.socketIo));
      expect(RealtimeProtocolType.values, contains(RealtimeProtocolType.sse));
    });
  });

  group('RealtimeMessageDraft', () {
    test('initializes with event and payload', () {
      const draft = RealtimeMessageDraft(
        event: 'chat:message',
        payload: '{"text":"hello"}',
      );

      expect(draft.event, 'chat:message');
      expect(draft.payload, '{"text":"hello"}');
      expect(draft.payloadText, '{"text":"hello"}');
    });

    test('handles null event for raw websocket', () {
      const draft = RealtimeMessageDraft(
        payload: 'raw message',
      );

      expect(draft.event, isNull);
      expect(draft.payload, 'raw message');
      expect(draft.payloadText, 'raw message');
    });

    test('payloadText handles non-string payload', () {
      final draft = RealtimeMessageDraft(
        payload: {'key': 'val'},
      );

      expect(draft.payloadText, '{key: val}');
    });

    test('equality and hashCode match by value', () {
      const d1 = RealtimeMessageDraft(event: 'e1', payload: 'p1');
      const d2 = RealtimeMessageDraft(event: 'e1', payload: 'p1');
      const d3 = RealtimeMessageDraft(event: 'e2', payload: 'p1');

      expect(d1, equals(d2));
      expect(d1.hashCode, equals(d2.hashCode));
      expect(d1, isNot(equals(d3)));
    });

    test('toString includes event and payload', () {
      const draft = RealtimeMessageDraft(event: 'e', payload: 'p');
      expect(draft.toString(), contains('event: e'));
      expect(draft.toString(), contains('payload: p'));
    });
  });
}
