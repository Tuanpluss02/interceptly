class HttpResponseData {
  const HttpResponseData({
    required this.statusCode,
    required this.headers,
    this.body,
    this.bodyBytes = 0,
    this.contentType,
    this.durationMs,
  });

  final int? statusCode;
  final Map<String, String> headers;
  final String? body;
  final int bodyBytes;
  final String? contentType;
  final int? durationMs;

  HttpResponseData copyWith({
    int? statusCode,
    Map<String, String>? headers,
    String? body,
    int? bodyBytes,
    String? contentType,
    int? durationMs,
  }) {
    return HttpResponseData(
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      contentType: contentType ?? this.contentType,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
