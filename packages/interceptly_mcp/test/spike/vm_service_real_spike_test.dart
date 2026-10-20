import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// Automated Spike: Confirms that real headless Dart processes expose VM Service,
/// that vm_service can connect over WebSockets, enumerate isolates, and invoke custom
/// service protocol extensions.
///
/// Manual Verification Checklist for Flutter App Hot Restart:
/// 1. Run Flutter example: cd packages/interceptly/example && flutter run
/// 2. Launch CLI: dart run packages/interceptly_mcp/bin/interceptly_mcp.dart --uri <printed-ws-uri>
/// 3. Call tool list_requests -> verify requests appear.
/// 4. Press 'R' in Flutter console (Hot Restart) -> previous isolate is destroyed, new one created.
/// 5. Call tool list_requests again -> verify CLI locates new isolate without crashing.
void main() {
  group('Real VM Service Spike', () {
    late Process process;
    VmService? vmService;
    late Uri wsUri;

    setUp(() async {
      final fixturePath = p.normalize(
        p.join(
          Directory.current.path,
          'test',
          'spike',
          'fixtures',
          'target_spike_app.dart',
        ),
      );

      final uriCompleter = Completer<Uri>();

      process = await Process.start('dart', [
        '--enable-vm-service=0',
        fixturePath,
      ]);

      final uriRegex = RegExp(
        r'The Dart VM service is listening on (http://[^\s]+)',
      );

      void handleLine(String line) {
        final match = uriRegex.firstMatch(line);
        if (match != null && !uriCompleter.isCompleted) {
          final httpUri = Uri.parse(match.group(1)!);
          final wsPath =
              httpUri.path.endsWith('/')
                  ? '${httpUri.path}ws'
                  : '${httpUri.path}/ws';
          final ws = httpUri.replace(scheme: 'ws', path: wsPath);
          uriCompleter.complete(ws);
        }
      }

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(handleLine);

      wsUri = await uriCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout:
            () => throw TimeoutException('Failed to capture VM service URI'),
      );

      vmService = await vmServiceConnectUri(wsUri.toString());
    });

    tearDown(() async {
      await vmService?.dispose();
      process.kill(ProcessSignal.sigterm);
      await process.exitCode;
    });

    test(
      'connects to real Dart VM, queries isolates, and invokes extension RPC',
      () async {
        VM vm = await vmService!.getVM();
        while ((vm.isolates ?? []).isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          vm = await vmService!.getVM();
        }
        expect(vm.isolates, isNotEmpty);

        final isolateRef = vm.isolates!.first;
        Isolate isolate = await vmService!.getIsolate(isolateRef.id!);
        while (!(isolate.extensionRPCs ?? []).contains('ext.spike.test')) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          isolate = await vmService!.getIsolate(isolateRef.id!);
        }

        expect(isolate.extensionRPCs, contains('ext.spike.test'));

        final response = await vmService!.callServiceExtension(
          'ext.spike.test',
          isolateId: isolate.id,
          args: {'message': 'spike_verification'},
        );

        final json = response.json!;
        expect(json['status'], 'ok');
        expect(json['echo'], 'spike_verification');
      },
    );
  });
}
