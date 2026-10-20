import 'package:flutter/foundation.dart';

import 'request_summary.dart';
import 'search_match_scope.dart';

/// Represents a search hit combining the request summary and matched scopes.
@immutable
class SearchResult {
  const SearchResult({
    required this.summary,
    required this.matchScopes,
  });

  /// The summary of the matching network request.
  final RequestSummary summary;

  /// The scopes where the search term was found (e.g. url, headers, body, error).
  final Set<SearchMatchScope> matchScopes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          summary.id == other.summary.id &&
          setEquals(matchScopes, other.matchScopes);

  @override
  int get hashCode => Object.hash(summary.id, Object.hashAll(matchScopes));
}
