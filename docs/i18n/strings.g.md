# `lib/i18n/strings.g.dart`

This file is part of the application library under `lib/`. Long-form comments and `///` documentation were moved here from the Dart source to keep implementation files minimal.

## License (REUSE / SPDX)

```text
(no SPDX header in file)
```

## Documentation migrated from source

### Block 1

Generated file. Do not edit.

 Source: lib/i18n
 To regenerate, run: `dart run slang`

### Block 2

Supported locales.

 Usage:
 - LocaleSettings.setLocale(AppLocale.en) // set locale
 - Locale locale = AppLocale.en.flutterLocale // get flutter locale from enum
 - if (LocaleSettings.currentLocale == AppLocale.en) // locale check

### Block 3

Gets current instance managed by [LocaleSettings].

### Block 4

Method A: Simple

 No rebuild after locale change.
 Translation happens during initialization of the widget (call of t).
 Configurable via 'translate_var'.

 Usage:
 String a = t.someKey.anotherKey;

### Block 5

Method B: Advanced

 All widgets using this method will trigger a rebuild when locale changes.
 Use this if you have e.g. a settings page where the user can select the locale during runtime.

 Step 1:
 wrap your App with
 TranslationProvider(
 	child: MyApp()
 );

 Step 2:
 final t = Translations.of(context); // Get t variable.
 String a = t.someKey.anotherKey; // Use t variable.

### Block 6

Method B shorthand via [BuildContext] extension method.
 Configurable via 'translate_var'.

 Usage (e.g. in a widget's build method):
 context.t.someKey.anotherKey

### Block 7

Manages all translation instances and the current locale

### Block 8

Provides utility functions without any side effects.

## Imports

- `package:flutter/widgets.dart`
- `package:intl/intl.dart`
- `package:slang/generated.dart`
- `package:slang_flutter/slang_flutter.dart`
- `strings_pt_BR.g.dart`

## Symbols (heuristic scan)

The following names were detected by a lightweight parse (classes, enums, mixins, extensions, typedefs, and some top-level functions). Private members are mostly omitted.

- `AppLocale`
- `TranslationProvider`
- `BuildContextTranslationsExtension`
- `LocaleSettings`
- `AppLocaleUtils`
- `build()`

## Implementation notes

Read the Dart source at the mirrored path under `lib/` for exact behavior, edge cases, and widget structure. This document stays in sync by path: `docs/...` corresponds to `lib/...` with a `.md` extension instead of `.dart`.
