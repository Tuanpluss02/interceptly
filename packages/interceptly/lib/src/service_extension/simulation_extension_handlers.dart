import 'dart:developer' as developer;

import '../engine/interceptly_engine.dart';
import '../model/network_simulation.dart';
import 'service_extension_exception.dart';

/// Handlers for network simulation and state mutation service extensions.
abstract final class SimulationExtensionHandlers {
  /// Handles `ext.interceptly.setNetworkSimulation`.
  static Map<String, dynamic> handleSetNetworkSimulation({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) {
    checkServiceExtensionEnabled(isEnabled);

    if (engine == null) {
      throw const ServiceExtensionException(
        developer.ServiceExtensionResponse.extensionError,
        'Interceptly engine is not available',
      );
    }

    final profileStr = parameters['profile']?.toLowerCase();
    final enabledParam = parameters['enabled'];
    final latencyMsParam = parameters['latency_ms'];
    final offlineParam = parameters['offline'] == 'true';
    final downloadKbpsParam = parameters['download_kbps'];
    final uploadKbpsParam = parameters['upload_kbps'];

    NetworkSimulationProfile profile;
    if (enabledParam == 'false') {
      profile = NetworkSimulationProfile.none;
    } else if (profileStr != null && profileStr.isNotEmpty) {
      profile = switch (profileStr) {
        'offline' => NetworkSimulationProfile.offlineProfile,
        'slow3g' || 'slow_3g' => NetworkSimulationProfile.slow3G,
        'fast3g' || 'fast_3g' => NetworkSimulationProfile.fast3G,
        '4g' => NetworkSimulationProfile.fourG,
        'wifi' => NetworkSimulationProfile.wifi,
        'custom' => NetworkSimulationProfile(
            name: 'Custom',
            offline: offlineParam,
            latencyMs: int.tryParse(latencyMsParam ?? '0') ?? 0,
            downloadKbps: int.tryParse(downloadKbpsParam ?? '0') ?? 0,
            uploadKbps: int.tryParse(uploadKbpsParam ?? '0') ?? 0,
          ),
        _ => NetworkSimulationProfile.none,
      };
    } else if (latencyMsParam != null ||
        offlineParam ||
        downloadKbpsParam != null ||
        uploadKbpsParam != null) {
      profile = NetworkSimulationProfile(
        name: 'Custom',
        offline: offlineParam,
        latencyMs: int.tryParse(latencyMsParam ?? '0') ?? 0,
        downloadKbps: int.tryParse(downloadKbpsParam ?? '0') ?? 0,
        uploadKbps: int.tryParse(uploadKbpsParam ?? '0') ?? 0,
      );
    } else {
      profile = NetworkSimulationProfile.none;
    }

    engine.setNetworkSimulation(profile);

    return {
      'status': 'ok',
      'networkSimulation': profile.name,
    };
  }

  /// Handles `ext.interceptly.clearTraffic`.
  static Future<Map<String, dynamic>> handleClearTraffic({
    required InterceptlyEngine? engine,
    required Map<String, String> parameters,
    bool isEnabled = true,
  }) async {
    checkServiceExtensionEnabled(isEnabled);

    if (engine != null) {
      await engine.clear();
    }

    return {'status': 'ok'};
  }
}
