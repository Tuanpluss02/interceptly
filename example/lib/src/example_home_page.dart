import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'example_local_server.dart';
import 'example_request_runner.dart';

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

  late final ExampleRequestRunner _runner;

  @override
  void initState() {
    super.initState();
    _runner = ExampleRequestRunner(
      baseUrl: widget.server.baseUrl,
      dio: widget.dio,
      httpClient: widget.httpClient,
      chopperClient: widget.chopperClient,
    );
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
        title: const Text('Interceptly Example'),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // ── Server Status Banner ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 10, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Local Server: ${widget.server.baseUrl}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '100% Offline',
                      style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Section 1: Basic Traffic ──────────────────────────────
            Text(
              'Basic Traffic',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Standard requests served locally (replaces external mockapi.io & httpbin).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('Dio GET /api/users', _runner.runDioGet),
                  child: const Text('Dio GET'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('HTTP GET /api/users', _runner.runHttpGet),
                  child: const Text('HTTP GET'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('Chopper GET /api/users', _runner.runChopperGet),
                  child: const Text('Chopper GET'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _runRequest('Dio Error 503', _runner.runError),
                  icon: const Icon(Icons.error_outline, size: 18),
                  label: const Text('Error 503'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Section 2: Stress Test & Heavy JSON ───────────────────
            Row(
              children: [
                const Icon(Icons.speed, size: 20, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Text(
                  'Stress Test & Heavy JSON',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Test JsonViewer virtualization, deep tree indentation, and memory truncation.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _isLoading ? null : () => _runRequest('Heavy List (3k items)', _runner.runHeavyListGet),
                  child: const Text('Heavy List (~1MB)'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                  onPressed: _isLoading ? null : () => _runRequest('Extreme List (20k items)', _runner.runExtremeListGet),
                  child: const Text('Extreme List (>6MB)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('Deep Nested (35 levels)', _runner.runDeepNestedGet),
                  child: const Text('Deep Nested (35 lvls)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('Wide Text (100k chars)', _runner.runWideTextGet),
                  child: const Text('Wide Text (100k)'),
                ),
                FilledButton.tonal(
                  onPressed: _isLoading ? null : () => _runRequest('Heavy POST (1k items)', _runner.runHeavyPost),
                  child: const Text('Heavy POST (1k)'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _runRequest('Delayed (1.5s)', _runner.runDelayedGet),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Delayed (1.5s)'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Request Status & Results Card ─────────────────────────
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
                          color: _lastResult!.statusCode >= 200 && _lastResult!.statusCode < 300
                              ? Colors.green
                              : Colors.red,
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
                      style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.bug_report, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tap the floating bug icon to open the Interceptly inspector and test JsonViewer rendering, search, and folding.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
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
