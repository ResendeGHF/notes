// SPDX-FileCopyrightText: 2025 Gustavo Henrique Freitas de Resende <https://github.com/ResendeGHF>
// SPDX-License-Identifier: GPL-3.0-or-later

class PdfOutlineItem {
  final String title;
  int pageIndex;
  final List<PdfOutlineItem>? children;

  PdfOutlineItem({
    required this.title,
    required this.pageIndex,
    this.children,
  });

  Map<String, dynamic> toJson() {
    return {
      't': title,
      'p': pageIndex,
      if (children != null) 'c': children!.map((c) => c.toJson()).toList(),
    };
  }

  factory PdfOutlineItem.fromJson(Map<String, dynamic> json) {
    return PdfOutlineItem(
      title: json['t'] as String,
      pageIndex: json['p'] as int,
      children: json['c'] != null
          ? (json['c'] as List)
              .map((c) => PdfOutlineItem.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}

