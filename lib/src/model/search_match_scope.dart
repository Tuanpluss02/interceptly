/// Represents the locations in a network request where a search query matched.
enum SearchMatchScope {
  url('URL'),
  headers('Headers'),
  body('Body'),
  error('Error');

  const SearchMatchScope(this.label);

  final String label;
}
