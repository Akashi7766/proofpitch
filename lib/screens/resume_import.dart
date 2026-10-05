import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data.dart';
import '../insights.dart';
import '../models.dart';
import '../theme.dart';

/// Keeps an app-private copy of the PDF (original file name, so it looks right in Gmail) for email attachments.
/// Returns '' where there's no file system (web).
Future<String> storeResume(List<int> bytes, String name) async {
  if (kIsWeb) return '';
  try {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/resume');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^\w.\- ]'), '_');
    final f = File('${dir.path}/${safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf'}');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  } catch (_) {
    return '';
  }
}

/// Just swap the attached resume, without re-reading it into the profile.
Future<void> pickResumeFile(WidgetRef ref) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
  if (file == null) return;
  final path = await storeResume(await file.readAsBytes(), file.name);
  if (path.isNotEmpty) ref.read(profileProvider.notifier).save(ref.read(profileProvider).copyWith(resumePath: path));
}

/// Pick a PDF → extract text on-device → let the user review → merge into the profile.
Future<void> importResume(BuildContext context, WidgetRef ref) async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
  if (file == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  String text;
  try {
    final bytes = await file.readAsBytes();
    text = pdfToText(bytes);
    // Same file goes out with every email pitch.
    final path = await storeResume(bytes, file.name);
    if (path.isNotEmpty) ref.read(profileProvider.notifier).save(ref.read(profileProvider).copyWith(resumePath: path));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't read that PDF. Is it password-protected?")));
    return;
  }
  if (text.trim().length < 80) {
    messenger.showSnackBar(const SnackBar(content: Text('No text inside — looks like a scanned image. Export it as a text PDF.')));
    return;
  }
  if (!context.mounted) return;
  final ok = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => ResumeReviewScreen(data: parseResume(text))),
  );
  if (ok == true) messenger.showSnackBar(const SnackBar(content: Text('Profile filled from your resume ✨ Jobs are now ranked for you.')));
}

class ResumeReviewScreen extends ConsumerStatefulWidget {
  const ResumeReviewScreen({super.key, required this.data});
  final ResumeData data;
  @override
  ConsumerState<ResumeReviewScreen> createState() => _ResumeReviewScreenState();
}

class _ResumeReviewScreenState extends ConsumerState<ResumeReviewScreen> {
  late final d = widget.data;
  late final _c = {
    'Name': TextEditingController(text: d.name),
    'Email': TextEditingController(text: d.email),
    'Phone': TextEditingController(text: d.phone),
    'College': TextEditingController(text: d.college),
    'Degree': TextEditingController(text: d.degree),
    'CGPA': TextEditingController(text: d.cgpa?.toString() ?? ''),
    'Grad year': TextEditingController(text: d.graduationYear?.toString() ?? ''),
    'GitHub': TextEditingController(text: d.github),
    'LinkedIn': TextEditingController(text: d.linkedin),
    'Portfolio': TextEditingController(text: d.portfolio),
    'City': TextEditingController(text: d.city),
    'Country': TextEditingController(text: d.country),
  };
  late final Set<String> _skills = {...d.skills};
  late final Set<String> _projects = {for (final p in d.projects) p.id};
  late final _links = {for (final p in d.projects) p.id: TextEditingController(text: p.url)};

  int get _found =>
      _c.values.where((c) => c.text.isNotEmpty).length + (_skills.isNotEmpty ? 1 : 0) + (_projects.isNotEmpty ? 1 : 0);

  void _save() {
    String v(String k) => _c[k]!.text.trim();
    final edited = ResumeData(
      name: v('Name'),
      email: v('Email'),
      phone: v('Phone'),
      college: v('College'),
      degree: v('Degree'),
      city: v('City'),
      country: v('Country'),
      cgpa: double.tryParse(v('CGPA')),
      graduationYear: int.tryParse(v('Grad year')),
      github: v('GitHub'),
      linkedin: v('LinkedIn'),
      portfolio: v('Portfolio'),
      skills: _skills.toList(),
      experience: d.experience,
      extras: d.extras,
      sections: d.sections,
      projects: [
        for (final p in d.projects)
          if (_projects.contains(p.id))
            Project(
              id: p.id,
              name: p.name,
              url: _links[p.id]!.text.trim(),
              kind: kindForUrl(_links[p.id]!.text),
              tags: p.tags,
              oneLiner: p.oneLiner,
              bullets: p.bullets,
            ),
      ],
    );
    final n = ref.read(profileProvider.notifier);
    n.save(edited.mergeInto(ref.read(profileProvider)));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            Row(children: [
              Expanded(child: Text('Here\'s what\nwe found', style: display(30))),
              Stamp(child: StampLabel('$_found of ${_c.length + 2}', color: C.blue, size: 18)),
            ]),
            const SizedBox(height: 8),
            Text('We filled $_found of ${_c.length + 2} things from your resume. Fix anything that looks off — nothing leaves your phone.',
                style: const TextStyle(color: muted)),
            const SizedBox(height: 16),
            if (d.warnings.isNotEmpty) ...[
              Brutal(
                color: C.yellow,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fix these in your resume', style: display(15)),
                  const SizedBox(height: 6),
                  for (final w in d.warnings) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $w')),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            for (final e in _c.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: e.value,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: e.key,
                    isDense: true,
                    helperText: e.key == 'City' && e.value.text.isEmpty ? 'Add your city — jobs near you are shown first' : null,
                  suffixIcon: e.value.text.isEmpty ? const Tooltip(message: 'Not found', child: Icon(Icons.help_outline, color: muted)) : null,
                  ),
                ),
              ),
            SectionTitle('Skills · ${_skills.length}'),
            if (_skills.isEmpty) const Text('None detected. Add them later on the ME tab.', style: TextStyle(color: muted)),
            Wrap(spacing: 6, runSpacing: 8, children: [
              for (final s in d.skills)
                BrutalChip(_skills.contains(s) ? '$s ✓' : s, selected: _skills.contains(s), color: C.lime,
                    onTap: () => setState(() => _skills.contains(s) ? _skills.remove(s) : _skills.add(s))),
            ]),
            SectionTitle('Projects · ${_projects.length}'),
            if (d.projects.isEmpty)
              const Text('No projects section found. Add your best work on the ME tab — it powers your pitches.',
                  style: TextStyle(color: muted)),
            for (final p in d.projects)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Brutal(
                  color: _projects.contains(p.id) ? C.white : const Color(0xFFEDE6D8),
                  shadow: _projects.contains(p.id) ? 4 : 0,
                  onTap: () => setState(() => _projects.contains(p.id) ? _projects.remove(p.id) : _projects.add(p.id)),
                  child: Row(children: [
                    Icon(_projects.contains(p.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: display(16)),
                        if (p.oneLiner.isNotEmpty) Text(p.oneLiner, style: const TextStyle(color: muted)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _links[p.id],
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Link to this project (repo, store, demo)', isDense: true),
                        ),
                        if (p.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(spacing: 4, runSpacing: 4, children: [for (final t in p.tags) Pill(t)]),
                        ],
                      ]),
                    ),
                    Pill(p.kind.label, color: C.pink),
                  ]),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: BrutalButton('Looks right — save', big: true, onTap: _save),
          ),
        ),
      );
}

