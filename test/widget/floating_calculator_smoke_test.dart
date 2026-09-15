import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/toolbar/floating_calculator.dart';
import 'package:saber/i18n/strings.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.en);
  });

  testWidgets('FloatingCalculator mounts first tab', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: Scaffold(
            body: FloatingCalculator(
              onClose: () {},
              onDrag: (_) {},
              onInsertImage: (_, {String? assetFileInfo, bool invertible = false}) {},
            ),
          ),
        ),
      ),
    );
    // Heavy child graphs: avoid pumpAndSettle (animations / tabs).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FloatingCalculator), findsOneWidget);
  });
}
