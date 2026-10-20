import 'dart:io';

/// Utility for scanning running local processes to discover Dart tooling endpoints.
class ProcessScanner {
  const ProcessScanner();

  static final RegExp _dtdRegex = RegExp(r'--dtd-uri[=\s]+([^\s]+)');
  static final RegExp _ddsRegex = RegExp(r'--vm-service-uri[=\s]+([^\s]+)');

  /// Retrieves command-line strings of currently running processes on POSIX systems.
  Future<List<String>> getRunningCommandLines() async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('ps', ['-eo', 'command']);
        if (result.exitCode == 0) {
          return (result.stdout as String).split('\n');
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Extracts loopback `--dtd-uri` values from process command-line strings.
  List<Uri> extractDtdUris(Iterable<String> commandLines) {
    final uris = <Uri>[];
    for (final line in commandLines) {
      final match = _dtdRegex.firstMatch(line);
      if (match != null) {
        final uriStr = match.group(1);
        final uri = uriStr != null ? Uri.tryParse(uriStr) : null;
        if (uri != null) uris.add(uri);
      }
    }
    return uris;
  }

  /// Extracts loopback `--vm-service-uri` values from process command-line strings.
  List<Uri> extractDdsUris(Iterable<String> commandLines) {
    final uris = <Uri>[];
    for (final line in commandLines) {
      final match = _ddsRegex.firstMatch(line);
      if (match != null) {
        final uriStr = match.group(1);
        final uri = uriStr != null ? Uri.tryParse(uriStr) : null;
        if (uri != null) uris.add(uri);
      }
    }
    return uris;
  }
}
