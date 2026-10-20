import 'dart:developer' as developer;

/// Thrown by service extension handlers when a parameter is missing,
/// malformed, or an operation fails.
class ServiceExtensionException implements Exception {
  const ServiceExtensionException(this.errorCode, this.message);

  /// Error code matching [developer.ServiceExtensionResponse] constants.
  final int errorCode;

  /// Error message explaining the failure.
  final String message;

  @override
  String toString() => 'ServiceExtensionException($errorCode): $message';
}

/// Throws a [ServiceExtensionException] if [isEnabled] is false.
void checkServiceExtensionEnabled(bool isEnabled) {
  if (!isEnabled) {
    throw const ServiceExtensionException(
      developer.ServiceExtensionResponse.extensionError,
      'Interceptly extensions are disabled',
    );
  }
}
