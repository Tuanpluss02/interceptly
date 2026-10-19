import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/engine/interceptly_engine.dart';
import 'package:interceptly/src/model/interceptly_settings.dart';
import 'package:interceptly/src/model/network_protocol.dart';
import 'package:interceptly/src/ui/scope/interceptly_scope.dart';
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

    test('shared instance survives and resets cleanly for testing', () {
      final shared1 = InterceptlyPreferences.shared;
      shared1.setSelectedTabIndex(1);
      shared1.setUrlDecodeEnabled(false);

      expect(InterceptlyPreferences.shared.selectedTabIndex, equals(1));
      expect(InterceptlyPreferences.shared.urlDecodeEnabled, isFalse);

      InterceptlyPreferences.resetSharedForTesting();

      expect(InterceptlyPreferences.shared.selectedTabIndex, equals(0));
      expect(InterceptlyPreferences.shared.urlDecodeEnabled, isTrue);
    });
  });

  group('InterceptlyPreferences & ScopeController Integration', () {
    tearDown(() async {
      InterceptlyPreferences.resetSharedForTesting();
    });

    test('ScopeController initializes urlDecodeEnabled from engine settings',
        () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);
      engine.configure(const InterceptlySettings(urlDecodeEnabled: false));

      final controller = InterceptlyScopeController(engine: engine);
      addTearDown(controller.dispose);

      expect(controller.preferences.urlDecodeEnabled, isFalse);
    });

    test('ScopeController preserves shared preferences across screen reopens',
        () {
      final engine = InterceptlyEngine();
      addTearDown(engine.dispose);

      final controller1 = InterceptlyScopeController(engine: engine);
      controller1.preferences.setSelectedTabIndex(1);
      controller1.preferences.setThemeMode(ThemeMode.dark);
      controller1.dispose();

      // Second controller opens (simulating reopening the inspector)
      final controller2 = InterceptlyScopeController(engine: engine);
      addTearDown(controller2.dispose);

      expect(controller2.preferences.selectedTabIndex, equals(1));
      expect(controller2.preferences.themeMode, equals(ThemeMode.dark));
    });
  });
}
