class HttpCallFilter {
  const HttpCallFilter({
    this.method,
    this.statusCode,
    this.host,
    this.query,
  });

  final String? method;
  final int? statusCode;
  final String? host;
  final String? query;

  bool get isEmpty {
    return _isBlank(method) &&
        statusCode == null &&
        _isBlank(host) &&
        _isBlank(query);
  }

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
