/// Defines runtime network conditions applied by Interceptly wrappers.
class NetworkSimulationProfile {
  /// Creates a custom network simulation profile.
  const NetworkSimulationProfile({
    required this.name,
    required this.offline,
    required this.latencyMs,
    required this.downloadKbps,
    required this.uploadKbps,
  })  : assert(latencyMs >= 0, 'latencyMs must be non-negative'),
        assert(downloadKbps >= 0, 'downloadKbps must be non-negative'),
        assert(uploadKbps >= 0, 'uploadKbps must be non-negative');

  /// Human-readable profile name shown in the UI.
  final String name;

  /// If true, requests fail immediately as offline.
  final bool offline;

  /// Added round-trip latency in milliseconds.
  final int latencyMs;

  /// Simulated download throughput in kilobits per second.
  final int downloadKbps;

  /// Simulated upload throughput in kilobits per second.
  final int uploadKbps;

  /// True when all throttling parameters effectively disable simulation.
  bool get isNoThrottling =>
      !offline && latencyMs <= 0 && downloadKbps <= 0 && uploadKbps <= 0;

  /// Built-in profile with no artificial latency or throttling.
  static const none = NetworkSimulationProfile(
    name: 'No throttling',
    offline: false,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  /// Built-in profile that simulates offline mode.
  static const offlineProfile = NetworkSimulationProfile(
    name: 'Offline',
    offline: true,
    latencyMs: 0,
    downloadKbps: 0,
    uploadKbps: 0,
  );

  /// Built-in profile roughly matching Slow 3G conditions.
  static const slow3G = NetworkSimulationProfile(
    name: 'Slow 3G',
    offline: false,
    latencyMs: 400,
    downloadKbps: 400,
    uploadKbps: 400,
  );

  /// Built-in profile roughly matching Fast 3G conditions.
  static const fast3G = NetworkSimulationProfile(
    name: 'Fast 3G',
    offline: false,
    latencyMs: 150,
    downloadKbps: 1600,
    uploadKbps: 750,
  );

  /// Built-in profile roughly matching 4G conditions.
  static const fourG = NetworkSimulationProfile(
    name: '4G',
    offline: false,
    latencyMs: 70,
    downloadKbps: 9000,
    uploadKbps: 9000,
  );

  /// Built-in profile roughly matching Wi-Fi conditions.
  static const wifi = NetworkSimulationProfile(
    name: 'Wi-Fi',
    offline: false,
    latencyMs: 30,
    downloadKbps: 30000,
    uploadKbps: 15000,
  );

  /// Ordered list of built-in profiles used by settings UI.
  static const presets = <NetworkSimulationProfile>[
    none,
    offlineProfile,
    slow3G,
    fast3G,
    fourG,
    wifi,
  ];

  /// Returns a copy with selected fields replaced.
  NetworkSimulationProfile copyWith({
    String? name,
    bool? offline,
    int? latencyMs,
    int? downloadKbps,
    int? uploadKbps,
  }) {
    return NetworkSimulationProfile(
      name: name ?? this.name,
      offline: offline ?? this.offline,
      latencyMs: latencyMs ?? this.latencyMs,
      downloadKbps: downloadKbps ?? this.downloadKbps,
      uploadKbps: uploadKbps ?? this.uploadKbps,
    );
  }
}

/// Exception thrown when a request is blocked by simulated offline mode.
class SimulatedNetworkException implements Exception {
  /// Creates a simulation exception with a readable [message].
  const SimulatedNetworkException(this.message);

  /// Message that describes why the simulated failure occurred.
  final String message;

  @override
  String toString() => message;
}
