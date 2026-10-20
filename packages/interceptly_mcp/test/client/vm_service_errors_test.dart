import 'package:interceptly_mcp/src/client/vm_service_errors.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

void main() {
  group('VmServiceErrorClassification', () {
    test(
      'isConnectionDisposed matches RPCError -32000 and socket messages',
      () {
        final rpcError = RPCError(
          'getVM',
          -32000,
          'Service connection disposed',
        );
        expect(rpcError.isConnectionDisposed, isTrue);

        final strError = Exception(
          'WebSocketChannelException: connection closed',
        );
        expect(strError.isConnectionDisposed, isTrue);

        final otherError = RPCError('ping', 100, 'Some other error');
        expect(otherError.isConnectionDisposed, isFalse);
      },
    );

    test('isIsolateInvalidated matches Sentinel and dead isolate codes', () {
      final sentinelError = RPCError(
        'ext.interceptly.ping',
        106,
        '[Sentinel kind: Collected, valueAsString: <collected>] from ext.interceptly.ping()',
      );
      expect(sentinelError.isIsolateInvalidated, isTrue);

      final isolate105 = RPCError(
        'ext.interceptly.ping',
        105,
        'Isolate must be runnable',
      );
      expect(isolate105.isIsolateInvalidated, isTrue);

      final deadIsolateError = RPCError(
        'invoke',
        100,
        'isolate has terminated',
      );
      expect(deadIsolateError.isIsolateInvalidated, isTrue);

      final unhandled = Exception('random network failure');
      expect(unhandled.isIsolateInvalidated, isFalse);
    });
  });
}
