import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/simulation/network_simulation_service.dart';
import 'package:interceptly/src/model/network_simulation.dart';

void main() {
  // ── throughputDelayForChunk ───────────────────────────────────────────────

  group('NetworkSimulationService.throughputDelayForChunk', () {
    test('returns zero when kbps is 0 (no throttling)', () {
      final delay = NetworkSimulationService.throughputDelayForChunk(
        NetworkSimulationProfile.none,
        1024,
      );
      expect(delay, Duration.zero);
    });

    test('returns zero when chunkBytes is 0', () {
      final delay = NetworkSimulationService.throughputDelayForChunk(
        NetworkSimulationProfile.slow3G,
        0,
      );
      expect(delay, Duration.zero);
    });

    test('computes correct delay for known bandwidth', () {
      // 1000 bytes at 1000 kbps:
      // delay_ms = ceil(1000 * 8 * 1000 / (1000 * 1000)) = ceil(8) = 8 ms
      final profile = const NetworkSimulationProfile(
        name: 'test',
        offline: false,
        latencyMs: 0,
        downloadKbps: 1000,
        uploadKbps: 0,
      );
      final delay = NetworkSimulationService.throughputDelayForChunk(
        profile,
        1000,
      );
      expect(delay, const Duration(milliseconds: 8));
    });
  });

  // ── applyBeforeRequest ────────────────────────────────────────────────────

  group('NetworkSimulationService.applyBeforeRequest', () {
    test('throws SimulatedNetworkException when offline', () async {
      expect(
        () async => NetworkSimulationService.applyBeforeRequest(
          NetworkSimulationProfile.offlineProfile,
          uploadBytes: 0,
        ),
        throwsA(isA<SimulatedNetworkException>()),
      );
    });

    test(
      'completes without delay when profile has no latency and no upload throttle',
      () async {
        final sw = Stopwatch()..start();
        await NetworkSimulationService.applyBeforeRequest(
          NetworkSimulationProfile.none,
          uploadBytes: 0,
        );
        sw.stop();
        // No latency, no throttle → should finish nearly instantly
        expect(sw.elapsedMilliseconds, lessThan(50));
      },
    );
  });

  // ── applyAfterResponse ────────────────────────────────────────────────────

  group('NetworkSimulationService.applyAfterResponse', () {
    test('completes without delay when downloadKbps is 0', () async {
      final sw = Stopwatch()..start();
      await NetworkSimulationService.applyAfterResponse(
        NetworkSimulationProfile.none,
        downloadBytes: 1024 * 1024,
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });

    test('completes without delay when downloadBytes is 0', () async {
      final sw = Stopwatch()..start();
      await NetworkSimulationService.applyAfterResponse(
        NetworkSimulationProfile.slow3G,
        downloadBytes: 0,
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  // ── NetworkSimulationProfile helpers ─────────────────────────────────────

  group('NetworkSimulationProfile', () {
    test('isNoThrottling is true for none profile', () {
      expect(NetworkSimulationProfile.none.isNoThrottling, isTrue);
    });

    test('isNoThrottling is false for slow3G', () {
      expect(NetworkSimulationProfile.slow3G.isNoThrottling, isFalse);
    });

    test('isNoThrottling is false when offline=true', () {
      expect(NetworkSimulationProfile.offlineProfile.isNoThrottling, isFalse);
    });

    test('copyWith overrides selected fields', () {
      final p = NetworkSimulationProfile.slow3G.copyWith(latencyMs: 0);
      expect(p.latencyMs, 0);
      expect(p.downloadKbps, NetworkSimulationProfile.slow3G.downloadKbps);
    });

    test('SimulatedNetworkException.toString returns message', () {
      const ex = SimulatedNetworkException('offline');
      expect(ex.toString(), 'offline');
    });

    test('presets contains all built-in profiles', () {
      expect(NetworkSimulationProfile.presets.length, 6);
    });
  });
}
