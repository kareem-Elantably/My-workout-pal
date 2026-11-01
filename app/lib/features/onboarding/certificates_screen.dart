import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../../data/onboarding_repository.dart';

/// Coach sign-up: upload certificates for the admin to review, then submit.
class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  late Future<List<Certificate>> _certificates = _load();
  bool _submitting = false;

  SessionData get _session => (ref.read(sessionProvider).requireValue as SignedIn).data;

  Future<List<Certificate>> _load() => ref.read(onboardingRepositoryProvider).loadCertificates(_session.userId);

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddCertificateSheet(coachId: _session.userId),
    );
    if (added == true) setState(() => _certificates = _load());
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(onboardingRepositoryProvider).submitApplication(_session, AppRole.coach);
      await ref.read(sessionProvider.notifier).refresh(); // the router moves on to the waiting screen
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.certificatesTitle)),
      body: FutureBuilder(
        future: _certificates,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(error: snapshot.error!, onRetry: () => setState(() => _certificates = _load()));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final certificates = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(l10n.certificatesBody, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              for (final certificate in certificates)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text(certificate.title),
                    subtitle: certificate.issuer == null ? null : Text(certificate.issuer!),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: Text(l10n.addCertificate)),
              const SizedBox(height: 24),
              BusyButton(
                label: l10n.submit,
                busy: _submitting,
                onPressed: certificates.isEmpty ? null : _submit,
              ),
              if (certificates.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.needOneCertificate, textAlign: TextAlign.center),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddCertificateSheet extends ConsumerStatefulWidget {
  const _AddCertificateSheet({required this.coachId});

  final String coachId;

  @override
  ConsumerState<_AddCertificateSheet> createState() => _AddCertificateSheetState();
}

class _AddCertificateSheetState extends ConsumerState<_AddCertificateSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _issuer = TextEditingController();
  PlatformFile? _file;
  bool _uploading = false;

  @override
  void dispose() {
    _title.dispose();
    _issuer.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
    );
    if (file != null) setState(() => _file = file);
  }

  Future<void> _upload() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _uploading = true);
    try {
      await ref.read(onboardingRepositoryProvider).uploadCertificate(
            coachId: widget.coachId,
            title: _title.text.trim(),
            issuer: _issuer.text.trim(),
            fileName: _file!.name,
            bytes: await _file!.readAsBytes(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.addCertificate, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.certificateTitle),
              validator: (value) => (value == null || value.trim().isEmpty) ? l10n.required : null,
            ),
            const SizedBox(height: 16),
            TextFormField(controller: _issuer, decoration: InputDecoration(labelText: l10n.certificateIssuer)),
            const SizedBox(height: 16),
            FormField<PlatformFile>(
              validator: (_) => _file == null ? l10n.required : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _pick();
                      field.didChange(_file);
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(_file?.name ?? l10n.chooseFile, overflow: TextOverflow.ellipsis),
                  ),
                  if (field.errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(field.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            BusyButton(label: _uploading ? l10n.uploading : l10n.save, busy: _uploading, onPressed: _upload),
          ],
        ),
      ),
    );
  }
}
