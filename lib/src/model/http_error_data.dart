class HttpErrorData {
  const HttpErrorData({
    required this.type,
    required this.message,
    this.stackTrace,
  });

  final String type;
  final String message;
  final StackTrace? stackTrace;
}
