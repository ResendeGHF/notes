// SPDX-FileCopyrightText: 2022 Adil Hanney <https://github.com/adil192>
// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

class SaberVersion {
  final int major;
  final int minor;
  final int patch;
  final int revision;

  SaberVersion(this.major, this.minor, this.patch, [this.revision = 0])
    : assert(major >= 0 && major < 100),
      assert(minor >= 0 && minor < 100),
      assert(patch >= 0 && patch < 100),
      assert(revision >= 0 && revision < 10);

  factory SaberVersion.fromName(String name) {
    final parts = name.split('.');
    assert(parts.length == 3);
    return SaberVersion(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  factory SaberVersion.fromNumber(int number) {

    final revision = number % 10;

    final patch = (number ~/ 10) % 100;

    final minor = (number ~/ 1000) % 100;

    final major = (number ~/ 100000) % 100;

    return SaberVersion(major, minor, patch, revision);
  }

  String get buildName => '$major.$minor.$patch';
  String get buildNameWithCommas => '$major,$minor,$patch';
  int get buildNumber => revision + patch * 10 + minor * 1000 + major * 100000;
  int get buildNumberWithoutRevision => buildNumber - revision;

  SaberVersion bumpMajor() => SaberVersion(major + 1, 0, 0);
  SaberVersion bumpMinor() => SaberVersion(major, minor + 1, 0);
  SaberVersion bumpPatch() => SaberVersion(major, minor, patch + 1);

  SaberVersion copyWith({int? major, int? minor, int? patch, int? revision}) =>
      SaberVersion(
        major ?? this.major,
        minor ?? this.minor,
        patch ?? this.patch,
        revision ?? this.revision,
      );

  @override
  String toString() => buildName;

  @override
  bool operator ==(Object other) =>
      other is SaberVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
