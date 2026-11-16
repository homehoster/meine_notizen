import 'package:flutter/material.dart';

Widget blockedMarkdownImage(Uri _, String? _, String? alt) {
  final description = alt?.trim();
  return Text(
    description == null || description.isEmpty
        ? 'Bild blockiert'
        : 'Bild blockiert: $description',
  );
}
