import 'package:flutter/material.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';
import 'package:interceptly/src/ui/widgets/error_summary.dart';
import 'package:interceptly/src/ui/widgets/json_viewer/json_viewer.dart';

import '../../model/body_truncation.dart';
import '../../model/request_record.dart';
import 'detail_search.dart';

class DetailTabsBuilder {
  final RequestRecord record;
  final List<DetailMatch> matches;
  final int? activeGlobalIndex;
  final String query;
  final bool urlDecodeEnabled;
  final dynamic Function(String?) tryParseJson;
  final Map<DetailSection, GlobalKey>? sectionKeys;
  final int? scrollTrigger;
  final DateTime Function()? now;

  DetailTabsBuilder({
    required this.record,
    required this.matches,
    required this.activeGlobalIndex,
    required this.query,
    required this.urlDecodeEnabled,
    required this.tryParseJson,
    this.sectionKeys,
    this.scrollTrigger,
    this.now,
  });

  Widget buildOverviewTab() {
    final mStyle = InterceptlyTheme.getMethodStyle(record.method);
    final isPending = record.statusCode == 0 && !record.hasError;
    final isErrorWithoutStatus = record.statusCode == 0 && record.hasError;
    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    String displayUrl = record.url;
    if (urlDecodeEnabled) {
      try {
        displayUrl = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    final String statusValue;
    if (isPending) {
      statusValue = 'Loading';
    } else if (isErrorWithoutStatus) {
      statusValue = 'Error';
    } else {
      statusValue = '${record.statusCode}';
    }

    final String durationValue;
    if (isPending) {
      durationValue = 'loading…';
    } else {
      durationValue = '${record.durationMs} ms';
    }

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildOverviewRow('URL', displayUrl, DetailSection.overviewUrl),
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Method',
            record.method,
            DetailSection.overviewMethod,
            valueStyle: InterceptlyTheme.typography.bodyMediumBold.copyWith(
              color: mStyle.text,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Status',
            statusValue,
            DetailSection.overviewStatus,
          ),
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Duration',
            durationValue,
            DetailSection.overviewDuration,
          ),
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Request size',
            formatBytes(record.requestSizeBytes),
            DetailSection.overviewRequestSize,
          ),
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Response size',
            isPending ? 'loading…' : formatBytes(record.responseSizeBytes),
            DetailSection.overviewResponseSize,
          ),
          if (record.hasError) ...[
            const SizedBox(height: 16),
            _buildOverviewRow(
              'Error',
              shortError,
              DetailSection.overviewError,
              valueStyle:
                  InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.yellow400,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _buildOverviewRow(
            'Time',
            record.timestamp.toIso8601String(),
            DetailSection.overviewTime,
          ),
        ],
      ),
    );
  }

  Widget buildRequestTab() {
    var urlForParsing = record.url;
    if (urlDecodeEnabled) {
      try {
        urlForParsing = Uri.decodeFull(record.url);
      } catch (_) {}
    }

    final uri = Uri.tryParse(urlForParsing);
    final hasQueryParams = uri != null && uri.queryParameters.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Request Headers'),
        _buildJsonBox(record.requestHeaders, DetailSection.requestHeaders),
        const SizedBox(height: 24),
        if (hasQueryParams) ...[
          _buildSectionHeader('Query Parameters'),
          _buildJsonBox(uri.queryParameters, DetailSection.queryParams),
          const SizedBox(height: 24),
        ],
        _buildSectionHeader('Request Body', color: InterceptlyTheme.indigo400),
        _buildBodyPreviewSection(
          contentType: record.requestContentType,
          headers: record.requestHeaders,
          bodyPreview: record.requestBodyPreview,
          truncation: record.requestTruncation,
          section: DetailSection.requestBody,
        ),
      ],
    );
  }

  Widget buildResponseTab() {
    final isPending = record.statusCode == 0 && !record.hasError;
    final isErrorWithoutResponse = record.statusCode == 0 && record.hasError;
    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    if (isPending) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: InterceptlyTheme.indigo500),
            const SizedBox(height: 12),
            Text(
              'Waiting for response...',
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (isErrorWithoutResponse) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              shortError,
              textAlign: TextAlign.center,
              style: InterceptlyTheme.typography.bodyMediumMedium.copyWith(
                color: InterceptlyTheme.yellow400,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              record.errorMessage ??
                  'Request failed before receiving a response.',
              textAlign: TextAlign.center,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                color: InterceptlyTheme.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Response Headers'),
        _buildJsonBox(record.responseHeaders, DetailSection.responseHeaders),
        const SizedBox(height: 24),
        _buildSectionHeader('Response Body', color: InterceptlyTheme.green400),
        _buildBodyPreviewSection(
          contentType: record.responseContentType,
          headers: record.responseHeaders,
          bodyPreview: record.responseBodyPreview,
          truncation: record.responseTruncation,
          section: DetailSection.responseBody,
        ),
      ],
    );
  }

  Widget buildErrorTab() {
    if (!record.hasError) {
      return Center(
        child: Text(
          'No errors for this request.',
          style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
            color: InterceptlyTheme.textMuted,
          ),
        ),
      );
    }

    final shortError = summarizeRequestError(
      errorType: record.errorType,
      errorMessage: record.errorMessage,
    );

    return ListView(
      padding: const EdgeInsets.all(16.0).copyWith(bottom: 100),
      children: [
        _buildSectionHeader('Error Summary', color: InterceptlyTheme.yellow400),
        _buildJsonBox(shortError, DetailSection.errorSummary),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Type', color: InterceptlyTheme.yellow400),
        _buildJsonBox(record.errorType ?? 'None', DetailSection.errorType),
        const SizedBox(height: 24),
        _buildSectionHeader('Error Message', color: InterceptlyTheme.yellow400),
        _buildJsonBox(
          record.errorMessage ?? 'None',
          DetailSection.errorMessage,
        ),
      ],
    );
  }

  Widget _buildOverviewRow(
    String label,
    String value,
    DetailSection section, {
    TextStyle? valueStyle,
  }) {
    final baseStyle = valueStyle ??
        InterceptlyTheme.typography.bodyMediumRegular.copyWith(
          fontSize: 12,
          color: InterceptlyTheme.textSecondary,
        );

    Widget valueWidget;
    if (query.isNotEmpty) {
      final sectionFirstIdx = matches.indexWhere((m) => m.section == section);
      if (sectionFirstIdx >= 0) {
        final spans = JsonViewer.buildHighlightedSpans(
          value,
          query.toLowerCase(),
          sectionFirstIdx,
          activeGlobalIndex,
          baseStyle.color ?? InterceptlyTheme.textSecondary,
        );
        valueWidget = Text.rich(TextSpan(style: baseStyle, children: spans));
      } else {
        valueWidget = Text(value, style: baseStyle);
      }
    } else {
      valueWidget = Text(value, style: baseStyle);
    }

    return Container(
      key: sectionKeys?[section],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                fontSize: 12,
                color: InterceptlyTheme.textMuted,
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _buildBodyPreviewSection({
    required String? contentType,
    required Map<String, String> headers,
    required String? bodyPreview,
    required BodyTruncation truncation,
    required DetailSection section,
  }) {
    final encodingLabel = _buildEncodingLabel(headers);
    final isBinary = _isBinaryPayload(contentType, bodyPreview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTruncationNotice(truncation),
        if (truncation.isTruncated) const SizedBox(height: 8),
        _buildBodyMetaChips(
          contentType: contentType,
          encodingLabel: encodingLabel,
        ),
        if (contentType != null || encodingLabel != null)
          const SizedBox(height: 8),
        isBinary
            ? _buildBinaryPreview(
                contentType: contentType,
                bodyPreview: bodyPreview,
                section: section,
              )
            : _buildJsonBox(
                _formatBodyData(
                  contentType: contentType,
                  bodyPreview: bodyPreview,
                ),
                section,
              ),
      ],
    );
  }

  /// Explains, in place, that this body is shorter than what crossed the wire.
  ///
  /// The wording distinguishes a preview-only cut (nothing is lost — exports
  /// and replay still carry the whole payload) from a storage cut (bytes are
  /// gone for good). Reporting both separately keeps the two failure modes from
  /// reading as one vague warning.
  Widget _buildTruncationNotice(BodyTruncation truncation) {
    if (!truncation.isTruncated) return const SizedBox.shrink();

    final notices = bodyTruncationNotices(truncation);
    if (notices.isEmpty) return const SizedBox.shrink();
    final message = notices.first;

    final isLoss = truncation.hasDataLoss;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isLoss
            ? InterceptlyTheme.yellow400.withValues(alpha: 0.10)
            : InterceptlyTheme.controlMuted.withValues(alpha: 0.20),
        border: Border.all(
          color: isLoss
              ? InterceptlyTheme.yellow400.withValues(alpha: 0.35)
              : InterceptlyTheme.dividerSubtle,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLoss ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 15,
            color: isLoss
                ? InterceptlyTheme.yellow400
                : InterceptlyTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
                fontSize: 11.5,
                height: 1.35,
                color: isLoss
                    ? InterceptlyTheme.yellow400
                    : InterceptlyTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyMetaChips({
    required String? contentType,
    required String? encodingLabel,
  }) {
    if ((contentType == null || contentType.isEmpty) && encodingLabel == null) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (contentType != null && contentType.isNotEmpty)
          _buildMetaChip('content-type: $contentType'),
        if (encodingLabel != null) _buildMetaChip(encodingLabel),
      ],
    );
  }

  Widget _buildMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: InterceptlyTheme.typography.bodyMediumRegular.copyWith(
          fontSize: 11,
          color: InterceptlyTheme.textMuted,
        ),
      ),
    );
  }

  dynamic _formatBodyData({
    required String? contentType,
    required String? bodyPreview,
  }) {
    return formatBodyData(
      contentType: contentType,
      bodyPreview: bodyPreview,
      tryParseJson: tryParseJson,
    );
  }

  bool _isBinaryPayload(String? contentType, String? bodyPreview) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.startsWith('image/') ||
        ct.startsWith('audio/') ||
        ct.startsWith('video/') ||
        ct.contains('application/pdf') ||
        ct.contains('application/octet-stream') ||
        ct.contains('protobuf') ||
        ct.contains('msgpack')) {
      return true;
    }

    if (bodyPreview == null) return false;
    return bodyPreview.startsWith('[binary:') ||
        bodyPreview.startsWith('\x00[binary:');
  }

  Widget _buildBinaryPreview({
    required String? contentType,
    required String? bodyPreview,
    required DetailSection section,
  }) {
    final kind = _binaryKind(contentType);
    final meta = <String, dynamic>{
      'kind': kind,
      'contentType': contentType ?? 'unknown',
      'sizeBytes': _extractBinarySize(bodyPreview),
    };
    return _buildJsonBox(meta, section);
  }

  String _binaryKind(String? contentType) {
    final ct = (contentType ?? '').toLowerCase();
    if (ct.startsWith('image/')) return 'image';
    if (ct.contains('application/pdf')) return 'pdf';
    if (ct.contains('protobuf')) return 'protobuf';
    if (ct.contains('msgpack')) return 'msgpack';
    return 'binary';
  }

  int? _extractBinarySize(String? preview) {
    if (preview == null) return null;
    final m = RegExp(r'\[binary:\s*(\d+)\s*bytes\]').firstMatch(preview);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  String? _buildEncodingLabel(Map<String, String> headers) {
    final encoding = _headerValue(headers, 'content-encoding');
    if (encoding == null || encoding.trim().isEmpty) return null;
    return 'content-encoding: $encoding';
  }

  String? _headerValue(Map<String, String> headers, String key) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
    }
    return null;
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title.toUpperCase(),
        style: InterceptlyTheme.typography.bodyMediumBold.copyWith(
          fontSize: 12,
          color: color ?? InterceptlyTheme.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildJsonBox(dynamic data, DetailSection section) {
    int matchOffset = matches.indexWhere((m) => m.section == section);
    if (matchOffset < 0) matchOffset = 0;

    return Container(
      key: sectionKeys?[section],
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(0, 12.0, 12.0, 4.0),
      decoration: BoxDecoration(
        color: InterceptlyTheme.surfaceContainer,
        border: Border.all(color: InterceptlyTheme.dividerSubtle),
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: JsonViewer(
        data: data,
        searchQuery: query.isEmpty ? null : query,
        matchOffset: matchOffset,
        activeGlobalIndex: activeGlobalIndex,
        scrollTrigger: scrollTrigger,
      ),
    );
  }
}
