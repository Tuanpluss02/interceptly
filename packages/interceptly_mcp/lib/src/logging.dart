import 'dart:io';

/// Logs a message strictly to [stderr], preventing any JSON-RPC stream
/// corruption on [stdout].
void logStderr(String message) {
  stderr.writeln('[interceptly_mcp] $message');
}
