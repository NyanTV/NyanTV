import 'package:flutter/material.dart';

class NyantvThemeColors {
  final Color primary;
  final Color? secondary;
  const NyantvThemeColors(this.primary, {this.secondary});
}

ColorScheme buildColorScheme(
    NyantvThemeColors themeColors,
    Brightness brightness, {
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) {
  final base = ColorScheme.fromSeed(
    seedColor: themeColors.primary,
    brightness: brightness,
    dynamicSchemeVariant: variant,
  );
  if (themeColors.secondary == null) return base;

  final contrast = ThemeData.estimateBrightnessForColor(themeColors.secondary!) == Brightness.light
      ? Colors.black
      : Colors.white;

  if (brightness == Brightness.dark) {
    return base.copyWith(
      primary: themeColors.primary,
      onPrimary: Colors.white,
      primaryContainer: themeColors.primary.withOpacity(0.6),
      onPrimaryContainer: themeColors.primary,
      secondary: themeColors.secondary,
      onSecondary: const Color.fromARGB(255, 0, 0, 0),
      secondaryContainer: themeColors.secondary!.withOpacity(0.8),
      onSecondaryContainer: themeColors.secondary,
    );
  }

  return base.copyWith(
    secondary: themeColors.secondary,
    secondaryContainer: themeColors.secondary!.withOpacity(0.2),
    onSecondary: contrast,
  );
}

Map<String, NyantvThemeColors> colorMap = {
  "Green":       const NyantvThemeColors(Colors.green),
  "Red":         const NyantvThemeColors(Colors.red),
  "Pink":        const NyantvThemeColors(Colors.pink),
  "Purple":      const NyantvThemeColors(Colors.purple),
  "DeepPurple":  const NyantvThemeColors(Colors.deepPurple),
  "Indigo":      const NyantvThemeColors(Colors.indigo),
  "Blue":        const NyantvThemeColors(Colors.blue),
  "LightBlue":   const NyantvThemeColors(Colors.lightBlue),
  "Cyan":        const NyantvThemeColors(Colors.cyan),
  "Teal":        const NyantvThemeColors(Colors.teal),
  "LightGreen":  const NyantvThemeColors(Colors.lightGreen),
  "Lime":        const NyantvThemeColors(Colors.lime),
  "Yellow":      const NyantvThemeColors(Colors.yellow),
  "Amber":       const NyantvThemeColors(Colors.amber),
  "Orange":      const NyantvThemeColors(Colors.orange),
  "DeepOrange":  const NyantvThemeColors(Colors.deepOrange),
  "Brown":       const NyantvThemeColors(Colors.brown),
  "Galatasaray": const NyantvThemeColors(Color(0xFFD4021D), secondary: Color(0xFFF5C518)),
};

List<NyantvThemeColors> colorList = colorMap.values.toList();
List<String> colorKeys = colorMap.keys.toList();

Map<String, BoxFit> resizeModes = {
  for (var e in BoxFit.values)
    if (e != BoxFit.none)
      capitalize(e.name) +
          (e == BoxFit.contain ? ' (default)' : '') +
          (e == BoxFit.fill ? ' (Stretch) ' : ''): e,
};
List<String> resizeModeList = resizeModes.keys.toList()..sort();

Map<String, DynamicSchemeVariant> dynamicSchemeVariantMap = {
  for (var variant in DynamicSchemeVariant.values)
    capitalize(variant.name): variant,
};
List<DynamicSchemeVariant> dynamicSchemeVariantList =
    dynamicSchemeVariantMap.values.toList();
List<String> dynamicSchemeVariantKeys = dynamicSchemeVariantMap.keys.toList();

String capitalize(String word) {
  String firstLetter = (word[0]).toUpperCase();
  String truncatedWord = firstLetter + word.substring(1, word.length);
  return truncatedWord;
}

const maxMobileWidth = 600;

final Map<String, Color> colorOptions = {
  'Default': Colors.transparent,
  'White': Colors.white,
  'Black': Colors.black,
  'Red': Colors.red,
  'Green': Colors.green,
  'Blue': Colors.blue,
  'Yellow': Colors.yellow,
  'Cyan': Colors.cyan,
};

final Map<String, Color> fontColorOptions = {
  'Default': Colors.white70,
  'White': Colors.white,
  'Black': Colors.black,
  'Red': Colors.red,
  'Green': Colors.green,
  'Blue': Colors.blue,
  'Yellow': Colors.yellow,
  'Cyan': Colors.cyan,
};

final cursedSpeed = [
  0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75,
  2.00, 3.00, 5.00, 10.00,
  ...[25.0, 50.0, 75.0, 100.0],
];

final List<String> extensions = [
  'srt', 'vtt', 'ssa', 'ass', 'sub', 'idx', 'txt',
  'dfxp', 'ttml', 'lrc', 'stl', 'sbv', 'xml', 'cap',
  'mks', 'sup',
];