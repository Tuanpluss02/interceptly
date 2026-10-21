import 'dart:async';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart' as vm_io;

import '../logging.dart';
import 'app_discovery.dart';
import 'vm_service_errors.dart';

/// Contract for interacting with the Flutter VM Service and Interceptly extension RPCs.
abstract interface class VmServiceClient {
  /// Whether the client is currently connected to a running VM Service and has an active isolate.
  bool get isConnected;

  /// The version of the Interceptly extension API reported by the remote app, or `null` if not connected.
  int? get remoteExtensionApiVersion;

  /// The ID of the currently active Flutter isolate.
  String? get activeIsolateId;

  /// The WebSocket URI of the connected VM Service.
  Uri? get connectedUri;

  /// Connects to the VM Service at [wsUri].
  Future<void> connect(Uri wsUri);

  /// Disconnects from the current VM Service session and clears state.
  Future<void> disconnect();

  /// Ensures that a connection is established, discovering candidates if needed.
  Future<void> ensureConnected();

  /// Invokes an extension RPC method with the given [params].
  Future<Map<String, dynamic>> invoke(
    String method, [
    Map<String, String>? params,
  ]);
}

/// Default implementation of [VmServiceClient] connecting over WebSockets.
class DefaultVmServiceClient implements VmServiceClient {
  /// Creates a [DefaultVmServiceClient].
  ///
  /// Optionally accepts [explicitUri] to bypass auto-discovery, [environment]
  /// for fallback environment variables, and [dtdUri] for Dart Tooling Daemon discovery.
  DefaultVmServiceClient({
    this.explicitUri,
    this.environment,
    this.dtdUri,
    Future<VmService> Function(String)? vmServiceConnectUri,
  }) : vmServiceConnectUri = vmServiceConnectUri ?? vm_io.vmServiceConnectUri;

  /// Explicitly provided VM Service URI, if specified via CLI flags.
  final Uri? explicitUri;

  /// Process environment map used to resolve fallback discovery URIs.
  final Map<String, String>? environment;

  /// Explicitly provided Dart Tooling Daemon (DTD) URI, if specified.
  final Uri? dtdUri;

  /// Factory function for creating a [VmService] connection given a WebSocket URI.
  final Future<VmService> Function(String) vmServiceConnectUri;

  VmService? _vmService;
  Uri? _connectedUri;
  String? _activeIsolateId;
  int? _remoteExtensionApiVersion;

  /// Minimum supported Interceptly extension API version.
  static const int minCompatibleExtensionApiVersion = 1;

  /// Maximum supported Interceptly extension API version.
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

    unawaited(
      service.onDone
          .then((_) {
            if (identical(_vmService, service)) {
              logStderr(
                'VM Service connection closed by remote host ($wsUri).',
              );
              disconnect();
            }
          })
          .catchError((_) {
            if (identical(_vmService, service)) {
              disconnect();
            }
          }),
    );

    await _refreshIsolate();

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
