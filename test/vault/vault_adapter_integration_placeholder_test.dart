import 'package:flutter_test/flutter_test.dart';

/// [VaultAdapter] needs SQLCipher, platform paths, and optional secure storage.
/// Automated unlock/create/delete tests belong in `integration_test/` with a temp vault directory.
void main() {
  test(
    'VaultAdapter: document manual / integration coverage',
    () {
      expect(true, isTrue);
    },
    skip:
        'Vault unlock and blob I/O require SQLCipher + device filesystem; not run in unit tests.',
  );
}
