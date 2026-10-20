import 'dart:async';
import 'package:dtd/dtd.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../logging.dart';
import 'process_scanner.dart';

/// Represents a running Flutter/Dart application with active Interceptly extensions.
class DiscoveredApp {
  const DiscoveredApp({required this.uri, required this.isolateId, this.name});

  /// The WebSocket URI to connect to.
  final Uri uri;

  /// The primary isolate ID advertising `ext.interceptly.ping`.
  final String isolateId;

  /// Human-readable application or device name, if known.
  final String? name;

  @override
  String toString() =>
      'DiscoveredApp(name: $name, uri: $uri, isolateId: $isolateId)';
}

/// Thrown when multiple running apps advertise Interceptly extensions,
/// requiring the user/client to explicitly specify which app to connect to.
class MultipleAppsException implements Exception {
  const MultipleAppsException(this.candidates);

  final List<DiscoveredApp> candidates;

  @override
  String toString() {
    final buffer = StringBuffer(
      'Multiple Flutter apps with Interceptly detected. Please specify target with --uri or call connect_app(uri: ...):\n',
    );
    for (final app in candidates) {
      buffer.writeln(
        '  - ${app.name ?? "Flutter App"}: ${app.uri} (isolate: ${app.isolateId})',
      );
    }
    return buffer.toString().trim();
  }
}

/// Discovery cascade that resolves the VM Service URI to connect to.
class AppDiscovery {
  AppDiscovery._();

  static const ProcessScanner _processScanner = ProcessScanner();

  /// Validates whether [uri] points to a loopback address.
  ///
  /// Prevents security risks where a client is directed to an external host.
  static bool isLoopbackUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '::1' ||
        host == '[::1]';
  }

  /// Normalizes an HTTP or WebSocket URI to a standard VM Service WebSocket URI.
  static Uri normalizeWsUri(Uri uri) {
    var path = uri.path;
    if (!path.endsWith('/ws')) {
      if (path.endsWith('/')) {
        path = '${path}ws';
      } else {
        path = '$path/ws';
      }
    }
    return uri.replace(scheme: 'ws', path: path);
  }

  /// Resolves the VM Service URI following the priority cascade:
  /// 1. [explicitUri] (from CLI argument)
  /// 2. `INTERCEPTLY_VM_SERVICE_URI` (from environment)
  /// 3. [dtdUri] or `DTD_URI` environment variable
  /// 4. Dynamic local discovery (scanning active DTD / DDS processes)
  static Future<Uri?> resolveUri({
    Uri? explicitUri,
    Map<String, String>? environment,
    Uri? dtdUri,
    ProcessScanner processScanner = _processScanner,
  }) async {
    // 1. Explicit CLI argument
    if (explicitUri != null) {
      if (!isLoopbackUri(explicitUri)) {
        throw ArgumentError(
          'Security error: VM Service URI must be a loopback address (127.0.0.1 or localhost), got: $explicitUri',
        );
      }
      return normalizeWsUri(explicitUri);
    }

    // 2. Custom environment variable
    final envUriStr = environment?['INTERCEPTLY_VM_SERVICE_URI'];
    if (envUriStr != null && envUriStr.trim().isNotEmpty) {
      final envUri = Uri.parse(envUriStr.trim());
      if (!isLoopbackUri(envUri)) {
        throw ArgumentError(
          'Security error: INTERCEPTLY_VM_SERVICE_URI must be a loopback address, got: $envUri',
        );
      }
      return normalizeWsUri(envUri);
    }

    // 3. Statically configured Dart Tooling Daemon (DTD)
    final dtdUriStr = dtdUri?.toString() ?? environment?['DTD_URI'];
    if (dtdUriStr != null && dtdUriStr.trim().isNotEmpty) {
      final discoveredFromDtd = await _queryDtdForInterceptlyApp(
        Uri.parse(dtdUriStr.trim()),
      );
      if (discoveredFromDtd != null) {
        return discoveredFromDtd;
      }
    }

    // 4. Dynamic local discovery via running processes (unless disabled for tests)
    if (environment?['INTERCEPTLY_DISABLE_PROCESS_SCAN'] != 'true') {
      final dynamicDiscovered = await _discoverViaRunningProcesses(
        processScanner,
      );
      if (dynamicDiscovered != null) {
        return dynamicDiscovered;
      }
    }

    return null;
  }

  /// Discovers candidate endpoints by inspecting local running processes.
  static Future<Uri?> _discoverViaRunningProcesses(
    ProcessScanner scanner,
  ) async {
    final commandLines = await scanner.getRunningCommandLines();
    if (commandLines.isEmpty) return null;

    // 4a. Check active DTD instances
    for (final dtdUri in scanner.extractDtdUris(commandLines)) {
      if (!isLoopbackUri(dtdUri)) continue;
      final uri = await _queryDtdForInterceptlyApp(dtdUri);
      if (uri != null) return uri;
    }

    // 4b. Check active DDS / VM Service instances directly
    for (final ddsUri in scanner.extractDdsUris(commandLines)) {
      if (!isLoopbackUri(ddsUri)) continue;
      final wsUri = normalizeWsUri(ddsUri);
      if (await _hasInterceptlyExtension(wsUri)) {
        logStderr(
          'Auto-discovered Interceptly app via running DDS process ($wsUri).',
        );
        return wsUri;
      }
    }

    return null;
  }

  /// Queries a DTD daemon at [dtdUri] for registered VM Services hosting Interceptly.
  static Future<Uri?> _queryDtdForInterceptlyApp(Uri dtdUri) async {
    if (!isLoopbackUri(dtdUri)) return null;
    try {
      final dtd = await DartToolingDaemon.connect(dtdUri);
      final response = await dtd.getVmServices();
      await dtd.close();

      for (final info in response.vmServicesInfos) {
        final rawUri = Uri.tryParse(info.uri);
        if (rawUri == null || !isLoopbackUri(rawUri)) continue;

        final wsUri = normalizeWsUri(rawUri);
        if (await _hasInterceptlyExtension(wsUri)) {
          logStderr(
            'Auto-discovered Interceptly app via DTD ($dtdUri -> $wsUri).',
          );
          return wsUri;
        }
      }
    } catch (_) {
      // DTD instance might be terminating or unreachable
    }
    return null;
  }

  /// Verifies if a VM Service at [wsUri] hosts an isolate with `ext.interceptly.ping`.
  static Future<bool> _hasInterceptlyExtension(Uri wsUri) async {
    try {
      final service = await vmServiceConnectUri(wsUri.toString());
      final candidates = await findCandidates(service, targetUri: wsUri);
      await service.dispose();
      return candidates.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Finds all isolates inside [service] that advertise `ext.interceptly.ping`.
  static Future<List<DiscoveredApp>> findCandidates(
    VmService service, {
    Uri? targetUri,
  }) async {
    final vm = await service.getVM();
    final isolates = vm.isolates ?? <IsolateRef>[];
    final candidates = <DiscoveredApp>[];

    for (final ref in isolates) {
      if (ref.id == null) continue;
      try {
        final isolate = await service.getIsolate(ref.id!);
        final rpcs = isolate.extensionRPCs ?? <String>[];
        if (rpcs.contains('ext.interceptly.ping')) {
          candidates.add(
            DiscoveredApp(
              uri: targetUri ?? Uri.parse('ws://127.0.0.1/ws'),
              isolateId: ref.id!,
              name: isolate.name ?? ref.name,
            ),
          );
        }
      } catch (_) {
        // Isolate may have exited during inspection
      }
    }

    return candidates;
  }
}
