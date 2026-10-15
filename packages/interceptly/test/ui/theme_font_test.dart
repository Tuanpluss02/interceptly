import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/ui/interceptly_theme.dart';

void main() {
  group('InterceptlyTheme Font Resolution', () {
    test('ThemeData resolves JetBrainsMono with package prefix in text themes',
        () {
      final lightTheme = InterceptlyTheme.lightTheme;
      final darkTheme = InterceptlyTheme.darkTheme;

      expect(lightTheme.textTheme.bodyMedium?.fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
      expect(darkTheme.textTheme.bodyMedium?.fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
    });

    test(
        'InterceptlyTypography styles resolve JetBrainsMono with package prefix',
        () {
      final typography = InterceptlyTheme.typography;

      expect(typography.titleLargeRegular.fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
      expect(typography.bodyMediumRegular.fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
      expect(typography.labelSmallMedium.fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
      expect(typography.monospace().fontFamily,
          equals('packages/interceptly/JetBrainsMono'));
    });
  });
}
