import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interceptly/src/share/interceptly_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isWithinTempDirectory validates safe temp paths', () {
    expect(
        InterceptlyShare.isWithinTempDirectory('/tmp/request_1.har'), isTrue);
    expect(InterceptlyShare.isWithinTempDirectory('/private/tmp/file.har'),
        isTrue);
    expect(InterceptlyShare.isWithinTempDirectory('/etc/passwd'), isFalse);
    expect(
        InterceptlyShare.isWithinTempDirectory('/tmp/../etc/passwd'), isFalse);
  });

  test('shareFile throws ArgumentError for path outside temp directory',
      () async {
    final share = InterceptlyShare();
    expect(
      () => share.shareFile(filePath: '/etc/passwd'),
      throwsArgumentError,
    );
  });

  test('shareFile returns false on non-mobile platform or when plugin missing',
      () async {
    const channel = MethodChannel('dev.stormx.interceptly/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    final share = InterceptlyShare();
    final presented = await share.shareFile(filePath: '/tmp/x.har');
    expect(presented, isFalse);
  });
}
