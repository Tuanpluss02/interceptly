import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'json_viewer_style.dart';

/// Pure, widget-independent helpers for formatting, counting and
/// highlighting search matches in JSON-like data.
///
/// Match counting mirrors exactly how the viewer renders values (strings and
/// keys are counted including their surrounding quotes), so global match
/// indices stay consistent between the search controller and the viewer.
abstract final class JsonSearch {
  /// Format any data into a pretty-printed JSON string.
  ///
  /// Strings that contain valid JSON are decoded and re-indented; anything
  /// that cannot be encoded falls back to `toString()`.
  static String formatData(dynamic data) {
    if (data == null) return 'null';
    try {
      if (data is String) {
        try {
          final decoded = jsonDecode(data);
          return const JsonEncoder.withIndent('  ').convert(decoded);
        } catch (_) {
          return data;
        }
      } else {
        return const JsonEncoder.withIndent('  ').convert(data);
      }
    } catch (e) {
      return data.toString();
    }
  }

  /// Asynchronously formats [data] into pretty-printed JSON,
  /// offloading to [compute] when [data] size or node count exceeds 5,000.
  static Future<String> formatDataAsync(dynamic data) async {
    if (data == null) return 'null';
    if (data is String && data.length > 5000) {
      return compute(_formatWorker, data);
    }
    if (data is List && data.length > 5000) {
      return compute(_formatWorker, data);
    }
    if (data is Map && data.length > 5000) {
      return compute(_formatWorker, data);
    }
    return formatData(data);
  }

  static String _formatWorker(dynamic data) => formatData(data);

  /// Counts case-insensitive [query] matches within structured JSON data.
  static int countMatches(dynamic data, String query) {
    if (query.isEmpty) return 0;
    final q = query.toLowerCase();

    if (data == null) return countIn('null', q);
    if (data is bool) return countIn(data.toString(), q);
    if (data is num) return countIn(data.toString(), q);
    if (data is String) {
      return countIn('"$data"', q);
    }
    if (data is List) {
      int total = 0;
      for (final item in data) {
        total += countMatches(item, query);
      }
      return total;
    }
    if (data is Map) {
      int total = 0;
      for (final entry in data.entries) {
        total += countIn('"${entry.key}"', q);
        total += countMatches(entry.value, query);
      }
      return total;
    }
    return countIn(data.toString(), q);
  }

  /// Counts non-overlapping occurrences of [lowerQuery] in [text]
  /// (case-insensitive).
  static int countIn(String text, String lowerQuery) {
    if (lowerQuery.isEmpty) return 0;
    int count = 0;
    int start = 0;
    final lower = text.toLowerCase();
    while (true) {
      final idx = lower.indexOf(lowerQuery, start);
      if (idx < 0) break;
      count++;
      start = idx + lowerQuery.length;
    }
    return count;
  }

  /// Total matches for every collapsible/leaf node, keyed by JSON path
  /// (e.g. `$`, `$.data`, `$.items[0]`).
  ///
  /// A node's count includes the keys of its direct map entries.
  static Map<String, int> matchCountsByPath(dynamic data, String lowerQuery) {
    if (lowerQuery.isEmpty) return const {};
    final counts = <String, int>{};
    int walk(dynamic value, String path) {
      int total = 0;
      if (value is List) {
        for (var i = 0; i < value.length; i++) {
          total += walk(value[i], '$path[$i]');
        }
      } else if (value is Map) {
        value.forEach((k, v) {
          total += countIn('"$k"', lowerQuery);
          total += walk(v, '$path.$k');
        });
      } else if (value is String) {
        total += countIn('"$value"', lowerQuery);
      } else if (value != null) {
        total += countIn(value.toString(), lowerQuery);
      } else {
        total += countIn('null', lowerQuery);
      }
      counts[path] = total;
      return total;
    }

    walk(data, r'$');
    return counts;
  }

  /// Build highlighted [TextSpan] list for [text], marking query matches.
  ///
  /// [matchOffset] is the global index of the first match within [text].
  /// [activeGlobalIndex] is the currently selected match, painted with
  /// [JsonViewerColors.activeHighlight].
  static List<TextSpan> buildHighlightedSpans(
    String text,
    String lowerQuery,
    int matchOffset,
    int? activeGlobalIndex,
    Color baseColor,
  ) {
    if (lowerQuery.isEmpty) {
      return [
        TextSpan(
          text: text,
          style: TextStyle(color: baseColor),
        ),
      ];
    }
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    int start = 0;
    int currentMatch = matchOffset;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        if (start < text.length) {
          spans.add(
            TextSpan(
              text: text.substring(start),
              style: TextStyle(color: baseColor),
            ),
          );
        }
        break;
      }

      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: TextStyle(color: baseColor),
          ),
        );
      }

      final isActive = currentMatch == activeGlobalIndex;
      currentMatch++;

      spans.add(
        TextSpan(
          text: text.substring(index, index + lowerQuery.length),
          style: TextStyle(
            color: baseColor,
            backgroundColor: isActive
                ? JsonViewerColors.activeHighlight
                : JsonViewerColors.highlight,
          ),
        ),
      );

      start = index + lowerQuery.length;
    }

    return spans;
  }

  /// Whether [span] (or any descendant) is painted as the active match.
  static bool spanHasActiveHighlight(TextSpan span) {
    if (span.style?.backgroundColor == JsonViewerColors.activeHighlight) {
      return true;
    }
    final children = span.children;
    if (children == null || children.isEmpty) return false;
    for (final child in children) {
      if (child is TextSpan && spanHasActiveHighlight(child)) {
        return true;
      }
    }
    return false;
  }
}
