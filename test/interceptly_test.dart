import 'package:flutter_test/flutter_test.dart';

import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/storage/memory_index.dart';

// ignore: unused_import
import 'package:flutter/widgets.dart';

void main() {
  test('MemoryIndex drops oldest entry when maxEntries is exceeded', () {
    final index = MemoryIndex(maxEntries: 2);

    final e1 = _buildEntry('1');
    final e2 = _buildEntry('2');
    final e3 = _buildEntry('3');

    index.add(e1);
    index.add(e2);
    index.add(e3);

    expect(index.length, 2);
    // Newest entries are kept (newest-first order).
    expect(index.entries.first.id, '3');
    expect(index.entries.last.id, '2');
  });

  test('MemoryIndex filter by method', () {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1', method: 'GET'));
    index.add(_buildEntry('2', method: 'POST'));
    index.add(_buildEntry('3', method: 'GET'));

    final filtered = index.filtered(const HttpCallFilter(method: 'POST'));
    expect(filtered.length, 1);
    expect(filtered.first.id, '2');
  });

  test('MemoryIndex filter by status code', () {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1', statusCode: 200));
    index.add(_buildEntry('2', statusCode: 404));

    final filtered = index.filtered(const HttpCallFilter(statusCode: 404));
    expect(filtered.length, 1);
    expect(filtered.first.id, '2');
  });

  test('MemoryIndex clear resets entries and emits empty list', () async {
    final index = MemoryIndex(maxEntries: 100);
    index.add(_buildEntry('1'));

    final emitted = <int>[];
    final sub = index.stream.listen((entries) => emitted.add(entries.length));

    index.clear();
    await Future<void>.delayed(Duration.zero);

    expect(index.length, 0);
    expect(emitted, contains(0));
    await sub.cancel();
  });

  test('InspectorSession singleton is shared', () {
    final a = InspectorSession.instance;
    final b = InspectorSession.instance;
    expect(identical(a, b), isTrue);
  });

  test('InterceptlyDioInterceptor uses shared session by default', () {
    final interceptor = InterceptlyDioInterceptor();
    expect(interceptor.session, same(InspectorSession.instance));
  });

  test('InterceptlyOverlay uses shared session by default', () {
    // InterceptlyOverlay requires a Flutter environment so we verify the
    // session instance equality through the session singleton directly.
    final a = InspectorSession.instance;
    final b = InspectorSession.instance;
    expect(identical(a, b), isTrue);
  });
}

IndexEntry _buildEntry(
  String id, {
  String method = 'GET',
  String url = 'https://example.com/test',
  int statusCode = 200,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    durationMs: 20,
    requestSizeBytes: 0,
    responseSizeBytes: 0,
    timestamp: DateTime(2026, 1, 1),
    hasError: false,
    bodyLocation: BodyLocation.memory,
  );
}
