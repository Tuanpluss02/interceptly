/// Filter criteria used to narrow visible network calls in the inspector.
class HttpCallFilter {
  /// Creates a filter from optional method, status, host, and text query.
  const HttpCallFilter({
    this.method,
    this.statusCode,
    this.host,
    this.query,
  });

  /// HTTP method to filter by (for example `GET`, `POST`).
  final String? method;

  /// Exact HTTP status code to filter by.
  final int? statusCode;

  /// Hostname filter (for example `api.example.com`).
  final String? host;

  /// Free-text query matched against request metadata.
  final String? query;

  /// True when no filter field is currently set.
  bool get isEmpty {
    return _isBlank(method) &&
        statusCode == null &&
        _isBlank(host) &&
        _isBlank(query);
  }

  /// Creates a new filter with selective field updates.
  ///
  /// Use `clear*` flags to explicitly clear a field to null.
  HttpCallFilter copyWith({
    String? method,
    int? statusCode,
    String? host,
    String? query,
    bool clearMethod = false,
    bool clearStatusCode = false,
    bool clearHost = false,
    bool clearQuery = false,
  }) {
    return HttpCallFilter(
      method: clearMethod ? null : (method ?? this.method),
      statusCode: clearStatusCode ? null : (statusCode ?? this.statusCode),
      host: clearHost ? null : (host ?? this.host),
      query: clearQuery ? null : (query ?? this.query),
    );
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;
}
