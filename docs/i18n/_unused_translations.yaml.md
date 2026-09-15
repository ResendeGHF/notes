# `i18n/_unused_translations.yaml`

YAML under `lib/i18n/` defines translation strings or metadata for localization. Inline `#` comments in the YAML (if any) describe translator context; prefer editing the `.yaml` sources and regenerating Dart bindings with `dart run slang`.

## File role

- `_missing_translations.yaml` / `_unused_translations.yaml`: slang maintenance lists.
- `*.i18n.yaml`: locale string trees consumed by slang.

## Contents overview

```yaml
"@@info": 
  - Here are translations that exist in secondary locales but not in <en>.
  - "[--full enabled] Furthermore, translations not used in 'lib/' according to the 't.<path>' pattern are written into <en>."
en: 
ar: 
cs: 
de: 
eo: 
es: 
fa: 
fr: 
he: 
hu: 
it: 
ja: 
pt-BR: 
ru: 
tr: 
zh-Hans-CN: 
zh-Hant-TW: 

```
