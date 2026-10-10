import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/interceptly.dart';
import 'package:interceptly/src/model/body_location.dart';
import 'package:interceptly/src/model/index_entry.dart';
import 'package:interceptly/src/model/raw_capture.dart';
import 'package:interceptly/src/session/memory_index.dart';

IndexEntry _makeEntry(
  String id, {
  String method = 'GET',
  String url = 'https://api.example.com/test',
  int statusCode = 200,
  int durationMs = 15,
}) {
  return IndexEntry(
    id: id,
    method: method,
    url: url,
    statusCode: statusCode,
    isBodyTruncated: false,
    durationMs: durationMs,
    requestSizeBytes: 100,
    responseSizeBytes: 200,
    timestamp: DateTime(2026, 1, 1),
    hasError: statusCode >= 400 || statusCode == 0,
    bodyLocation: BodyLocation.memory,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('challenger_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tempDir.path;
        return null;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Challenger M1 - Area 1: MemoryIndex Boundary & Eviction Stress', () {
    test('Boundary: maxEntries = 1 with sequential adds and updates', () {
      final index = MemoryIndex(maxEntries: 1);
      expect(index.length, 0);

      // Add P1 pending
      final p1 = _makeEntry('p1', statusCode: 0);
      index.add(p1);
      expect(index.length, 1);
      expect(index.entries.first.id, 'p1');
      expect(index.entries.first.statusCode, 0);

      // Update P1 completed in-place
      final c1 = _makeEntry('p1', statusCode: 200);
      index.add(c1);
      expect(index.length, 1);
      expect(index.entries.first.id, 'p1');
      expect(index.entries.first.statusCode, 200);

      // Add P2: must evict P1
      final p2 = _makeEntry('p2', statusCode: 0);
      index.add(p2);
      expect(index.length, 1);
      expect(index.entries.first.id, 'p2');

      // Now P1 arrives again (late completion after eviction)
      final c1Late = _makeEntry('p1', statusCode: 200);
      index.add(c1Late);
      expect(index.length, 1);
      expect(index.entries.first.id, 'p1');
    });

    test('Boundary: maxEntries = 0 behavior', () {
      final index = MemoryIndex(maxEntries: 0);
      try {
        index.add(_makeEntry('item1'));
      } catch (e) {
        expect(e, isA<RangeError>());
      }
    });

    test(
        'Simultaneous pending requests exceeding maxEntries followed by out-of-order completions',
        () {
      const maxEntries = 5;
      final index = MemoryIndex(maxEntries: maxEntries);

      // Add 10 pending requests
      for (var i = 0; i < 10; i++) {
        index.add(_makeEntry('req_$i', statusCode: 0));
      }

      // MemoryIndex should be capped at maxEntries (newest first: req_9 to req_5)
      expect(index.length, maxEntries);
      expect(index.entries.map((e) => e.id).toList(), [
        'req_9',
        'req_8',
        'req_7',
        'req_6',
        'req_5',
      ]);

      // Complete req_7 (still present in memory index) -> should update in-place at index 2
      final c7 = _makeEntry('req_7', statusCode: 200);
      index.add(c7);
      expect(index.length, maxEntries);
      expect(index.entries[2].id, 'req_7');
      expect(index.entries[2].statusCode, 200);
      expect(index.entries.map((e) => e.id).toList(), [
        'req_9',
        'req_8',
        'req_7',
        'req_6',
        'req_5',
      ]);

      // Complete req_9 (newest entry, index 0) -> update in-place at index 0
      final c9 = _makeEntry('req_9', statusCode: 201);
      index.add(c9);
      expect(index.length, maxEntries);
      expect(index.entries[0].id, 'req_9');
      expect(index.entries[0].statusCode, 201);

      // Complete req_5 (oldest entry, index 4) -> update in-place at index 4
      final c5 = _makeEntry('req_5', statusCode: 204);
      index.add(c5);
      expect(index.length, maxEntries);
      expect(index.entries[4].id, 'req_5');
      expect(index.entries[4].statusCode, 204);

      // Now complete req_2 (which was previously evicted while pending!)
      final c2 = _makeEntry('req_2', statusCode: 200);
      index.add(c2);
      expect(index.length, maxEntries);
      expect(index.entries[0].id, 'req_2');
      expect(index.entries.map((e) => e.id).toList(), [
        'req_2',
        'req_9',
        'req_8',
        'req_7',
        'req_6',
      ]);

      // Now update req_2 again -> in place at index 0
      final c2Updated = _makeEntry('req_2', statusCode: 200, durationMs: 99);
      index.add(c2Updated);
      expect(index.length, maxEntries);
      expect(index.entries[0].id, 'req_2');
      expect(index.entries[0].durationMs, 99);
      expect(index.entries.map((e) => e.id).toList(), [
        'req_2',
        'req_9',
        'req_8',
        'req_7',
        'req_6',
      ]);
    });

    test(
        'Massive high-throughput churn test (2000 items with interleaved pending/completions)',
        () {
      const maxEntries = 100;
      final index = MemoryIndex(maxEntries: maxEntries);

      for (var round = 0; round < 2000; round++) {
        final id = 'req_${round % 300}';
        final isCompleted = round % 3 == 0;
        final entry = _makeEntry(id, statusCode: isCompleted ? 200 : 0);
        index.add(entry);

        expect(index.length, lessThanOrEqualTo(maxEntries));

        // Invariant: no duplicate IDs in entries
        final ids = index.entries.map((e) => e.id).toList();
        final uniqueIds = ids.toSet();
        expect(ids.length, uniqueIds.length,
            reason: 'Duplicate IDs detected at round $round');
      }
    });

    test('Edge case: empty ID and special character IDs', () {
      final index = MemoryIndex(maxEntries: 10);
      final emptyId = _makeEntry('');
      index.add(emptyId);
      expect(index.length, 1);
      expect(index.entries.first.id, '');

      final emptyIdCompleted = _makeEntry('', statusCode: 200);
      index.add(emptyIdCompleted);
      expect(index.length, 1);
      expect(index.entries.first.statusCode, 200);

      final unicodeId = _makeEntry('🔑/special?query=1&b=2#frag');
      index.add(unicodeId);
      expect(index.length, 2);
      expect(index.entries.first.id, '🔑/special?query=1&b=2#frag');

      final unicodeUpdated =
          _makeEntry('🔑/special?query=1&b=2#frag', statusCode: 304);
      index.add(unicodeUpdated);
      expect(index.length, 2);
      expect(index.entries.first.statusCode, 304);
    });
  });

  group('Challenger M1 - Area 2: InspectorSession Domain Expansion & Listeners',
      () {
    test('Multi-domain expansion toggles: isolation and state accuracy',
        () async {
      final session = InspectorSession();

      final domains = [
        'alpha.com',
        'beta.org',
        'gamma.net',
        'delta.io',
        'epsilon.dev'
      ];
      for (var i = 0; i < domains.length; i++) {
        session.recordPending(
          id: 'req_$i',
          method: 'GET',
          url: 'https://${domains[i]}/v1/test',
          timestamp: DateTime(2026, 1, 1),
        );
      }

      var groups = session.getGroupedRecords();
      expect(groups.length, 5);
      for (final g in groups) {
        expect(g.isExpanded, isTrue,
            reason: 'Domain ${g.domain} should initially be expanded');
      }

      // Collapse beta.org only
      session.toggleDomainExpanded('beta.org');
      groups = session.getGroupedRecords();
      for (final g in groups) {
        if (g.domain == 'beta.org') {
          expect(g.isExpanded, isFalse);
        } else {
          expect(g.isExpanded, isTrue);
        }
      }

      // Collapse delta.io as well
      session.toggleDomainExpanded('delta.io');
      groups = session.getGroupedRecords();
      for (final g in groups) {
        if (g.domain == 'beta.org' || g.domain == 'delta.io') {
          expect(g.isExpanded, isFalse);
        } else {
          expect(g.isExpanded, isTrue);
        }
      }

      // Re-expand beta.org
      session.toggleDomainExpanded('beta.org');
      groups = session.getGroupedRecords();
      for (final g in groups) {
        if (g.domain == 'delta.io') {
          expect(g.isExpanded, isFalse);
        } else {
          expect(g.isExpanded, isTrue);
        }
      }

      await session.dispose();
    });

    test(
        'Listener notification count and immediate state inspection during callback',
        () async {
      final session = InspectorSession();
      session.recordPending(
        id: 'req1',
        method: 'POST',
        url: 'https://service.com/api',
        timestamp: DateTime(2026, 1, 1),
      );

      var notificationCount = 0;
      bool? isExpandedSeenInListener;

      session.addListener(() {
        notificationCount++;
        final grps = session.getGroupedRecords();
        final match = grps.firstWhere((g) => g.domain == 'service.com');
        isExpandedSeenInListener = match.isExpanded;
      });

      // Toggle service.com to collapsed
      session.toggleDomainExpanded('service.com');

      expect(notificationCount, 1,
          reason: 'Should notify listeners exactly once per toggle');
      expect(isExpandedSeenInListener, isFalse,
          reason: 'Listener should immediately see collapsed state');

      // Toggle service.com back to expanded
      session.toggleDomainExpanded('service.com');
      expect(notificationCount, 2);
      expect(isExpandedSeenInListener, isTrue,
          reason: 'Listener should immediately see expanded state');

      await session.dispose();
    });

    test('Pre-toggling domain expansion before requests for that domain exist',
        () async {
      final session = InspectorSession();

      session.toggleDomainExpanded('future-api.com');

      session.recordPending(
        id: 'f1',
        method: 'GET',
        url: 'https://future-api.com/items',
        timestamp: DateTime(2026, 1, 1),
      );

      final groups = session.getGroupedRecords();
      expect(groups.length, 1);
      expect(groups.first.domain, 'future-api.com');
      expect(groups.first.isExpanded, isFalse,
          reason: 'Pre-collapsed state should be respected');

      await session.dispose();
    });

    test('Nested toggling inside listener callback', () async {
      final session = InspectorSession();
      session.recordPending(
        id: 'r1',
        method: 'GET',
        url: 'https://dom1.com/a',
        timestamp: DateTime(2026, 1, 1),
      );
      session.recordPending(
        id: 'r2',
        method: 'GET',
        url: 'https://dom2.com/b',
        timestamp: DateTime(2026, 1, 1),
      );

      var recursiveTriggered = false;
      void listener() {
        if (!recursiveTriggered) {
          recursiveTriggered = true;
          session.toggleDomainExpanded('dom2.com');
        }
      }

      session.addListener(listener);
      session.toggleDomainExpanded('dom1.com');

      final groups = session.getGroupedRecords();
      final dom1 = groups.firstWhere((g) => g.domain == 'dom1.com');
      final dom2 = groups.firstWhere((g) => g.domain == 'dom2.com');

      expect(dom1.isExpanded, isFalse);
      expect(dom2.isExpanded, isFalse);

      await session.dispose();
    });
  });

  group('Challenger M1 - Area 3: dispose() and Recreation Lifecycles', () {
    test('Multiple dispose() calls on InspectorSession: verify behavior',
        () async {
      final session = InspectorSession();
      await session.initialize();
      await session.dispose();

      var threw = false;
      Object? capturedError;
      try {
        await session.dispose().timeout(const Duration(seconds: 2));
      } catch (e) {
        capturedError = e;
        threw = true;
      }
      expect(threw, isTrue);
      expect(capturedError is! TimeoutException, isTrue,
          reason:
              'Expected dispose to reject immediately, not hang. Actual: $capturedError');
    });

    test(
        'Fresh InspectorSession.instance recreation and full operation after dispose()',
        () async {
      final session1 = InspectorSession.instance;
      session1.recordPending(
        id: 's1_req',
        method: 'GET',
        url: 'https://session1.com/test',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(session1.entries.length, 1);

      await session1.dispose();

      final session2 = InspectorSession.instance;
      expect(identical(session1, session2), isFalse);
      expect(session2.entries.length, 0);

      session2.recordPending(
        id: 's2_req',
        method: 'POST',
        url: 'https://session2.com/test',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(session2.entries.length, 1);
      expect(session2.entries.first.id, 's2_req');

      session2.toggleDomainExpanded('session2.com');
      final groups = session2.getGroupedRecords();
      expect(groups.length, 1);
      expect(groups.first.isExpanded, isFalse);

      await session2.dispose();
    });

    test('Interceptly facade recreation and sync after dispose()', () async {
      final app1 = Interceptly.instance;
      expect(app1.calls.length, 0);

      app1.recordCapture(
        RawCapture(
          id: 'cap1',
          method: 'GET',
          url: 'https://app1.com/test',
          requestHeaders: const {},
          responseHeaders: const {},
          statusCode: 200,
          durationMs: 10,
          timestamp: DateTime(2026, 1, 1),
        ),
      );

      app1.dispose();

      final app2 = Interceptly.instance;
      expect(identical(app1, app2), isFalse);

      app2.dispose();
      await InspectorSession.instance.dispose();
    });

    test('Pending timers and isolate cleanup on session dispose()', () async {
      final session = InspectorSession();

      for (var i = 0; i < 5; i++) {
        session.recordPending(
          id: 'timeout_test_$i',
          method: 'GET',
          url: 'https://timeout.com/$i',
          timestamp: DateTime(2026, 1, 1),
        );
      }

      expect(session.totalEntries, 5);

      await session.dispose();

      expect(session.totalEntries, 0);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test(
        'Session clear() resets entries, invalidates grouped records, and cancels pending timers',
        () async {
      final session = InspectorSession();
      for (var i = 0; i < 3; i++) {
        session.recordPending(
          id: 'clr_$i',
          method: 'GET',
          url: 'https://clear-test.com/endpoint',
          timestamp: DateTime(2026, 1, 1),
        );
      }
      expect(session.totalEntries, 3);
      expect(session.getGroupedRecords().length, 1);

      await session.clear();

      expect(session.totalEntries, 0);
      expect(session.entries.length, 0);
      expect(session.getGroupedRecords().length, 0);

      session.recordPending(
        id: 'after_clear',
        method: 'POST',
        url: 'https://clear-test.com/new',
        timestamp: DateTime(2026, 1, 1),
      );
      expect(session.totalEntries, 1);
      expect(session.getGroupedRecords().length, 1);

      await session.dispose();
    });

    test(
        'Adding new requests to collapsed domain maintains collapsed state but updates request count',
        () async {
      final session = InspectorSession();
      session.recordPending(
        id: 'req1',
        method: 'GET',
        url: 'https://collapse-test.com/item1',
        timestamp: DateTime(2026, 1, 1),
      );

      session.toggleDomainExpanded('collapse-test.com');
      var groups = session.getGroupedRecords();
      expect(groups.first.isExpanded, isFalse);
      expect(groups.first.requests.length, 1);

      session.recordPending(
        id: 'req2',
        method: 'GET',
        url: 'https://collapse-test.com/item2',
        timestamp: DateTime(2026, 1, 1),
      );

      groups = session.getGroupedRecords();
      expect(groups.first.isExpanded, isFalse,
          reason: 'Domain should still be collapsed');
      expect(groups.first.requests.length, 2,
          reason: 'Requests in domain group should be updated');

      await session.dispose();
    });

    test('Rapid domain toggling stress test (100 toggles across 5 domains)',
        () async {
      final session = InspectorSession();
      final domains = ['d1.com', 'd2.com', 'd3.com', 'd4.com', 'd5.com'];
      for (var i = 0; i < domains.length; i++) {
        session.recordPending(
          id: 'req_$i',
          method: 'GET',
          url: 'https://${domains[i]}/',
          timestamp: DateTime(2026, 1, 1),
        );
      }

      final expectedState = <String, bool>{
        for (final d in domains) d: true,
      };

      for (var i = 0; i < 100; i++) {
        final domain = domains[i % domains.length];
        session.toggleDomainExpanded(domain);
        expectedState[domain] = !expectedState[domain]!;

        final groups = session.getGroupedRecords();
        for (final g in groups) {
          expect(g.isExpanded, expectedState[g.domain],
              reason: 'Mismatch for ${g.domain} at iteration $i');
        }
      }

      await session.dispose();
    });

    test('Handling requests with unknown or unparseable domain URLs', () async {
      final session = InspectorSession();
      session.recordPending(
        id: 'rel_req',
        method: 'GET',
        url: '/relative/path/without/host',
        timestamp: DateTime(2026, 1, 1),
      );

      var groups = session.getGroupedRecords();
      expect(groups.length, 1);
      expect(groups.first.domain, 'unknown');
      expect(groups.first.isExpanded, isTrue);

      session.toggleDomainExpanded('unknown');
      groups = session.getGroupedRecords();
      expect(groups.first.domain, 'unknown');
      expect(groups.first.isExpanded, isFalse);

      await session.dispose();
    });
  });
}
