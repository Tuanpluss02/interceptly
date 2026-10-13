import 'request_summary.dart';

/// Unified filter applied to the inspector request list.
///
/// An empty [RequestFilter] (all defaults) passes every entry through.
/// Use [isEmpty] to cheaply skip filtering when no criteria are set.
class RequestFilter {
  /// HTTP methods to include. An empty set means "include all methods".
  final Set<String> methods;

  /// Status-code range toggles.
  final bool include2xx;
  final bool include3xx;
  final bool include4xx;
  final bool include5xx;

  /// Domain allowlist. An empty set means "include all domains".
  final Set<String> domains;

  /// Hostname substring filter (e.g. `api.example.com`).
  final String? host;

  /// Free-text query matched against URL and error message.
  final String? query;

  RequestFilter({
    Set<String> methods = const {},
    this.include2xx = true,
    this.include3xx = true,
    this.include4xx = true,
    this.include5xx = true,
    Set<String> domains = const {},
    this.host,
    this.query,
  })  : methods = Set.unmodifiable(methods.map((m) => m.toUpperCase()).toSet()),
        domains = Set.unmodifiable(domains);

  /// True when all fields are at their default — no filtering applied.
  bool get isEmpty {
    return methods.isEmpty &&
        include2xx &&
        include3xx &&
        include4xx &&
        include5xx &&
        domains.isEmpty &&
        _isBlank(host) &&
        _isBlank(query);
  }

  /// Returns true if [entry] satisfies every active filter criterion.
  bool matches(RequestSummary entry) {
    if (methods.isNotEmpty) {
      if (!methods.contains(entry.method.toUpperCase())) return false;
    }

    final statusCode = entry.statusCode;
    if (statusCode > 0) {
      final included = (statusCode >= 200 && statusCode < 300 && include2xx) ||
          (statusCode >= 300 && statusCode < 400 && include3xx) ||
          (statusCode >= 400 && statusCode < 500 && include4xx) ||
          (statusCode >= 500 && statusCode < 600 && include5xx);
      if (!included) return false;
    }

    if (domains.isNotEmpty) {
      if (!domains.contains(extractDomain(entry.url))) return false;
    }

    final h = host?.trim().toLowerCase();
    if (h != null && h.isNotEmpty) {
      final uri = Uri.tryParse(entry.url);
      if (uri == null || !uri.host.toLowerCase().contains(h)) return false;
    }

    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      if (entry.url.toLowerCase().contains(q)) return true;
      if (entry.errorMessage?.toLowerCase().contains(q) ?? false) return true;
      return false;
    }

    return true;
  }

  /// Extracts the hostname from [url], or `'unknown'` on parse failure.
  static String extractDomain(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isNotEmpty ? host : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// True when this filter is narrowing results.
  bool get isActive => !isEmpty;

  /// Number of distinct filter groups that are currently active.
  int get activeFilterCount {
    int count = 0;
    if (methods.isNotEmpty) count++;
    if (!include2xx || !include3xx || !include4xx || !include5xx) count++;
    if (domains.isNotEmpty) count++;
    if (!_isBlank(host)) count++;
    if (!_isBlank(query)) count++;
    return count;
  }

  RequestFilter copyWith({
    Set<String>? methods,
    bool? include2xx,
    bool? include3xx,
    bool? include4xx,
    bool? include5xx,
    Set<String>? domains,
    String? host,
    String? query,
    bool clearHost = false,
    bool clearQuery = false,
  }) {
    return RequestFilter(
      methods: methods ?? this.methods,
      include2xx: include2xx ?? this.include2xx,
      include3xx: include3xx ?? this.include3xx,
      include4xx: include4xx ?? this.include4xx,
      include5xx: include5xx ?? this.include5xx,
      domains: domains ?? this.domains,
      host: clearHost ? null : (host ?? this.host),
      query: clearQuery ? null : (query ?? this.query),
    );
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RequestFilter &&
          runtimeType == other.runtimeType &&
          _setsEqual(methods, other.methods) &&
          include2xx == other.include2xx &&
          include3xx == other.include3xx &&
          include4xx == other.include4xx &&
          include5xx == other.include5xx &&
          _setsEqual(domains, other.domains) &&
          host == other.host &&
          query == other.query;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(methods.toList()..sort()),
        include2xx,
        include3xx,
        include4xx,
        include5xx,
        Object.hashAll(domains.toList()..sort()),
        host,
        query,
      );

  static bool _setsEqual(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
