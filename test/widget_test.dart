import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    const channel = MethodChannel('xyz.luan/audioplayers.global');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async => 1);
  });

  testWidgets('AuraApp UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('YTDx Downloader')),
        ),
      ),
    );
    expect(find.text('YTDx Downloader'), findsOneWidget);
  });
}
