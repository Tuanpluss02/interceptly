import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/share/interceptly_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shareFile sends path, mime and origin over channel', () async {
    InterceptlyShare.debugMobileOverride = true;
    addTearDown(() => InterceptlyShare.debugMobileOverride = null);
    Map<String, dynamic>? captured;
    const channel = MethodChannel('dev.stormx.interceptly/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = Map<String, dynamic>.from(call.arguments as Map);
      return true;
    });

    final share = InterceptlyShare();
    final presented = await share.shareFile(
      filePath: '/tmp/request_1.har',
      subject: 'HAR Export',
      text: 'Network request HAR export',
      mimeType: 'application/json',
    );

    expect(presented, isTrue);
    expect(captured?['path'], '/tmp/request_1.har');
    expect(captured?['mimeType'], 'application/json');
    expect(captured?['subject'], 'HAR Export');
  });

  test('shareFile returns false when plugin missing', () async {
    const channel = MethodChannel('dev.stormx.interceptly/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    final share = InterceptlyShare();
    final presented = await share.shareFile(filePath: '/tmp/x.har');
    expect(presented, isFalse);
  });
}
