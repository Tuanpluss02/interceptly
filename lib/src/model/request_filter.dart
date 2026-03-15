import 'request_record.dart';

class RequestFilter {
  // HTTP Methods filter
  final Set<String> methods; // ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']

  // Status code groups
  final bool include2xx; // 200-299
  final bool include3xx; // 300-399
  final bool include4xx; // 400-499
  final bool include5xx; // 500-599

  // Domain filter
  final Set<String> domains; // Selected domains to show

  RequestFilter({
    this.methods = const {},
    this.include2xx = true,
    this.include3xx = true,
    this.include4xx = true,
    this.include5xx = true,
    this.domains = const {},
  });

  /// Check if a request matches all active filters
  bool matches(RequestRecord record) {
    // If methods filter is active, check it
    if (methods.isNotEmpty) {
      if (!methods.contains(record.method.toUpperCase())) {
        return false;
      }
    }

    // Check status code filter
    final statusCode = record.statusCode;
    if (statusCode > 0) {
      final isIncluded =
          (statusCode >= 200 && statusCode < 300 && include2xx) ||
              (statusCode >= 300 && statusCode < 400 && include3xx) ||
              (statusCode >= 400 && statusCode < 500 && include4xx) ||
              (statusCode >= 500 && statusCode < 600 && include5xx);

      if (!isIncluded) {
        return false;
      }
    }

    // Check domain filter
    if (domains.isNotEmpty) {
      final domain = _extractDomain(record.url);
      if (!domains.contains(domain)) {
        return false;
      }
    }

    return true;
  }

  /// Extract domain from URL
  static String extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return 'unknown';
    }
  }

  String _extractDomain(String url) => extractDomain(url);

  /// Check if any filter is active
  bool get isActive {
    return methods.isNotEmpty ||
        !include2xx ||
        !include3xx ||
        !include4xx ||
        !include5xx ||
        domains.isNotEmpty;
  }

  /// Count active filters
  int get activeFilterCount {
    int count = 0;
    if (methods.isNotEmpty) count++;
    if (!include2xx || !include3xx || !include4xx || !include5xx) count++;
    if (domains.isNotEmpty) count++;
    return count;
  }

  /// Copy with new values
  RequestFilter copyWith({
    Set<String>? methods,
    bool? include2xx,
    bool? include3xx,
    bool? include4xx,
    bool? include5xx,
    Set<String>? domains,
  }) {
    return RequestFilter(
      methods: methods ?? this.methods,
      include2xx: include2xx ?? this.include2xx,
      include3xx: include3xx ?? this.include3xx,
      include4xx: include4xx ?? this.include4xx,
      include5xx: include5xx ?? this.include5xx,
      domains: domains ?? this.domains,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestFilter &&
          runtimeType == other.runtimeType &&
          methods == other.methods &&
          include2xx == other.include2xx &&
          include3xx == other.include3xx &&
          include4xx == other.include4xx &&
          include5xx == other.include5xx &&
          domains == other.domains;

  @override
  int get hashCode =>
      methods.hashCode ^
      include2xx.hashCode ^
      include3xx.hashCode ^
      include4xx.hashCode ^
      include5xx.hashCode ^
      domains.hashCode;
}
