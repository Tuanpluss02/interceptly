import 'package:vm_service/vm_service.dart';

/// Extension providing centralized, type-safe classification of Dart VM Service errors.
extension VmServiceErrorClassification on Object {
  /// Returns `true` if this error indicates the remote VM Service connection was terminated.
  bool get isConnectionDisposed {
    if (this is RPCError) {
      final rpc = this as RPCError;
      if (rpc.code == -32000 &&
          rpc.message.toLowerCase().contains('disposed')) {
        return true;
      }
    }
    final str = toString().toLowerCase();
    return str.contains('service connection disposed') ||
        str.contains('connection closed') ||
        str.contains('socketexception') ||
        str.contains('websocketchannelfailed');
  }

  /// Returns `true` if this error indicates the target Dart Isolate was destroyed or collected
  /// (e.g. during a Flutter Hot Restart).
  bool get isIsolateInvalidated {
    if (this is RPCError) {
      final rpc = this as RPCError;
      // 105: Isolate must be runnable, 106: Cannot invoke on collected/dead isolate
      if (rpc.code == 105 || rpc.code == 106) return true;
      final msg = rpc.message.toLowerCase();
      if (msg.contains('sentinel') ||
          msg.contains('collected') ||
          (msg.contains('isolate') &&
              (msg.contains('dead') ||
                  msg.contains('exit') ||
                  msg.contains('not found')))) {
        return true;
      }
    }
    final str = toString().toLowerCase();
    return (str.contains('sentinel') && str.contains('collected')) ||
        str.contains('isolate has terminated');
  }
}
