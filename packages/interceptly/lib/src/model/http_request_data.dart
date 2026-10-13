class HttpRequestData {
  const HttpRequestData({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
    this.bodyBytes = 0,
    this.contentType,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final int bodyBytes;
  final String? contentType;

  HttpRequestData copyWith({
    String? method,
    Uri? uri,
    Map<String, String>? headers,
    String? body,
    int? bodyBytes,
    String? contentType,
  }) {
    return HttpRequestData(
      method: method ?? this.method,
      uri: uri ?? this.uri,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      contentType: contentType ?? this.contentType,
    );
  }
}
