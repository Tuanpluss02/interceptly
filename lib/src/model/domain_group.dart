import 'request_summary.dart';

class DomainGroup {
  final String domain;
  final List<RequestSummary> requests;
  final bool isExpanded;

  DomainGroup({
    required this.domain,
    required this.requests,
    this.isExpanded = true,
  });

  int get requestCount => requests.length;

  int get successCount =>
      requests.where((r) => r.statusCode >= 200 && r.statusCode < 400).length;

  int get errorCount => requests.where((r) => r.statusCode >= 400).length;

  int get warningCount =>
      requests.where((r) => r.statusCode >= 300 && r.statusCode < 400).length;

  bool get hasErrors => errorCount > 0;

  bool get hasWarnings => warningCount > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainGroup &&
          runtimeType == other.runtimeType &&
          domain == other.domain &&
          requests == other.requests &&
          isExpanded == other.isExpanded;

  @override
  int get hashCode => domain.hashCode ^ requests.hashCode ^ isExpanded.hashCode;
}
