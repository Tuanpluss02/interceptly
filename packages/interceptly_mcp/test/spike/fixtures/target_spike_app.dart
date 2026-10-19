import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

void main() async {
  developer.registerExtension('ext.spike.test', (method, parameters) async {
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'status': 'ok',
        'echo': parameters['message'] ?? 'none',
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );
  });

  // Signal ready on stderr
  stderr.writeln('SPIKE_TARGET_READY');

  // Keep event loop active
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {});
  ProcessSignal.sigterm.watch().listen((_) {
    timer.cancel();
    exit(0);
  });

  await Completer<void>().future;
}
