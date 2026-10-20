import 'dart:async';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart' as vm_io;

import '../logging.dart';
import 'app_discovery.dart';
import 'vm_service_errors.dart';

/// Contract for interacting with the Flutter VM Service and Interceptly extension RPCs.
abstract interface class VmServiceClient {
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
  DefaultVmServiceClient({
    this.explicitUri,
    this.environment,
    this.dtdUri,
    Future<VmService> Function(String)? vmServiceConnectUri,
  }) : vmServiceConnectUri = vmServiceConnectUri ?? vm_io.vmServiceConnectUri;

  final Uri? explicitUri;
  final Map<String, String>? environment;
  final Uri? dtdUri;
  final Future<VmService> Function(String) vmServiceConnectUri;

  VmService? _vmService;
  Uri? _connectedUri;
  String? _activeIsolateId;
  int? _remoteExtensionApiVersion;

  static const int minCompatibleExtensionApiVersion = 1;
  static const int maxCompatibleExtensionApiVersion = 1;

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

    // Automatically reset connection state when remote host closes WebSocket
    unawaited(
      service.onDone
          .then((_) {
            logStderr('VM Service connection closed by remote host ($wsUri).');
            disconnect();
          })
          .catchError((_) {
            disconnect();
          }),
    );

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

    try {
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
    } catch (e) {
      if (e.isConnectionDisposed) {
        await disconnect();
      }
      rethrow;
    }
  }

  Future<void> _checkVersionContract() async {
    try {
      final res = await invoke('ext.interceptly.ping');
      final version = res['extensionApiVersion'] as int?;
      _remoteExtensionApiVersion = version;

      if (version != null &&
          (version < minCompatibleExtensionApiVersion ||
              version > maxCompatibleExtensionApiVersion)) {
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

  /// Executes an operation against the active VM Service, automatically recovering from
  /// isolate invalidation (e.g. Flutter Hot Restart) or connection termination.
  Future<T> _executeWithRecovery<T>(
    Future<T> Function(VmService service, String isolateId) action,
  ) async {
    await ensureConnected();

    final service = _vmService;
    final isolateId = _activeIsolateId;
    if (service == null || isolateId == null) {
      throw StateError('Cannot execute request: client is not connected');
    }

    try {
      return await action(service, isolateId);
    } catch (e) {
      if (e.isConnectionDisposed) {
        logStderr('VM connection was disposed ($e). Resetting state...');
        await disconnect();
        rethrow;
      }
      if (e.isIsolateInvalidated) {
        logStderr(
          'Target isolate invalidated ($e). Attempting to re-discover isolate after Hot Restart...',
        );
        await _refreshIsolate();
        return await action(service, _activeIsolateId!);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, String>? params,
  ]) async {
    return _executeWithRecovery((service, isolateId) async {
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
    });
  }
}
