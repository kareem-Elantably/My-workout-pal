import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/plan_models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/library_repository.dart';
import '../auth/validators.dart';

final _arabic = RegExp(r'[؀-ۿ]');

/// A food that isn't in the library yet: the coach types its values per
/// 100 g (from the pack or a nutrition site) and, optionally, a unit like
/// "loaf". [name] pre-fills what they searched for. Returns the new food.
Future<Food?> addNewFood(BuildContext context, {String? name, FoodDraft? draft, String? barcode}) {
  final typed = name?.trim() ?? '';
  return showDialog<Food>(
    context: context,
    builder: (_) => FoodDialog(
      draft: draft,
      barcode: barcode,
      nameEn: _arabic.hasMatch(typed) ? null : typed,
      nameAr: _arabic.hasMatch(typed) ? typed : null,
    ),
  );
}

/// Scans a pack's barcode: returns the food if it's already in the library,
/// otherwise opens the new-food form filled from Open Food Facts.
Future<Food?> scanFood(BuildContext context, WidgetRef ref) async {
  final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()));
  if (code == null || !context.mounted) return null;
  final repo = ref.read(libraryRepositoryProvider);
  try {
    final existing = await repo.foodByBarcode(code);
    if (existing != null) {
      if (context.mounted) showMessage(context, context.l10n.foodAlreadyInLibrary(existing.name(context)));
      return existing;
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
  FoodDraft? draft;
  try {
    draft = await repo.lookupOpenFoodFacts(code);
  } catch (_) {}
  if (!context.mounted) return null;
  if (draft == null) showMessage(context, context.l10n.barcodeNotFound);
  return addNewFood(context, draft: draft, barcode: code);
}

class BarcodeScannerScreen extends StatelessWidget {
  const BarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var done = false;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.scanBarcode)),
      body: MobileScanner(
        onDetect: (capture) {
          final code = capture.barcodes.firstOrNull?.rawValue;
          if (code != null && !done) {
            done = true;
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}

class FoodDialog extends ConsumerStatefulWidget {
  const FoodDialog({super.key, this.draft, this.barcode, this.nameEn, this.nameAr});

  final FoodDraft? draft;
  final String? barcode;
  final String? nameEn;
  final String? nameAr;

  @override
  ConsumerState<FoodDialog> createState() => _FoodDialogState();
}

class _FoodDialogState extends ConsumerState<FoodDialog> {
  final _form = GlobalKey<FormState>();
  late final _nameEn = TextEditingController(text: widget.draft?.name ?? widget.nameEn);
  late final _nameAr = TextEditingController(text: widget.nameAr);
  late final _kcal = TextEditingController(text: formatNum(widget.draft?.kcal));
  late final _protein = TextEditingController(text: formatNum(widget.draft?.protein));
  late final _carbs = TextEditingController(text: formatNum(widget.draft?.carbs));
  late final _fat = TextEditingController(text: formatNum(widget.draft?.fat));
  final _unitName = TextEditingController();
  final _unitGrams = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_nameEn, _nameAr, _kcal, _protein, _carbs, _fat, _unitName, _unitGrams]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final unitGrams = parseNumber(_unitGrams.text);
      // Arabic-only names are fine: the English name falls back to it.
      final nameEn = _nameEn.text.trim().isEmpty ? _nameAr.text.trim() : _nameEn.text;
      final food = await ref.read(libraryRepositoryProvider).createFood(
            nameEn: nameEn,
            nameAr: _nameAr.text,
            kcal: parseNumber(_kcal.text)!,
            protein: parseNumber(_protein.text) ?? 0,
            carbs: parseNumber(_carbs.text) ?? 0,
            fat: parseNumber(_fat.text) ?? 0,
            barcode: widget.barcode,
            units: _unitName.text.trim().isEmpty || unitGrams == null ? const [] : [(_unitName.text.trim(), _unitName.text.trim(), unitGrams)],
          );
      if (mounted) Navigator.pop(context, food);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget field(TextEditingController c, String label, {bool required = false, bool last = false}) => TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: last ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: last ? (_) => _save() : null,
          validator: (v) => validateNumber(context, v, required: required, min: 0, max: 900),
        );
    return AlertDialog(
      title: Text(widget.barcode == null ? l10n.newFood : l10n.foodFromBarcode),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.newFoodHint, style: Theme.of(context).textTheme.bodySmall),
            TextFormField(
              controller: _nameAr,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.nameArabic),
              validator: (v) => (v ?? '').trim().isEmpty && _nameEn.text.trim().isEmpty ? l10n.foodNameRequired : null,
            ),
            TextFormField(
              controller: _nameEn,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: l10n.nameEnglishOptional),
            ),
            const SizedBox(height: 8),
            Text(l10n.per100g, style: Theme.of(context).textTheme.labelLarge),
            field(_kcal, l10n.kcal, required: true),
            Row(children: [
              Expanded(child: field(_protein, l10n.protein)),
              const SizedBox(width: 8),
              Expanded(child: field(_carbs, l10n.carbs)),
              const SizedBox(width: 8),
              Expanded(child: field(_fat, l10n.fat)),
            ]),
            const SizedBox(height: 8),
            Text(l10n.unitOptional, style: Theme.of(context).textTheme.labelLarge),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _unitName,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.unitName, hintText: l10n.unitNameHint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: field(_unitGrams, l10n.gramsPerUnit, last: true)),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
