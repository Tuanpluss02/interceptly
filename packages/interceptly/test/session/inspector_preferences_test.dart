import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/model/network_protocol.dart';
import 'package:interceptly/src/ui/settings/inspector_preferences.dart';

void main() {
  group('InterceptlyPreferences', () {
    late InterceptlyPreferences prefs;

    setUp(() {
      prefs = InterceptlyPreferences();
    });

    test('initializes with default values', () {
      expect(prefs.themeMode, equals(ThemeMode.system));
      expect(prefs.urlDecodeEnabled, isTrue);
      expect(prefs.selectedTabIndex, equals(0));
      expect(prefs.selectedProtocol, equals(NetworkProtocol.rest));
    });

    test('setSelectedTabIndex updates value and notifies listeners', () {
      var notifications = 0;
      prefs.addListener(() => notifications++);

      prefs.setSelectedTabIndex(1);
      expect(prefs.selectedTabIndex, equals(1));
      expect(prefs.selectedProtocol, equals(NetworkProtocol.realtime));
      expect(notifications, equals(1));

      // Duplicate value does not notify
      prefs.setSelectedTabIndex(1);
      expect(notifications, equals(1));

      prefs.setSelectedTabIndex(0);
      expect(prefs.selectedTabIndex, equals(0));
      expect(prefs.selectedProtocol, equals(NetworkProtocol.rest));
      expect(notifications, equals(2));
    });

    test('setSelectedProtocol maps correctly to selectedTabIndex', () {
      prefs.setSelectedProtocol(NetworkProtocol.realtime);
      expect(prefs.selectedTabIndex, equals(1));
      expect(prefs.selectedProtocol, equals(NetworkProtocol.realtime));

      prefs.setSelectedProtocol(NetworkProtocol.rest);
      expect(prefs.selectedTabIndex, equals(0));
      expect(prefs.selectedProtocol, equals(NetworkProtocol.rest));
    });
  });
}
