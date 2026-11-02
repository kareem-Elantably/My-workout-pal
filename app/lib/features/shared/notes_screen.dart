import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../core/widgets.dart';
import '../../data/social_repository.dart';

final notesProvider = FutureProvider.autoDispose.family<List<Note>, String?>(
  (ref, aboutUserId) => ref.watch(socialRepositoryProvider).notes(aboutUserId: aboutUserId),
);

/// Private notes: only the author ever sees them. General notes, or about
/// one trainee (shown inside that trainee's page for coaches).
class NotesList extends ConsumerWidget {
  const NotesList({super.key, this.aboutUserId});

  final String? aboutUserId;

  Future<void> _edit(BuildContext context, WidgetRef ref, {Note? note}) async {
    final body = await promptText(context, title: context.l10n.note, initial: note?.body, multiline: true);
    if (body == null || body.trim().isEmpty) return;
    try {
      await ref.read(socialRepositoryProvider).saveNote(id: note?.id, body: body, aboutUserId: aboutUserId);
      ref.invalidate(notesProvider(aboutUserId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final notes = ref.watch(notesProvider(aboutUserId));
    final format = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'notes',
        icon: const Icon(Icons.add),
        label: Text(l10n.addNote),
        onPressed: () => _edit(context, ref),
      ),
      body: AsyncBody(
        value: notes,
        onRetry: () => ref.invalidate(notesProvider(aboutUserId)),
        builder: (list) => list.isEmpty
            ? EmptyList(icon: Icons.sticky_note_2_outlined, title: l10n.noNotes, body: l10n.notesPrivate)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Text(l10n.notesPrivate, style: Theme.of(context).textTheme.bodySmall),
                  for (final note in list)
                    Card(
                      child: ListTile(
                        title: Text(note.body),
                        subtitle: Text(format.format(note.updatedAt.toLocal())),
                        onTap: () => _edit(context, ref, note: note),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (!await confirm(context, l10n.deleteNoteConfirm, action: l10n.delete)) return;
                            await ref.read(socialRepositoryProvider).deleteNote(note.id);
                            ref.invalidate(notesProvider(aboutUserId));
                          },
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.myNotes)),
        body: const NotesList(),
      );
}
