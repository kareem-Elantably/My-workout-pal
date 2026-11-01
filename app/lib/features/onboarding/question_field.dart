import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/models.dart';
import '../../core/ui.dart';
import '../auth/validators.dart';

/// One sign-up question, rendered for its answer type. Values match what is
/// stored in `answers.value`: String, num, bool, `YYYY-MM-DD`, String,
/// `List<String>`, or a list of `HH:mm`. Empty answers are null.
class QuestionField extends StatelessWidget {
  const QuestionField({
    super.key,
    required this.question,
    required this.value,
    required this.onChanged,
    this.timeSlots,
  });

  final Question question;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  /// For time lists: how many times to ask for (e.g. the meals-per-day answer).
  final int? timeSlots;

  @override
  Widget build(BuildContext context) {
    final label = localized(context, question.textEn, question.textAr);
    final hint = question.hintEn == null ? null : localized(context, question.hintEn!, question.hintAr ?? question.hintEn!);
    return switch (question.type) {
      AnswerType.text => _TextQuestion(
          key: ValueKey(question.id),
          label: label,
          hint: hint,
          initial: value as String?,
          validator: (text) => question.isRequired && (text == null || text.trim().isEmpty) ? context.l10n.required : null,
          onChanged: (text) => onChanged(text.trim().isEmpty ? null : text.trim()),
        ),
      AnswerType.number => _TextQuestion(
          key: ValueKey(question.id),
          label: label,
          hint: hint,
          initial: value == null ? null : _formatNumber(value as num),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: (text) =>
              validateNumber(context, text, required: question.isRequired, min: question.min, max: question.max),
          onChanged: (text) => onChanged(parseNumber(text)),
        ),
      AnswerType.boolean => _ChoiceQuestion(
          label: label,
          hint: hint,
          isRequired: question.isRequired,
          options: [(true, context.l10n.yes), (false, context.l10n.no)],
          selected: value == null ? const {} : {value as bool},
          multiple: false,
          onChanged: (selected) => onChanged(selected.firstOrNull),
        ),
      AnswerType.singleChoice => _ChoiceQuestion(
          label: label,
          hint: hint,
          isRequired: question.isRequired,
          options: [for (final o in question.options) (o.value, localized(context, o.labelEn, o.labelAr))],
          selected: value == null ? const {} : {value as String},
          multiple: false,
          onChanged: (selected) => onChanged(selected.firstOrNull),
        ),
      AnswerType.multiChoice => _ChoiceQuestion(
          label: label,
          hint: hint,
          isRequired: question.isRequired,
          options: [for (final o in question.options) (o.value, localized(context, o.labelEn, o.labelAr))],
          selected: {...(value as List? ?? const []).cast<String>()},
          multiple: true,
          onChanged: (selected) => onChanged(selected.isEmpty ? null : selected.toList()),
        ),
      AnswerType.date => _DateQuestion(
          label: label,
          hint: hint,
          isRequired: question.isRequired,
          value: value as String?,
          onChanged: onChanged,
        ),
      AnswerType.timeList => _TimeListQuestion(
          label: label,
          hint: hint,
          isRequired: question.isRequired,
          slots: timeSlots,
          value: (value as List? ?? const []).cast<String>(),
          onChanged: (times) => onChanged(times.isEmpty ? null : times),
        ),
    };
  }

  static String _formatNumber(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

class _TextQuestion extends StatelessWidget {
  const _TextQuestion({
    super.key,
    required this.label,
    required this.hint,
    required this.initial,
    required this.validator,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final String? hint;
  final String? initial;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextFormField(
        initialValue: initial,
        decoration: InputDecoration(labelText: label, helperText: hint, helperMaxLines: 2, alignLabelWithHint: true),
        keyboardType: keyboardType,
        maxLines: keyboardType == null ? null : 1,
        validator: validator,
        onChanged: onChanged,
      );
}

/// The question text above its input, for inputs that aren't text fields.
class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.hint, required this.error, required this.child});

  final String label;
  final String? hint;
  final String? error;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _ChoiceQuestion<T> extends StatelessWidget {
  const _ChoiceQuestion({
    required this.label,
    required this.hint,
    required this.isRequired,
    required this.options,
    required this.selected,
    required this.multiple,
    required this.onChanged,
  });

  final String label;
  final String? hint;
  final bool isRequired;
  final List<(T, String)> options;
  final Set<T> selected;
  final bool multiple;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) => FormField<Set<T>>(
        initialValue: selected,
        validator: (_) => isRequired && selected.isEmpty ? context.l10n.required : null,
        builder: (field) => _Labelled(
          label: label,
          hint: hint,
          error: field.errorText,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, text) in options)
                if (multiple)
                  FilterChip(
                    label: Text(text),
                    selected: selected.contains(value),
                    onSelected: (on) => _select(field, on ? {...selected, value} : ({...selected}..remove(value))),
                  )
                else
                  ChoiceChip(
                    label: Text(text),
                    selected: selected.contains(value),
                    onSelected: (on) => _select(field, on ? {value} : <T>{}),
                  ),
            ],
          ),
        ),
      );

  void _select(FormFieldState<Set<T>> field, Set<T> next) {
    field.didChange(next);
    onChanged(next);
  }
}

class _DateQuestion extends StatelessWidget {
  const _DateQuestion({
    required this.label,
    required this.hint,
    required this.isRequired,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? hint;
  final bool isRequired;
  final String? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final date = value == null ? null : DateTime.parse(value!);
    return FormField<String>(
      initialValue: value,
      validator: (_) => isRequired && value == null ? context.l10n.required : null,
      builder: (field) => _Labelled(
        label: label,
        hint: hint,
        error: field.errorText,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(date == null
              ? context.l10n.pickDate
              : DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date)),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            final iso = picked.toIso8601String().substring(0, 10);
            field.didChange(iso);
            onChanged(iso);
          },
        ),
      ),
    );
  }
}

class _TimeListQuestion extends StatelessWidget {
  const _TimeListQuestion({
    required this.label,
    required this.hint,
    required this.isRequired,
    required this.slots,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? hint;
  final bool isRequired;
  final int? slots;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    // A fixed number of pickers when we know how many meals there are,
    // otherwise the saved times plus an "add" button. '' = not picked yet,
    // so each time keeps its meal position.
    final count = slots ?? value.length;
    final times = [for (var i = 0; i < count; i++) i < value.length ? value[i] : ''];
    return FormField<List<String>>(
      initialValue: value,
      validator: (_) => isRequired && (times.isEmpty || times.contains('')) ? context.l10n.required : null,
      builder: (field) {
        Future<void> pick(int index) async {
          final current = index < times.length ? times[index] : '';
          final picked = await showTimePicker(
            context: context,
            initialTime: current.isEmpty
                ? TimeOfDay(hour: (8 + index * 4).clamp(0, 23), minute: 0)
                : TimeOfDay(hour: int.parse(current.substring(0, 2)), minute: int.parse(current.substring(3, 5))),
          );
          if (picked == null) return;
          final time = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
          final updated = [...times];
          index < updated.length ? updated[index] = time : updated.add(time);
          field.didChange(updated);
          onChanged(updated.every((t) => t.isEmpty) ? const [] : updated);
        }

        return _Labelled(
          label: label,
          hint: hint,
          error: field.errorText,
          child: Column(
            children: [
              for (var i = 0; i < times.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule),
                  title: Text(context.l10n.mealTime(i + 1)),
                  trailing: Text(times[i].isEmpty ? '--:--' : times[i], textDirection: TextDirection.ltr),
                  onTap: () => pick(i),
                ),
              if (slots == null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(context.l10n.addTime),
                    onPressed: () => pick(times.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
