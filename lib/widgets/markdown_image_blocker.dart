import 'package:flutter/material.dart';

import '../locales/app_localizations.dart';

Widget blockedMarkdownImage(Uri _, String? _, String? alt) {
  final description = alt?.trim();
  return Builder(
    builder: (context) => Text(
      description == null || description.isEmpty
          ? context.tr('Bild blockiert')
          : '${context.tr('Bild blockiert')}: $description',
    ),
  );
}
