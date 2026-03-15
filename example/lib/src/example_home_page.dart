import 'package:chopper/chopper.dart' as chopper;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'example_request_runner.dart';

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({
    super.key,
    required this.dio,
    required this.httpClient,
    required this.chopperClient,
  });

  final Dio dio;
  final http.Client httpClient;
  final chopper.ChopperClient chopperClient;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  String _status = 'Tap a button to generate network traffic.';
  String _responsePreview = '';
  bool _isLoading = false;

  late final ExampleRequestRunner _runner;

  @override
  void initState() {
    super.initState();
    _runner = ExampleRequestRunner(
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
      _responsePreview = '';
    });

    try {
      final response = await action();
      if (!mounted) return;
      setState(() {
        _status = '$label complete: ${response.statusCode}';
        _responsePreview = response.preview;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '$label failed: $error');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Interceptly Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('Dio GET', _runner.runDioGet),
              child: const Text('Run Dio GET'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('HTTP GET', _runner.runHttpGet),
              child: const Text('Run HTTP GET'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('Chopper GET', _runner.runChopperGet),
              child: const Text('Run Chopper GET'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _runRequest('Dio Error', _runner.runDioError),
              icon: const Icon(Icons.error_outline),
              label: const Text('Run Error Request'),
            ),
            const SizedBox(height: 24),
            if (_responsePreview.isNotEmpty) ...<Widget>[
              Text('Last response',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _responsePreview,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 24),
            ],
            const Text(
              'Use the floating bug button to open the inspector and compare Dio/HTTP/Chopper captures.',
            ),
          ],
        ),
      ),
    );
  }
}
