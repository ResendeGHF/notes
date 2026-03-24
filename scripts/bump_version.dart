#!/usr/bin/env dart
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:args/args.dart';
import 'package:saber/data/saber_version.dart';
import 'package:saber/data/version.dart' as old_version_file;

final oldVersion = SaberVersion.fromName(old_version_file.buildName);
late final SaberVersion newVersion;
late final bool failOnChanges;

enum ErrorCodes {
  noError(0),
  noVersionSpecified(1),
  changesNeeded(10);

  const ErrorCodes(this.code);

  final int code;
}

Future<void> main(List<String> args) async {
  parseArgs(args);
  await updateAllFiles();
}

void parseArgs(List<String> args) {
  final parser = ArgParser()
    ..addFlag('major', abbr: 'M', negatable: false, help: 'Bump major version')
    ..addFlag('minor', abbr: 'm', negatable: false, help: 'Bump minor version')
    ..addFlag('patch', abbr: 'p', negatable: false, help: 'Bump patch version')
    ..addOption(
      'custom',
      abbr: 'c',
      help: 'Use a custom buildName (e.g. 0.22.11) or buildNumber (e.g. 22110)',
    )
    ..addFlag(
      'fail-on-changes',
      abbr: 'f',
      negatable: false,
      help: 'Fail if any changes need to be made',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  final results = parser.parse(args);

  failOnChanges = results.flag('fail-on-changes');

  if (results.flag('help')) {
    print(parser.usage);
    exit(ErrorCodes.noError.code);
  } else if (results.flag('major')) {
    newVersion = oldVersion.bumpMajor();
  } else if (results.flag('minor')) {
    newVersion = oldVersion.bumpMinor();
  } else if (results.flag('patch')) {
    newVersion = oldVersion.bumpPatch();
  } else if (results.option('custom') != null) {
    final custom = results['custom']!;
    late final buildNumber = int.tryParse(custom);
    if (custom.contains('.')) {
      newVersion = SaberVersion.fromName(custom);
    } else if (buildNumber != null) {
      newVersion = SaberVersion.fromNumber(buildNumber);
    } else {
      print('Invalid custom version: $custom');
      print(parser.usage);
      exit(ErrorCodes.noVersionSpecified.code);
    }
  } else {
    print('No version specified');
    print(parser.usage);
    exit(ErrorCodes.noVersionSpecified.code);
  }

  print(
    'Bumping version from ${oldVersion.buildName} to ${newVersion.buildName}',
  );
}

Future<void> updateAllFiles() async {
  // update version file
  await File('lib/data/version.dart').replace({
    // e.g. const int buildNumber = 5050;
    RegExp(r'buildNumber = .+;'): 'buildNumber = ${newVersion.buildNumber};',
    // e.g. const String buildName = '0.5.5';
    RegExp(r'buildName = .+;'): "buildName = '${newVersion.buildName}';",
    // e.g. const int buildYear = 2023;
    RegExp(r'buildYear = .+;'): 'buildYear = ${DateTime.now().year};',
  });

  // update pubspec
  await File('pubspec.yaml').replace({
    // e.g. version: 5.5.0+5050
    RegExp(r'version: .+'):
        'version: ${newVersion.buildName}+${newVersion.buildNumber}',
  });

  print('\nVersion bumped successfully!');
}

extension on File {
  Future<void> replace(Map<RegExp, String> replacements) async {
    var matches = 0;
    final lines = await readAsLines();
    for (var i = 0; i < lines.length; i++) {
      for (final pattern in replacements.keys) {
        if (pattern.hasMatch(lines[i])) {
          matches++;
          final oldLine = lines[i];
          lines[i] = lines[i].replaceFirst(pattern, replacements[pattern]!);
          if (failOnChanges && lines[i] != oldLine) {
            print('Failed: Changes needed in $path');
            exit(ErrorCodes.changesNeeded.code);
          }
        }
      }
    }
    if (lines.last.isNotEmpty) lines.add('');
    await writeAsString(lines.join('\n'));

    if (matches >= replacements.length) {
      print('Updated $path with all $matches replacements');
    } else {
      print(
        'Updated $path with $matches out of ${replacements.length} '
        'replacements (${replacements.length - matches} missed)',
      );
    }
  }
}
