import 'dart:async';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../logging.dart';
import '../version.dart';
import 'app_discovery.dart';

/// Interface for interacting with the Flutter application via Dart VM Service.
abstract class VmServiceClient {
  bool get isConnected;
  int? get remoteExtensionApiVersion;
  String? get activeIsolateId;
  Uri? get connectedUri;

  Future<void> connect(Uri wsUri);
  Future<void> disconnect();
  Future<void> ensureConnected();
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, String>? params,
  ]);
}

/// Default implementation of [VmServiceClient] connecting over WebSockets.
class DefaultVmServiceClient implements VmServiceClient {
  DefaultVmServiceClient({this.explicitUri, this.environment, this.dtdUri});

  final Uri? explicitUri;
  final Map<String, String>? environment;
  final Uri? dtdUri;

  VmService? _vmService;
  Uri? _connectedUri;
  String? _activeIsolateId;
  int? _remoteExtensionApiVersion;

  @override
  bool get isConnected => _vmService != null && _activeIsolateId != null;

  @override
  int? get remoteExtensionApiVersion => _remoteExtensionApiVersion;

  @override
  String? get activeIsolateId => _activeIsolateId;

  @override
  Uri? get connectedUri => _connectedUri;

  @override
  Future<void> connect(Uri wsUri) async {
    if (!AppDiscovery.isLoopbackUri(wsUri)) {
      throw ArgumentError(
        'Security error: Target URI must be a loopback address: $wsUri',
      );
    }

    await disconnect();

    logStderr('Connecting to VM Service at $wsUri...');
    final service = await vmServiceConnectUri(wsUri.toString());
    _vmService = service;
    _connectedUri = wsUri;

    // Discover target isolate
    await _refreshIsolate();

    // Verify version contract
    await _checkVersionContract();
  }

  @override
  Future<void> disconnect() async {
    try {
      await _vmService?.dispose();
    } catch (_) {}
    _vmService = null;
    _connectedUri = null;
    _activeIsolateId = null;
    _remoteExtensionApiVersion = null;
  }

  @override
  Future<void> ensureConnected() async {
    if (isConnected) return;

    final targetUri = await AppDiscovery.resolveUri(
      explicitUri: explicitUri ?? _connectedUri,
      environment: environment,
      dtdUri: dtdUri,
    );

    if (targetUri == null) {
      throw StateError(
        'Could not locate a running Flutter app with Interceptly. '
        'Ensure your Flutter app is running with Interceptly.init() '
        'and pass --uri or set INTERCEPTLY_VM_SERVICE_URI.',
      );
    }

    await connect(targetUri);
  }

  Future<void> _refreshIsolate() async {
    final service = _vmService;
    if (service == null) throw StateError('Not connected to VM service');

    final candidates = await AppDiscovery.findCandidates(
      service,
      targetUri: _connectedUri,
    );
    if (candidates.isEmpty) {
      throw StateError(
        'Connected to VM service at $_connectedUri, but no active isolate '
        'registered the "ext.interceptly.ping" extension. '
        'Ensure Interceptly.init() is called in debug mode.',
      );
    }

    if (candidates.length > 1) {
      throw MultipleAppsException(candidates);
    }

    _activeIsolateId = candidates.first.isolateId;
    logStderr(
      'Bound to isolate: $_activeIsolateId (${candidates.first.name ?? "unnamed"})',
    );
  }

  Future<void> _checkVersionContract() async {
    try {
      final res = await invoke('ext.interceptly.ping');
      final version = res['extensionApiVersion'] as int?;
      _remoteExtensionApiVersion = version;

      if (version == null ||
          version < minCompatibleExtensionApiVersion ||
          version > maxCompatibleExtensionApiVersion) {
        logStderr(
          'WARNING: Version skew detected! '
          'App extensionApiVersion is $version, but CLI supports '
          '$minCompatibleExtensionApiVersion..$maxCompatibleExtensionApiVersion. '
          'Some tools may behave unexpectedly. Please update your dependencies.',
        );
      }
    } catch (e) {
      logStderr('Could not verify version contract on startup: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, String>? params,
  ]) async {
    await ensureConnected();

    final service = _vmService;
    final isolateId = _activeIsolateId;
    if (service == null || isolateId == null) {
      throw StateError('Cannot invoke $method: client is not connected');
    }

    try {
      final response = await service.callServiceExtension(
        method,
        isolateId: isolateId,
        args: params,
      );

      final json = response.json;
      if (json == null) {
        throw StateError('Empty response from $method');
      }
      return json;
    } on RPCError catch (e) {
      // Check if isolate died (e.g. after hot restart)
      if (e.message.contains('isolate') || e.code == 105 || e.code == -32000) {
        logStderr(
          'Isolate error ($e), attempting to re-discover isolate after hot restart...',
        );
        await _refreshIsolate();

        // Retry invocation once with refreshed isolate
        final retryResponse = await service.callServiceExtension(
          method,
          isolateId: _activeIsolateId,
          args: params,
        );
        return retryResponse.json ?? <String, dynamic>{};
      }
      rethrow;
    }
  }
}
