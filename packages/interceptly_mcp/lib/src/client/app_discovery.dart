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
    if (explicitUri != null) {
      if (!isLoopbackUri(explicitUri)) {
        throw ArgumentError(
          'Security error: VM Service URI must be a loopback address (127.0.0.1 or localhost), got: $explicitUri',
        );
      }
      return normalizeWsUri(explicitUri);
    }

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

    final dtdUriStr = dtdUri?.toString() ?? environment?['DTD_URI'];
    if (dtdUriStr != null && dtdUriStr.trim().isNotEmpty) {
      final apps = await _queryDtdCandidates(Uri.parse(dtdUriStr.trim()));
      final uniqueByUri = <Uri, DiscoveredApp>{};
      for (final app in apps) {
        uniqueByUri.putIfAbsent(app.uri, () => app);
      }
      if (uniqueByUri.length > 1) {
        throw MultipleAppsException(apps);
      }
      if (uniqueByUri.length == 1) {
        return uniqueByUri.values.first.uri;
      }
    }

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

    final candidates = <DiscoveredApp>[];
    final probedUris = <Uri>{};

    for (final dtdUri in scanner.extractDtdUris(commandLines)) {
      if (!isLoopbackUri(dtdUri)) continue;
      final apps = await _queryDtdCandidates(dtdUri);
      for (final app in apps) {
        if (probedUris.add(app.uri)) {
          candidates.add(app);
        }
      }
    }

    for (final ddsUri in scanner.extractDdsUris(commandLines)) {
      if (!isLoopbackUri(ddsUri)) continue;
      final wsUri = normalizeWsUri(ddsUri);
      if (probedUris.add(wsUri)) {
        final apps = await _probeCandidates(wsUri);
        candidates.addAll(apps);
      }
    }

    if (candidates.isEmpty) return null;

    // Deduplicate distinct apps by URI
    final uniqueByUri = <Uri, DiscoveredApp>{};
    for (final c in candidates) {
      uniqueByUri.putIfAbsent(c.uri, () => c);
    }

    if (uniqueByUri.length > 1) {
      throw MultipleAppsException(candidates);
    }

    final single = uniqueByUri.values.first;
    logStderr('Auto-discovered Interceptly app (${single.uri}).');
    return single.uri;
  }

  /// Queries a DTD daemon at [dtdUri] for registered VM Services hosting Interceptly.
  static Future<List<DiscoveredApp>> _queryDtdCandidates(Uri dtdUri) async {
    if (!isLoopbackUri(dtdUri)) return const [];
    try {
      final dtd = await DartToolingDaemon.connect(
        dtdUri,
      ).timeout(const Duration(seconds: 2));
      try {
        final response = await dtd.getVmServices();
        final apps = <DiscoveredApp>[];
        for (final info in response.vmServicesInfos) {
          final rawUri = Uri.tryParse(info.uri);
          if (rawUri == null || !isLoopbackUri(rawUri)) continue;
          final wsUri = normalizeWsUri(rawUri);
          final candidates = await _probeCandidates(wsUri);
          apps.addAll(candidates);
        }
        return apps;
      } finally {
        await dtd.close();
      }
    } catch (_) {
      return const [];
    }
  }

  /// Probes [wsUri] to discover isolates advertising `ext.interceptly.ping`.
  static Future<List<DiscoveredApp>> _probeCandidates(Uri wsUri) async {
    try {
      final service = await vmServiceConnectUri(
        wsUri.toString(),
      ).timeout(const Duration(seconds: 2));
      try {
        return await findCandidates(
          service,
          targetUri: wsUri,
        ).timeout(const Duration(seconds: 2));
      } finally {
        await service.dispose();
      }
    } catch (_) {
      return const [];
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
      } catch (_) {}
    }

    return candidates;
  }
}
