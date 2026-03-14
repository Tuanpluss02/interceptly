// import 'package:flutter_test/flutter_test.dart';

// Copying the logic from _share_handler.dart as it is private and static
String _sanitizeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
}

void main() {
  print('Running tests...');

  // Case 1: Path traversal
  const maliciousMethod = '../../evil';
  final timestamp = DateTime.now().millisecondsSinceEpoch;

  final sanitizedMethod = _sanitizeFilename(maliciousMethod);
  final fileName = 'request_${sanitizedMethod}_$timestamp.har';

  if (fileName.contains('..') || fileName.contains('/')) {
    print('FAILED: Path traversal detected in filename: $fileName');
    return;
  }
  if (!fileName.startsWith('request_______evil_')) {
    print('FAILED: Filename does not match expected prefix: $fileName');
    return;
  }
  print('PASSED: Path traversal fix verified.');

  // Case 2: Other characters
  const specialMethod = 'GET /api/v1';
  final sanitizedMethod2 = _sanitizeFilename(specialMethod);
  if (sanitizedMethod2 != 'GET__api_v1') {
    print('FAILED: Sanitization failed for special characters: $sanitizedMethod2');
    return;
  }
  print('PASSED: Special characters sanitization verified.');

  print('ALL TESTS PASSED!');
}
