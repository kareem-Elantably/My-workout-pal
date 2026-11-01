import 'package:flutter/widgets.dart';

import '../../core/ui.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(BuildContext context, String? value) {
  if (value == null || value.trim().isEmpty) return context.l10n.required;
  return _emailPattern.hasMatch(value.trim()) ? null : context.l10n.invalidEmail;
}

String? validatePassword(BuildContext context, String? value) {
  if (value == null || value.isEmpty) return context.l10n.required;
  return value.length < 8 ? context.l10n.passwordTooShort : null;
}

/// Parses Western or Arabic-Indic digits ("٧٢٫٥" -> 72.5).
num? parseNumber(String? value) {
  if (value == null) return null;
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  final normalized = value.trim().split('').map((char) {
    final index = arabicDigits.indexOf(char);
    if (index >= 0) return '$index';
    return char == '٫' || char == ',' ? '.' : char;
  }).join();
  return num.tryParse(normalized);
}

String? validateNumber(BuildContext context, String? value, {required bool required, num? min, num? max}) {
  if (value == null || value.trim().isEmpty) return required ? context.l10n.required : null;
  final number = parseNumber(value);
  if (number == null) return context.l10n.invalidNumber;
  if ((min != null && number < min) || (max != null && number > max)) {
    return context.l10n.numberBetween(_format(min), _format(max));
  }
  return null;
}

String _format(num? n) => n == null ? '' : (n == n.roundToDouble() ? n.toInt().toString() : n.toString());
