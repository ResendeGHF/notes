// SPDX-FileCopyrightText: 2026 Muse Spark <https://github.com/anomalyco/opencode>
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CSS subset used by the EPUB renderer. Stylesheets are parsed with
// `package:csslib`; selectors are compiled into a small matcher and the
// declarations of every supported property are cascaded in document order
// (source order plus specificity). Anything unsupported is ignored, and
// malformed CSS never aborts a conversion.

// csslib is pulled in through the pdf package rather than declared directly.
// ignore_for_file: depend_on_referenced_packages

import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart';
import 'package:html/dom.dart' as dom;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// CSS pixels to PDF points (CSS assumes 96dpi).
const kCssPxToPt = 0.75;

/// CSS-wide keywords that must not be treated as concrete values.
const _cssWideKeywords = {
  'inherit',
  'initial',
  'unset',
  'revert',
  'revert-layer',
};

/// Properties the renderer understands. Everything else is dropped while
/// parsing so the cascade stays cheap.
const _supportedProperties = {
  'display',
  'font-weight',
  'font-style',
  'font-size',
  'color',
  'background-color',
  'text-align',
  'line-height',
  'margin-top',
  'margin-right',
  'margin-bottom',
  'margin-left',
  'padding-top',
  'padding-right',
  'padding-bottom',
  'padding-left',
  'text-decoration',
  'list-style-type',
  'white-space',
  'page-break-before',
  'page-break-after',
  'break-before',
  'break-after',
  'vertical-align',
};

/// A selector that has been compiled into the subset the renderer can match.
class EpubCssSelector {
  EpubCssSelector._(this._parts);

  /// Compounds ordered as written (left to right).
  final List<_CssCompound> _parts;

  /// Rightmost element name for cheap pre-filtering (null means wildcard).
  String? get keyTag => _parts.last.tag;

  /// Rightmost id for cheap pre-filtering.
  String? get keyId => _parts.last.id;

  /// Rightmost class names for cheap pre-filtering.
  List<String> get keyClasses => _parts.last.classes;

  /// Compiles a csslib selector, or returns null when it uses constructs the
  /// renderer does not support (the rule is then dropped).
  static EpubCssSelector? tryCompile(Selector selector) {
    final parts = <_CssCompound>[];
    for (final sequence in selector.simpleSelectorSequences) {
      final compound = _compileSimple(sequence.simpleSelector);
      if (compound == null) return null;
      parts.add(compound.withCombinator(_combinatorOf(sequence)));
    }
    if (parts.isEmpty) return null;
    return EpubCssSelector._(parts);
  }

  /// Whether [element] matches this selector.
  bool matches(dom.Element element) => _matchesAt(element, _parts.length - 1);

  bool _matchesAt(dom.Element element, int index) {
    if (!_parts[index].matches(element)) return false;
    if (index == 0) return true;
    switch (_parts[index].combinator) {
      case _combinatorChild:
        final parent = element.parent;
        return parent is dom.Element && _matchesAt(parent, index - 1);
      case _combinatorAdjacent:
        final previous = element.previousElementSibling;
        return previous != null && _matchesAt(previous, index - 1);
      case _combinatorSibling:
        for (var sibling = element.previousElementSibling;
            sibling != null;
            sibling = sibling.previousElementSibling) {
          if (_matchesAt(sibling, index - 1)) return true;
        }
        return false;
      case _combinatorDescendant:
      default:
        for (var parent = element.parent;
            parent is dom.Element;
            parent = parent.parent) {
          if (_matchesAt(parent, index - 1)) return true;
        }
        return false;
    }
  }

  int specificity() {
    var a = 0;
    var b = 0;
    var c = 0;
    for (final part in _parts) {
      if (part.id != null) a++;
      b += part.classes.length + part.attributes.length + part.pseudos.length;
      if (part.negation != null) b++;
      if (part.tag != null) c++;
    }
    return a * 10000 + b * 100 + c;
  }

  static int _combinatorOf(SimpleSelectorSequence sequence) {
    if (sequence.isCombinatorGreater) return _combinatorChild;
    if (sequence.isCombinatorPlus) return _combinatorAdjacent;
    if (sequence.isCombinatorTilde) return _combinatorSibling;
    if (sequence.isCombinatorDescendant) return _combinatorDescendant;
    return _combinatorNone;
  }

  static _CssCompound? _compileSimple(SimpleSelector selector) {
    if (selector is ElementSelector) {
      final name = selector.name.toLowerCase();
      return _CssCompound(tag: name == '*' ? null : name);
    }
    if (selector is ClassSelector) {
      return _CssCompound(classes: [selector.name.toLowerCase()]);
    }
    if (selector is IdSelector) {
      return _CssCompound(id: selector.name);
    }
    if (selector is AttributeSelector) {
      final attribute = _CssAttribute.tryCompile(selector);
      return attribute == null ? null : _CssCompound(attributes: [attribute]);
    }
    if (selector is PseudoClassSelector) {
      final pseudo = _CssPseudo.tryCompile(selector);
      if (pseudo == null) return null;
      return _CssCompound(pseudos: [pseudo]);
    }
    if (selector is NamespaceSelector) {
      final inner = selector.nameAsSimpleSelector;
      if (inner == null) return null;
      return _compileSimple(inner);
    }
    if (selector is Wildcard) {
      return _CssCompound();
    }
    return null;
  }
}

const _combinatorNone = 0;
const _combinatorDescendant = 1;
const _combinatorChild = 2;
const _combinatorAdjacent = 3;
const _combinatorSibling = 4;

class _CssCompound {
  _CssCompound({
    this.tag,
    this.id,
    this.classes = const [],
    this.attributes = const [],
    this.pseudos = const [],
    this.negation,
    this.combinator = _combinatorNone,
  });

  final String? tag;
  final String? id;
  final List<String> classes;
  final List<_CssAttribute> attributes;
  final List<_CssPseudo> pseudos;
  final EpubCssSelector? negation;
  final int combinator;

  _CssCompound withCombinator(int value) => _CssCompound(
    tag: tag,
    id: id,
    classes: classes,
    attributes: attributes,
    pseudos: pseudos,
    negation: negation,
    combinator: value,
  );

  bool matches(dom.Element element) {
    if (tag != null && element.localName != tag) return false;
    if (id != null && element.id != id) return false;
    for (final className in classes) {
      if (!element.classes.contains(className)) return false;
    }
    for (final attribute in attributes) {
      if (!attribute.matches(element)) return false;
    }
    for (final pseudo in pseudos) {
      if (!pseudo.matches(element)) return false;
    }
    final negated = negation;
    if (negated != null && negated.matches(element)) return false;
    return true;
  }
}

class _CssAttribute {
  _CssAttribute(this.name, this.operator, this.expected);

  final String name;
  final String operator;
  final String expected;

  static _CssAttribute? tryCompile(AttributeSelector selector) {
    final name = selector.name.toLowerCase();
    final operator = selector.matchOperator() ?? '';
    final raw = selector.value;
    final expected = raw is Identifier
        ? raw.name
        : raw
              .toString()
              .replaceAll('"', '')
              .replaceAll("'", '');
    return _CssAttribute(name, operator, expected);
  }

  bool matches(dom.Element element) {
    final value = element.attributes[name];
    if (value == null) return false;
    switch (operator) {
      case '=':
        return value == expected;
      case '~=':
        return value.split(RegExp(r'\s+')).contains(expected);
      case '|=':
        return value == expected || value.startsWith('$expected-');
      case '^=':
        return expected.isNotEmpty && value.startsWith(expected);
      case r'$=':
        return expected.isNotEmpty && value.endsWith(expected);
      case '*=':
        return expected.isNotEmpty && value.contains(expected);
      default:
        return false;
    }
  }
}

class _CssPseudo {
  _CssPseudo(this.name);

  /// `first-child`, `last-child`, `root` and `only-child` are supported;
  /// unsupported pseudo classes match nothing so that dynamic rules such as
  /// `:hover` do not leak into the static PDF.
  final String name;

  static _CssPseudo? tryCompile(PseudoClassSelector selector) {
    final name = selector.name.toLowerCase();
    if (name == 'first-child' ||
        name == 'last-child' ||
        name == 'root' ||
        name == 'only-child') {
      return _CssPseudo(name);
    }
    return null;
  }

  bool matches(dom.Element element) {
    switch (name) {
      case 'first-child':
        return element.previousElementSibling == null;
      case 'last-child':
        return element.nextElementSibling == null;
      case 'only-child':
        return element.previousElementSibling == null &&
            element.nextElementSibling == null;
      case 'root':
        return element.parent is! dom.Element;
      default:
        return false;
    }
  }
}

/// One CSS rule: a selector list plus the winnowed declarations.
class EpubCssRule {
  EpubCssRule({
    required this.selectors,
    required this.declarations,
    required this.specificity,
    required this.order,
  });

  final List<EpubCssSelector> selectors;
  final Map<String, String> declarations;
  final int specificity;
  final int order;
}

/// Parsed author stylesheets for one XHTML document.
class EpubCssStylesheet {
  final rules = <EpubCssRule>[];

  final _byTag = <String, List<EpubCssRule>>{};
  final _byClass = <String, List<EpubCssRule>>{};
  final _byId = <String, List<EpubCssRule>>{};
  final _universal = <EpubCssRule>[];

  var _order = 0;

  bool get isEmpty => rules.isEmpty;

  /// Parses [cssText] and appends its rules.
  ///
  /// [loadImport] optionally resolves `@import` URIs to additional CSS text.
  void add(String cssText, {String? Function(String uri)? loadImport}) {
    if (cssText.trim().isEmpty) return;
    StyleSheet sheet;
    try {
      sheet = csslib.parse(cssText);
    } catch (_) {
      return;
    }
    _addTopLevels(sheet.topLevels, loadImport, 0);
  }

  void _addTopLevels(
    List<TreeNode> nodes,
    String? Function(String uri)? loadImport,
    int depth,
  ) {
    for (final node in nodes) {
      try {
        if (node is RuleSet) {
          _addRuleSet(node);
        } else if (node is MediaDirective) {
          if (_mediaApplies(node)) {
            _addTopLevels(node.rules, loadImport, depth);
          }
        } else if (node is ImportDirective && loadImport != null && depth < 8) {
          final uri = node.import;
          if (uri.isEmpty) continue;
          final imported = loadImport(uri);
          if (imported == null) continue;
          add(imported, loadImport: loadImport);
        }
      } catch (_) {
        // A single broken rule never stops the rest of the stylesheet.
      }
    }
  }

  static bool _mediaApplies(MediaDirective directive) {
    if (directive.mediaQueries.isEmpty) return true;
    for (final query in directive.mediaQueries) {
      if (!query.hasMediaType) return true;
      final type = query.mediaType.toLowerCase();
      if (type == 'all' || type == 'print' || type == 'screen') return true;
    }
    return false;
  }

  void _addRuleSet(RuleSet ruleSet) {
    final declarations = _extractDeclarations(ruleSet.declarationGroup);
    if (declarations.isEmpty) return;
    final group = ruleSet.selectorGroup;
    if (group == null) return;
    final compiled = <EpubCssSelector>[];
    var specificity = 0;
    for (final selector in group.selectors) {
      final result = EpubCssSelector.tryCompile(selector);
      if (result == null) continue;
      compiled.add(result);
      final value = result.specificity();
      if (value > specificity) specificity = value;
    }
    if (compiled.isEmpty) return;
    final rule = EpubCssRule(
      selectors: compiled,
      declarations: declarations,
      specificity: specificity,
      order: _order++,
    );
    rules.add(rule);
    for (final selector in compiled) {
      final tag = selector.keyTag;
      if (tag != null) {
        (_byTag[tag] ??= []).add(rule);
      }
      final id = selector.keyId;
      if (id != null) {
        (_byId[id] ??= []).add(rule);
      }
      if (selector.keyClasses.isEmpty) {
        if (tag == null && id == null) _universal.add(rule);
      } else {
        for (final className in selector.keyClasses) {
          (_byClass[className] ??= []).add(rule);
        }
      }
    }
  }

  /// Cascaded declarations for [element] (later declarations win).
  Map<String, String> declarationsFor(dom.Element element) {
    if (rules.isEmpty) return const <String, String>{};
    final candidates = <EpubCssRule>{};
    candidates.addAll(_universal);
    final tag = element.localName;
    final byTag = _byTag[tag];
    if (byTag != null) candidates.addAll(byTag);
    final id = element.id;
    if (id.isNotEmpty) {
      final byId = _byId[id];
      if (byId != null) candidates.addAll(byId);
    }
    for (final className in element.classes) {
      final byClass = _byClass[className];
      if (byClass != null) candidates.addAll(byClass);
    }
    if (candidates.isEmpty) return const <String, String>{};

    final matched = <EpubCssRule>[];
    for (final rule in candidates) {
      for (final selector in rule.selectors) {
        if (selector.matches(element)) {
          matched.add(rule);
          break;
        }
      }
    }
    if (matched.isEmpty) return const <String, String>{};
    matched.sort((a, b) {
      final bySpecificity = a.specificity.compareTo(b.specificity);
      if (bySpecificity != 0) return bySpecificity;
      return a.order.compareTo(b.order);
    });
    final out = <String, String>{};
    for (final rule in matched) {
      out.addAll(rule.declarations);
    }
    return out;
  }

  /// Parses an inline `style="..."` attribute into declarations.
  static Map<String, String> parseInlineStyle(String styleAttribute) {
    if (styleAttribute.trim().isEmpty) return const <String, String>{};
    try {
      final sheet = csslib.parse('x{$styleAttribute}');
      for (final node in sheet.topLevels) {
        if (node is RuleSet) {
          return _extractDeclarations(node.declarationGroup);
        }
      }
    } catch (_) {
      // Ignore malformed inline styles.
    }
    return const <String, String>{};
  }

  static Map<String, String> _extractDeclarations(DeclarationGroup group) {
    final raw = <String, String>{};
    for (final node in group.declarations) {
      if (node is! Declaration) continue;
      final entry = _declarationParts(node);
      if (entry == null) continue;
      raw[entry.$1] = entry.$2;
    }
    return _canonicalize(raw);
  }

  static (String, String)? _declarationParts(Declaration declaration) {
    final property = declaration.property.trim().toLowerCase();
    if (property.isEmpty || !RegExp(r'^[a-z][a-z0-9\-]*$').hasMatch(property)) {
      return null;
    }
    var value = '';
    final source = declaration.span.text;
    final colon = source.indexOf(':');
    if (colon >= 0 && colon + 1 < source.length) {
      value = source.substring(colon + 1);
    }
    if (value.isEmpty) {
      value = _expressionText(declaration.expression) ?? '';
    }
    value = value.trim();
    final lower = value.toLowerCase();
    if (lower.endsWith('!important')) {
      value = value.substring(0, value.length - '!important'.length).trim();
    } else if (lower.endsWith('! important')) {
      value = value.substring(0, value.length - '! important'.length).trim();
    }
    if (value.isEmpty) return null;
    return (property, value);
  }

  static String? _expressionText(Expression? expression) {
    if (expression == null) return null;
    if (expression is UnitTerm) {
      return '${expression.text}${expression.unitToString() ?? ''}';
    }
    if (expression is LiteralTerm) return expression.text;
    if (expression is Expressions) {
      final parts = <String>[];
      for (final item in expression.expressions) {
        final text = _expressionText(item);
        if (text == null) return null;
        parts.add(text);
      }
      return parts.join(' ');
    }
    return null;
  }

  static Map<String, String> _canonicalize(Map<String, String> raw) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final property = entry.key;
      final value = entry.value;
      switch (property) {
        case 'margin':
          _expandBox(out, 'margin', value);
        case 'padding':
          _expandBox(out, 'padding', value);
        case 'background':
          if (cssColor(value) != null) out['background-color'] = value;
        default:
          if (_supportedProperties.contains(property)) out[property] = value;
      }
    }
    return out;
  }

  static void _expandBox(
    Map<String, String> out,
    String prefix,
    String value,
  ) {
    final parts = _splitTopLevel(value);
    if (parts.isEmpty || parts.length > 4) return;
    for (final part in parts) {
      if (_cssWideKeywords.contains(part.toLowerCase())) return;
    }
    String top;
    String right;
    String bottom;
    String left;
    switch (parts.length) {
      case 1:
        top = right = bottom = left = parts[0];
      case 2:
        top = bottom = parts[0];
        right = left = parts[1];
      case 3:
        top = parts[0];
        right = left = parts[1];
        bottom = parts[2];
      default:
        top = parts[0];
        right = parts[1];
        bottom = parts[2];
        left = parts[3];
    }
    out['$prefix-top'] = top;
    out['$prefix-right'] = right;
    out['$prefix-bottom'] = bottom;
    out['$prefix-left'] = left;
  }

  /// Splits a shorthand value on whitespace that is not inside parentheses.
  static List<String> _splitTopLevel(String value) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    for (final rune in value.runes) {
      if (rune == 0x28) depth++;
      if (rune == 0x29 && depth > 0) depth--;
      if (depth == 0 && (rune == 0x20 || rune == 0x09 || rune == 0x0A)) {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.writeCharCode(rune);
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts;
  }

}

/// The computed style of one element.
///
/// Inherited properties keep the parent value unless overridden; all other
/// properties reset to their initial value on every element.
class EpubStyle {
  const EpubStyle({
    required this.fontSize,
    required this.color,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.lineThrough = false,
    this.superscript = false,
    this.subscript = false,
    this.background,
    this.textAlign,
    this.lineHeightFactor = 1.45,
    this.whiteSpacePre = false,
    this.display,
    this.marginTop = 0,
    this.marginRight = 0,
    this.marginBottom = 0,
    this.marginLeft = 0,
    this.paddingTop = 0,
    this.paddingRight = 0,
    this.paddingBottom = 0,
    this.paddingLeft = 0,
    this.listStyleType,
    this.breakBefore = false,
    this.breakAfter = false,
  });

  factory EpubStyle.initial({required double fontSize}) =>
      EpubStyle(fontSize: fontSize, color: PdfColors.black);

  /// Font size in points.
  final double fontSize;

  final bool bold;
  final bool italic;

  /// `text-decoration` is treated as inherited so nested inline styles keep
  /// the decoration of their ancestors (as browsers paint it).
  final bool underline;
  final bool lineThrough;

  final bool superscript;
  final bool subscript;

  final PdfColor color;
  final PdfColor? background;
  final pw.TextAlign? textAlign;
  final double lineHeightFactor;
  final bool whiteSpacePre;

  /// Author/default `display` value (`none`, `block`, `inline`,
  /// `list-item`), or null when the element's tag decides.
  final String? display;

  final double marginTop;
  final double marginRight;
  final double marginBottom;
  final double marginLeft;

  final double paddingTop;
  final double paddingRight;
  final double paddingBottom;
  final double paddingLeft;

  final String? listStyleType;

  final bool breakBefore;
  final bool breakAfter;

  bool get hasMargins =>
      marginTop != 0 ||
      marginRight != 0 ||
      marginBottom != 0 ||
      marginLeft != 0;

  bool get hasPaddings =>
      paddingTop != 0 ||
      paddingRight != 0 ||
      paddingBottom != 0 ||
      paddingLeft != 0;

  /// Returns a new style with [declarations] applied on top of this one.
  EpubStyle apply(
    Map<String, String> declarations, {
    required double rootFontSize,
    double percentBase = 0,
  }) {
    if (declarations.isEmpty) return this;

    var fontSize = this.fontSize;
    final rawFontSize = declarations['font-size'];
    if (rawFontSize != null) {
      fontSize =
          cssFontSizeToPt(rawFontSize, parentPt: this.fontSize, rootPt: rootFontSize) ??
          fontSize;
    }

    final rawWeight = declarations['font-weight'];
    final bold = rawWeight == null ? this.bold : isCssBoldWeight(rawWeight);

    final rawStyle = declarations['font-style'];
    final italic = rawStyle == null
        ? this.italic
        : rawStyle.trim().toLowerCase() == 'italic' ||
              rawStyle.trim().toLowerCase() == 'oblique';

    var underline = this.underline;
    var lineThrough = this.lineThrough;
    final rawDecoration = declarations['text-decoration'];
    if (rawDecoration != null) {
      final value = rawDecoration.toLowerCase();
      if (value.contains('none')) {
        underline = false;
        lineThrough = false;
      } else {
        if (value.contains('underline')) underline = true;
        if (value.contains('line-through')) lineThrough = true;
      }
    }

    final rawColor = declarations['color'];
    final color = rawColor == null ? this.color : (cssColor(rawColor) ?? this.color);

    final background = declarations.containsKey('background-color')
        ? cssColor(declarations['background-color']!)
        : null;

    final rawAlign = declarations['text-align'];
    final textAlign = rawAlign == null
        ? this.textAlign
        : (cssTextAlign(rawAlign) ?? this.textAlign);

    var lineHeightFactor = this.lineHeightFactor;
    final rawLineHeight = declarations['line-height'];
    if (rawLineHeight != null) {
      lineHeightFactor =
          cssLineHeightFactor(rawLineHeight, fontSize: fontSize) ??
          lineHeightFactor;
    }

    var whiteSpacePre = this.whiteSpacePre;
    final rawWhiteSpace = declarations['white-space'];
    if (rawWhiteSpace != null) {
      final value = rawWhiteSpace.toLowerCase().trim();
      if (value.contains('pre')) whiteSpacePre = true;
      if (value == 'normal' || value == 'nowrap') whiteSpacePre = false;
    }

    final display = declarations.containsKey('display')
        ? cssDisplay(declarations['display']!)
        : null;

    var superscript = this.superscript;
    var subscript = this.subscript;
    final rawVerticalAlign = declarations['vertical-align'];
    if (rawVerticalAlign != null) {
      switch (rawVerticalAlign.trim().toLowerCase()) {
        case 'super':
          superscript = true;
          subscript = false;
        case 'sub':
          superscript = false;
          subscript = true;
        case 'baseline':
        case 'middle':
        case 'top':
        case 'bottom':
        case 'text-top':
        case 'text-bottom':
          superscript = false;
          subscript = false;
      }
    }

    final listStyleType = declarations.containsKey('list-style-type')
        ? declarations['list-style-type']!.trim().toLowerCase()
        : this.listStyleType;

    return EpubStyle(
      fontSize: fontSize,
      color: color,
      bold: bold,
      italic: italic,
      underline: underline,
      lineThrough: lineThrough,
      superscript: superscript,
      subscript: subscript,
      background: background,
      textAlign: textAlign,
      lineHeightFactor: lineHeightFactor,
      whiteSpacePre: whiteSpacePre,
      display: display,
      marginTop: _length(declarations, 'margin-top', fontSize, percentBase) ?? 0,
      marginRight:
          _length(declarations, 'margin-right', fontSize, percentBase) ?? 0,
      marginBottom:
          _length(declarations, 'margin-bottom', fontSize, percentBase) ?? 0,
      marginLeft:
          _length(declarations, 'margin-left', fontSize, percentBase) ?? 0,
      paddingTop:
          _length(declarations, 'padding-top', fontSize, percentBase) ?? 0,
      paddingRight:
          _length(declarations, 'padding-right', fontSize, percentBase) ?? 0,
      paddingBottom:
          _length(declarations, 'padding-bottom', fontSize, percentBase) ?? 0,
      paddingLeft:
          _length(declarations, 'padding-left', fontSize, percentBase) ?? 0,
      listStyleType: listStyleType,
      breakBefore: _break(declarations, const [
        'break-before',
        'page-break-before',
      ]),
      breakAfter: _break(declarations, const [
        'break-after',
        'page-break-after',
      ]),
    );
  }

  static double? _length(
    Map<String, String> declarations,
    String property,
    double fontSize,
    double percentBase,
  ) {
    final raw = declarations[property];
    if (raw == null) return null;
    return cssLengthToPt(raw, fontSize: fontSize, percentBase: percentBase);
  }

  static bool _break(Map<String, String> declarations, List<String> keys) {
    for (final key in keys) {
      final raw = declarations[key];
      if (raw == null) continue;
      final value = raw.trim().toLowerCase();
      if (value.startsWith('always') ||
          value.startsWith('page') ||
          value.startsWith('left') ||
          value.startsWith('right')) {
        return true;
      }
    }
    return false;
  }
}

/// The built-in (user-agent) styles for common HTML elements.
const kEpubUserAgentStyles = {
  'html': {'display': 'block'},
  'body': {'display': 'block', 'margin': '8px'},
  'div': {'display': 'block'},
  'p': {'display': 'block', 'margin': '1em 0'},
  'section': {'display': 'block'},
  'article': {'display': 'block'},
  'aside': {'display': 'block'},
  'header': {'display': 'block'},
  'footer': {'display': 'block'},
  'main': {'display': 'block'},
  'nav': {'display': 'block'},
  'address': {'display': 'block', 'font-style': 'italic'},
  'h1': {
    'display': 'block',
    'font-size': '2em',
    'font-weight': 'bold',
    'margin': '0.67em 0',
  },
  'h2': {
    'display': 'block',
    'font-size': '1.5em',
    'font-weight': 'bold',
    'margin': '0.83em 0',
  },
  'h3': {
    'display': 'block',
    'font-size': '1.17em',
    'font-weight': 'bold',
    'margin': '1em 0',
  },
  'h4': {
    'display': 'block',
    'font-weight': 'bold',
    'margin': '1.33em 0',
  },
  'h5': {
    'display': 'block',
    'font-size': '0.83em',
    'font-weight': 'bold',
    'margin': '1.67em 0',
  },
  'h6': {
    'display': 'block',
    'font-size': '0.67em',
    'font-weight': 'bold',
    'margin': '2.33em 0',
  },
  'blockquote': {'display': 'block', 'margin': '1em 40px'},
  'pre': {
    'display': 'block',
    'white-space': 'pre',
    'margin': '1em 0',
  },
  'ul': {
    'display': 'block',
    'margin': '1em 0',
    'padding-left': '40px',
    'list-style-type': 'disc',
  },
  'ol': {
    'display': 'block',
    'margin': '1em 0',
    'padding-left': '40px',
    'list-style-type': 'decimal',
  },
  'li': {'display': 'list-item'},
  'dl': {'display': 'block', 'margin': '1em 0'},
  'dt': {'display': 'block'},
  'dd': {'display': 'block', 'margin-left': '40px'},
  'figure': {'display': 'block', 'margin': '1em 40px'},
  'figcaption': {'display': 'block', 'text-align': 'center', 'font-size': '0.9em'},
  'hr': {'display': 'block', 'margin': '0.5em 0'},
  'center': {'display': 'block', 'text-align': 'center'},
  'a': {'text-decoration': 'underline'},
  'b': {'font-weight': 'bold'},
  'strong': {'font-weight': 'bold'},
  'i': {'font-style': 'italic'},
  'em': {'font-style': 'italic'},
  'cite': {'font-style': 'italic'},
  'dfn': {'font-style': 'italic'},
  'u': {'text-decoration': 'underline'},
  'ins': {'text-decoration': 'underline'},
  's': {'text-decoration': 'line-through'},
  'strike': {'text-decoration': 'line-through'},
  'del': {'text-decoration': 'line-through'},
  'sup': {'vertical-align': 'super', 'font-size': 'smaller'},
  'sub': {'vertical-align': 'sub', 'font-size': 'smaller'},
  'small': {'font-size': '0.83em'},
  'big': {'font-size': '1.17em'},
  'mark': {'background-color': 'yellow'},
  'table': {'display': 'block'},
  'caption': {'display': 'block', 'text-align': 'center'},
  'thead': {'display': 'block'},
  'tbody': {'display': 'block'},
  'tfoot': {'display': 'block'},
  'tr': {'display': 'block'},
  'td': {'display': 'block'},
  'th': {'display': 'block', 'font-weight': 'bold'},
  'form': {'display': 'block'},
  'fieldset': {'display': 'block'},
  'details': {'display': 'block'},
  'summary': {'display': 'block'},
  'iframe': {'display': 'none'},
  'object': {'display': 'none'},
  'embed': {'display': 'none'},
  'canvas': {'display': 'none'},
  'video': {'display': 'none'},
  'audio': {'display': 'none'},
  'script': {'display': 'none'},
  'style': {'display': 'none'},
  'head': {'display': 'none'},
  'title': {'display': 'none'},
  'meta': {'display': 'none'},
  'link': {'display': 'none'},
  'base': {'display': 'none'},
  'template': {'display': 'none'},
  'noscript': {'display': 'none'},
};

/// HTML elements rendered as blocks when neither CSS nor the UA styles decide.
const _defaultBlockTags = {
  'blockquote',
  'dd',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figure',
  'figcaption',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hr',
  'main',
  'nav',
  'ol',
  'p',
  'pre',
  'section',
  'table',
  'ul',
};

/// Whether [tag] is block-level by default.
bool isDefaultBlockTag(String tag) => _defaultBlockTags.contains(tag);

/// Resolves a CSS length to points.
///
/// Percentages resolve against [percentBase] (0 means unsupported).
double? cssLengthToPt(
  String raw, {
  required double fontSize,
  double? percentBase,
}) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (value == 'auto' ||
      value == 'none' ||
      value == 'normal' ||
      value.startsWith('calc(') ||
      value.startsWith('var(') ||
      value.startsWith('min(') ||
      value.startsWith('max(') ||
      value.startsWith('clamp(')) {
    return null;
  }
  if (_cssWideKeywords.contains(value)) return null;
  final match = RegExp(
    r'^([+-]?(?:\d+\.?\d*|\.\d+))\s*(px|pt|pc|in|cm|mm|q|em|rem|ex|ch|%)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return null;
  switch (match.group(2) ?? '') {
    case 'px':
      return number * kCssPxToPt;
    case 'pt':
      return number;
    case 'pc':
      return number * 12;
    case 'in':
      return number * 72;
    case 'cm':
      return number * (72 / 2.54);
    case 'mm':
      return number * (72 / 25.4);
    case 'q':
      return number * (72 / 101.6);
    case 'em':
    case 'rem':
      return number * fontSize;
    case 'ex':
    case 'ch':
      return number * fontSize * 0.5;
    case '%':
      if (percentBase == null) return null;
      return percentBase * number / 100;
    default:
      // Unitless values are invalid CSS lengths, but zero and pixel-like
      // numbers in broken stylesheets are common enough to accept.
      return number * kCssPxToPt;
  }
}

/// Resolves a CSS `font-size` to points.
double? cssFontSizeToPt(
  String raw, {
  required double parentPt,
  required double rootPt,
}) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return null;
  switch (value) {
    case 'xx-small':
      return parentPt * 0.6;
    case 'x-small':
      return parentPt * 0.75;
    case 'small':
      return parentPt * 0.83;
    case 'medium':
      return parentPt;
    case 'large':
      return parentPt * 1.2;
    case 'x-large':
      return parentPt * 1.5;
    case 'xx-large':
      return parentPt * 2;
    case 'smaller':
      return parentPt * 0.75;
    case 'larger':
      return parentPt * 1.25;
    case 'inherit':
      return parentPt;
  }
  if (_cssWideKeywords.contains(value)) return null;
  final match = RegExp(
    r'^([+-]?(?:\d+\.?\d*|\.\d+))\s*(px|pt|pc|in|cm|mm|q|em|rem|ex|ch|%)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return null;
  switch (match.group(2) ?? '') {
    case 'px':
      return number * kCssPxToPt;
    case 'pt':
      return number;
    case 'pc':
      return number * 12;
    case 'in':
      return number * 72;
    case 'cm':
      return number * (72 / 2.54);
    case 'mm':
      return number * (72 / 25.4);
    case 'q':
      return number * (72 / 101.6);
    case 'em':
    case '%':
      return parentPt * number / (match.group(2) == '%' ? 100 : 1);
    case 'rem':
      return rootPt * number;
    case 'ex':
    case 'ch':
      return parentPt * number * 0.5;
    default:
      return number * kCssPxToPt;
  }
}

/// Resolves a CSS `line-height` to a multiplier of the font size, or null
/// when it should keep the inherited value.
double? cssLineHeightFactor(String raw, {required double fontSize}) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'normal' || value == 'inherit') return null;
  if (_cssWideKeywords.contains(value)) return null;
  final plain = double.tryParse(value);
  if (plain != null) return plain <= 0 ? null : plain;
  if (value.endsWith('%')) {
    final percent = double.tryParse(value.substring(0, value.length - 1));
    return percent == null ? null : percent / 100;
  }
  final length = cssLengthToPt(value, fontSize: fontSize);
  if (length == null || fontSize <= 0) return null;
  return length / fontSize;
}

/// Whether a CSS `font-weight` value renders bold.
bool isCssBoldWeight(String raw) {
  final value = raw.trim().toLowerCase();
  if (value == 'bold' || value == 'bolder') return true;
  final numeric = int.tryParse(value);
  if (numeric != null) return numeric >= 600;
  return false;
}

/// Parses a CSS `display` value into the subset used by the renderer.
String? cssDisplay(String raw) {
  final value = raw.trim().toLowerCase();
  switch (value) {
    case 'none':
      return 'none';
    case 'block':
    case 'flex':
    case 'grid':
    case 'table':
      return 'block';
    case 'list-item':
      return 'list-item';
    case 'inline':
    case 'inline-block':
    case 'inline-table':
    case 'inline-flex':
    case 'inline-grid':
    case 'contents':
      return 'inline';
    default:
      return null;
  }
}

/// Maps a CSS `text-align` value to a pdf [pw.TextAlign].
pw.TextAlign? cssTextAlign(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'left':
      return pw.TextAlign.left;
    case 'right':
      return pw.TextAlign.right;
    case 'center':
      return pw.TextAlign.center;
    case 'justify':
      return pw.TextAlign.justify;
    case 'start':
      return pw.TextAlign.start;
    case 'end':
      return pw.TextAlign.end;
    default:
      return null;
  }
}

/// Parses a CSS color: `#rgb`/`#rrggbb`/`#rgba`/`#rrggbbaa`, `rgb()`/`rgba()`
/// or a named color. `transparent` and unsupported values return null.
PdfColor? cssColor(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'transparent' || value == 'currentcolor') {
    return null;
  }
  if (_cssWideKeywords.contains(value)) return null;

  if (value.startsWith('#')) {
    value = value.substring(1).replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (value.length == 3) {
      value = value
          .split('')
          .map((part) => '$part$part')
          .join();
    }
    if (value.length != 6 && value.length != 8) return null;
    try {
      return PdfColor.fromHex(value);
    } catch (_) {
      return null;
    }
  }

  final functional = RegExp(
    r'^rgba?\(\s*([^)]*)\)$',
  ).firstMatch(value);
  if (functional != null) {
    final parts = functional
        .group(1)!
        .replaceAll('/', ' ')
        .split(RegExp(r'[\s,]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3) return null;
    double? channel(String part, {required bool alpha}) {
      if (part.endsWith('%')) {
        final percent = double.tryParse(part.substring(0, part.length - 1));
        if (percent == null) return null;
        return (alpha ? percent / 100 : percent / 100).clamp(0.0, 1.0);
      }
      final number = double.tryParse(part);
      if (number == null) return null;
      return (alpha ? number : number / 255).clamp(0.0, 1.0);
    }

    final red = channel(parts[0], alpha: false);
    final green = channel(parts[1], alpha: false);
    final blue = channel(parts[2], alpha: false);
    if (red == null || green == null || blue == null) return null;
    var alpha = 1.0;
    if (parts.length >= 4) {
      alpha = channel(parts[3], alpha: true) ?? 1.0;
    }
    return PdfColor(red, green, blue, alpha);
  }

  final named = kCssNamedColors[value];
  if (named == null) return null;
  return PdfColor.fromInt(named);
}

/// The subset of CSS named colors supported without a lookup table dependency.
const kCssNamedColors = {
  'black': 0xFF000000,
  'silver': 0xFFC0C0C0,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'white': 0xFFFFFFFF,
  'maroon': 0xFF800000,
  'red': 0xFFFF0000,
  'purple': 0xFF800080,
  'fuchsia': 0xFFFF00FF,
  'magenta': 0xFFFF00FF,
  'green': 0xFF008000,
  'lime': 0xFF00FF00,
  'olive': 0xFF808000,
  'yellow': 0xFFFFFF00,
  'navy': 0xFF000080,
  'blue': 0xFF0000FF,
  'teal': 0xFF008080,
  'aqua': 0xFF00FFFF,
  'cyan': 0xFF00FFFF,
  'orange': 0xFFFFA500,
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'blanchedalmond': 0xFFFFEBCD,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgrey': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'greenyellow': 0xFFADFF2F,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgrey': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'oldlace': 0xFFFDF5E6,
  'olivedrab': 0xFF6B8E23,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'rebeccapurple': 0xFF663399,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'whitesmoke': 0xFFF5F5F5,
  'yellowgreen': 0xFF9ACD32,
};
