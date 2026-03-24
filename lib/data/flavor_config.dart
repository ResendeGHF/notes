// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

class FlavorConfig {
  FlavorConfig._();

  static late String _flavor;
  static String get flavor => _flavor;

  static late String _appStore;
  static String get appStore => _appStore;

  static late bool _shouldCheckForUpdatesByDefault;
  static bool get shouldCheckForUpdatesByDefault =>
      _shouldCheckForUpdatesByDefault;

  static void setup({
    String flavor = '',
    String appStore = '',
    bool shouldCheckForUpdatesByDefault = true,
  }) {
    _flavor = flavor;
    _appStore = appStore;
    _shouldCheckForUpdatesByDefault = shouldCheckForUpdatesByDefault;
  }

  static void setupFromEnvironment() => setup(
    flavor: const String.fromEnvironment('FLAVOR'),
    appStore: const String.fromEnvironment('APP_STORE'),
    shouldCheckForUpdatesByDefault: const bool.fromEnvironment(
      'UPDATE_CHECK',
      defaultValue: true,
    ),
  );
}
