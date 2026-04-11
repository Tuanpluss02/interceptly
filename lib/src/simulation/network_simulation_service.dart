import '../model/network_simulation.dart';

/// Pure-static helpers for computing and applying network simulation delays.
///
/// [InspectorSession] owns the active [NetworkSimulationProfile]; this service
/// contains only the calculation and delay logic.
class NetworkSimulationService {
  NetworkSimulationService._();

  /// Applies simulated latency and upload throttling before a request is sent.
  ///
  /// Throws [SimulatedNetworkException] when [profile.offline] is true.
  static Future<void> applyBeforeRequest(
    NetworkSimulationProfile profile, {
    required int uploadBytes,
  }) async {
    if (profile.offline) {
      throw const SimulatedNetworkException(
        'Simulated offline mode is enabled.',
      );
    }

    if (profile.latencyMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: profile.latencyMs));
    }

    final uploadDelay = _throughputDelay(
      bytes: uploadBytes,
      kbps: profile.uploadKbps,
    );
    if (uploadDelay > Duration.zero) {
      await Future<void>.delayed(uploadDelay);
    }
  }

  /// Applies simulated download throttling after a response is received.
  static Future<void> applyAfterResponse(
    NetworkSimulationProfile profile, {
    required int downloadBytes,
  }) async {
    final delay = _throughputDelay(
      bytes: downloadBytes,
      kbps: profile.downloadKbps,
    );
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  /// Returns the per-chunk delay for streaming responses.
  static Duration throughputDelayForChunk(
    NetworkSimulationProfile profile,
    int chunkBytes,
  ) =>
      _throughputDelay(bytes: chunkBytes, kbps: profile.downloadKbps);

  static Duration _throughputDelay({required int bytes, required int kbps}) {
    if (bytes <= 0 || kbps <= 0) return Duration.zero;
    final ms = (bytes * 8 * 1000 / (kbps * 1000)).ceil();
    return ms <= 0 ? Duration.zero : Duration(milliseconds: ms);
  }
}
