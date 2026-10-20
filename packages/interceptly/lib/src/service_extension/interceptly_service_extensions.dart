import 'dart:convert';
import 'dart:developer' as developer;

import '../engine/interceptly_engine.dart';
import 'http_extension_handlers.dart';
import 'realtime_extension_handlers.dart';
import 'service_extension_exception.dart';
import 'simulation_extension_handlers.dart';
import 'summary_extension_handlers.dart';

export 'service_extension_exception.dart';

/// Registers and executes VM Service Protocol extensions (`ext.interceptly.*`)
/// allowing standalone tools (such as `interceptly_mcp`) to interact with
/// the running application via Dart VM Service.
class InterceptlyServiceExtensions {
  InterceptlyServiceExtensions._();

  /// Current schema revision of the Interceptly service extension contract.
  static const int extensionApiVersion = 1;

  static bool _isRegistered = false;
  static bool _enabled = true;
  static InterceptlyEngine? _engine;

  /// Whether extensions have been registered with [developer.registerExtension].
  static bool get isRegistered => _isRegistered;

  /// Whether extension RPC handlers are actively serving requests.
  static bool get isEnabled => _enabled;

  /// Enables serving extension requests.
  static void enable() => _enabled = true;

  /// Disables serving extension requests. When disabled, RPC calls return errors.
  static void disable() => _enabled = false;

  /// Idempotently registers Interceptly service extensions.
  ///
  /// Safe to call multiple times (e.g. during Hot Reload).
  /// Subsequent calls update the active [engine] reference without re-registering
  /// extension names, preventing `ArgumentError` duplicate registration crashes.
  static void register([InterceptlyEngine? engine]) {
    _engine = engine ?? InterceptlyEngine.instance;
    _enabled = true;

    if (_isRegistered) return;
    _isRegistered = true;

    _register(
      'ext.interceptly.ping',
      (params) async => handlePing(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.listRequests',
      (params) => HttpExtensionHandlers.handleListRequests(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.getRequestDetail',
      (params) => HttpExtensionHandlers.handleGetRequestDetail(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.setNetworkSimulation',
      (params) async => SimulationExtensionHandlers.handleSetNetworkSimulation(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.clearTraffic',
      (params) => SimulationExtensionHandlers.handleClearTraffic(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.exportCurl',
      (params) => HttpExtensionHandlers.handleExportCurl(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.listRealtimeFrames',
      (params) => RealtimeExtensionHandlers.handleListRealtimeFrames(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.getRealtimeFrameDetail',
      (params) => RealtimeExtensionHandlers.handleGetRealtimeFrameDetail(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );

    _register(
      'ext.interceptly.getTrafficSummary',
      (params) async => SummaryExtensionHandlers.handleGetTrafficSummary(
        engine: _engine,
        parameters: params,
        isEnabled: _enabled,
      ),
    );
  }

  static void _register(
    String name,
    Future<Map<String, dynamic>> Function(Map<String, String>) handler,
  ) {
    try {
      developer.registerExtension(name, (method, params) async {
        try {
          final result = await handler(params);
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } on ServiceExtensionException catch (e) {
          return developer.ServiceExtensionResponse.error(
            e.errorCode,
            jsonEncode({'errorCode': e.errorCode, 'message': e.message}),
          );
        } catch (e) {
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            jsonEncode({'errorCode': -32000, 'message': e.toString()}),
          );
        }
      });
    } catch (_) {}
  }

  /// Handles `ext.interceptly.ping`.
  static Map<String, dynamic> handlePing({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    checkServiceExtensionEnabled(isEnabled);

    return {
      'status': 'ok',
      'appName': 'Interceptly',
      'extensionApiVersion': extensionApiVersion,
      'sessionId': engine?.engineId ?? 'unknown',
      'entryCount': engine?.entries.length ?? 0,
      'requestCount': engine?.entries.length ?? 0,
      'droppedCount': engine?.droppedCount ?? 0,
      'networkSimulation': engine?.networkSimulation.name ?? 'none',
    };
  }
}
