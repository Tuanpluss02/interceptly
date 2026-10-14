import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:interceptly/interceptly.dart';

import 'example_local_server.dart';
import 'example_request_runner.dart';
import 'example_truncation_presets.dart';

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({
    super.key,
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
    required this.server,
  });

  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;
  final ExampleLocalServer server;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  String _status = 'Select any test case below to generate network traffic.';
  ExampleRequestResult? _lastResult;
  bool _isLoading = false;
  String _presetId = truncationPresets.first.id;

  late final ExampleRequestRunner _runner;

  TruncationPreset get _preset =>
      truncationPresets.firstWhere((p) => p.id == _presetId);

  @override
  void initState() {
    super.initState();
    _runner = ExampleRequestRunner(
      baseUrl: widget.server.baseUrl,
      dio: widget.dio,
      httpClient: widget.httpClient,
      chopperClient: widget.chopperClient,
    );
    _applyPreset(truncationPresets.first);
  }

  /// Size caps only affect captures recorded after they are applied, so the
  /// preset has to be chosen before firing the request under test.
  void _applyPreset(TruncationPreset preset) {
    InspectorSession.instance.configureSession(preset.toSettings());
  }

  Future<void> _runRequest(
    String label,
    Future<ExampleRequestResult> Function() action,
  ) async {
    setState(() {
      _isLoading = true;
      _status = 'Running $label...';
      _lastResult = null;
    });

    try {
      final response = await action();
      if (!mounted) return;
      setState(() {
        _status = '$label completed';
        _lastResult = response;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '$label failed: $error';
        _lastResult = null;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAll() async {
    await Interceptly.instance.clear();
    if (!mounted) return;
    setState(() {
      _status = 'Cleared all recorded requests in Interceptly.';
      _lastResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All recorded requests cleared from Interceptly.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interceptly Showcase'),
        elevation: 1,
        actions: [
          IconButton(
            tooltip: 'Clear Recorded Requests',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearAll,
          ),
          FilledButton.tonalIcon(
            onPressed: () => Interceptly.showInspector(context),
            icon: const Icon(Icons.bug_report, size: 18),
            label: const Text('Inspector'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Local Server: \n${widget.server.baseUrl}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _buildSectionHeader(
              title: 'RESTful Methods & Status Codes',
              subtitle:
                  'Test GET, POST 201, PUT, PATCH, DELETE 204, 400, 401, 404, 503 badges.',
              color: Colors.blue,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest('Dio GET (200)', _runner.runDioGet),
                  child: const Text('Dio GET 200'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest('HTTP GET (200)', _runner.runHttpGet),
                  child: const Text('HTTP GET 200'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Chopper GET (200)', _runner.runChopperGet),
                  child: const Text('Chopper GET 200'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('POST User (201)', _runner.runPostUser),
                  child: const Text('POST (201 Created)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest('PUT User (200)', _runner.runPutUser),
                  child: const Text('PUT (200)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('PATCH User (200)', _runner.runPatchUser),
                  child: const Text('PATCH (200)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'DELETE User (204)', _runner.runDeleteUser),
                  child: const Text('DELETE (204 No Content)'),
                ),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Bad Request (400)', _runner.run400BadRequest),
                  child: const Text('400 Bad Request'),
                ),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Unauthorized (401)', _runner.run401Unauthorized),
                  child: const Text('401 Unauthorized'),
                ),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Not Found (404)', _runner.run404NotFound),
                  child: const Text('404 Not Found'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('Server Error (503)', _runner.runError),
                  icon: const Icon(Icons.error_outline, size: 18),
                  label: const Text('503 Error'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(
              title: 'Specialized Formats & Viewers',
              subtitle:
                  'Test GraphQL Operation parsing, Multipart FormData summary, and Binary Image preview.',
              color: Colors.purple,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('GraphQL Query', _runner.runGraphQLQuery),
                  child: const Text('GraphQL Query'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'GraphQL Mutation', _runner.runGraphQLMutation),
                  child: const Text('GraphQL Mutation'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Multipart Upload', _runner.runMultipartUpload),
                  child: const Text('Multipart Upload (FormData)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Binary Image (PNG)', _runner.runGetImage),
                  child: const Text('Binary Image (PNG)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('Vector Image (SVG)', _runner.runGetSvg),
                  child: const Text('Vector Image (SVG)'),
                ),
              ],
            ),
            _buildSectionHeader(
              title: 'Realtime WebSocket Traffic',
              subtitle:
                  'Test bidirectional WebSocket connection, live frame streaming (Text & JSON), and connection teardown.',
              color: Colors.indigo,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'WebSocket Echo', _runner.runWebSocketEcho),
                  icon: const Icon(Icons.sync_alt, size: 18),
                  label: const Text('WebSocket Echo (Connect & Stream)'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(
              title: 'URL Filtering',
              subtitle: 'Verify URL blacklist exclusion via shouldCapture filter.',
              color: Colors.teal,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Analytics Request', _runner.runAnalyticsRequest),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Analytics (Filtered by shouldCapture)'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionHeader(
              title: 'Stress Test & Heavy Payloads',
              subtitle:
                  'Test JsonViewer virtualization, deep nesting, and memory truncation.',
              color: Colors.deepOrange,
            ),
            _buildPresetSelector(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Heavy List (3k items)', _runner.runHeavyListGet),
                  child: const Text('Heavy List (~1MB)'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange),
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest('Extreme List (20k items)',
                          _runner.runExtremeListGet),
                  child: const Text('Extreme List (>6MB Truncate)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Deep Nested (35 levels)', _runner.runDeepNestedGet),
                  child: const Text('Deep Nested (35 lvls)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Wide Text (100k chars)', _runner.runWideTextGet),
                  child: const Text('Wide Text (100k)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () => _runRequest(
                          'Heavy POST (1k items)', _runner.runHeavyPost),
                  child: const Text('Heavy POST (1k)'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () =>
                          _runRequest('Delayed (1.5s)', _runner.runDelayedGet),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Delayed (1.5s)'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (_isLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            Text(_status, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),

            if (_lastResult != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Badge(
                          label: 'Status ${_lastResult!.statusCode}',
                          color: _lastResult!.statusCode >= 200 &&
                                  _lastResult!.statusCode < 300
                              ? Colors.green
                              : (_lastResult!.statusCode >= 400 &&
                                      _lastResult!.statusCode < 500
                                  ? Colors.orange
                                  : Colors.red),
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          label: '${_lastResult!.durationMs} ms',
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _Badge(
                          label: _lastResult!.formattedBytes,
                          color: Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _lastResult!.preview,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  /// Lets a tester switch the size caps before firing a request, so every
  /// truncation stage can be observed without restarting the app.
  Widget _buildPresetSelector() {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 16, color: Colors.deepOrange),
                const SizedBox(width: 6),
                Text(
                  'Size limits preset',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Caps apply to requests captured after you pick them. Choose a '
              'preset, then fire "Extreme List (>6MB Truncate)".',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in truncationPresets)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: preset.id == _presetId,
                    onSelected: (_) {
                      setState(() => _presetId = preset.id);
                      _applyPreset(preset);
                      setState(() {
                        _status =
                            'Preset "${preset.label}" applied — maxBodyBytes '
                            '${_formatMb(preset.maxBodyBytes)}, '
                            'maxUiPreviewBytes ${_formatMb(preset.maxUiPreviewBytes)}';
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expected notice',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _preset.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMb(int bytes) {
    if (bytes <= 0) return 'unlimited';
    if (bytes >= 1024 * 1024) {
      return '${bytes ~/ (1024 * 1024)} MB';
    }
    return '${bytes ~/ 1024} KB';
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
