import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saber/data/flavor_config.dart';

/// Global setup for `flutter test`: bindings, [FlavorConfig], mocked prefs (for [stows] / [Stroke]).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlavorConfig.setup(
    flavor: 'test',
    appStore: '',
    shouldCheckForUpdatesByDefault: false,
  );
  SharedPreferences.setMockInitialValues({});
  await testMain();
}
