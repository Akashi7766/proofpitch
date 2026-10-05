import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../models.dart';
import '../tailor.dart';
import '../theme.dart';

/// Edit the resume itself: every section as written, plus each project's bullet points.
/// Saving rebuilds a clean PDF from it, and that becomes the resume emails attach.
class ResumeEditorScreen extends ConsumerStatefulWidget {
  const ResumeEditorScreen({super.key});
  @override
  ConsumerState<ResumeEditorScreen> createState() => _ResumeEditorScreenState();
}

class _Draft {
  _Draft(String title, this.kind, List<String> lines)
      : title = TextEditingController(text: title),
        body = TextEditingController(text: lines.join('\n'));
  final TextEditingController title, body;
  final String kind;
  ResumeSection get section => ResumeSection(
        title.text.trim(),
        kind,
        [for (final l in body.text.split('\n')) if (l.trim().isNotEmpty) l.trimRight()],
      );
}

class _ResumeEditorScreenState extends ConsumerState<ResumeEditorScreen> {
  late final StudentProfile _start = ref.read(profileProvider);
  late final List<_Draft> _sections = [
    // Projects are edited below (with their links and tags); the raw "Projects" block isn't printed.
    for (final x in _start.resumeSections.isNotEmpty ? _start.resumeSections : _fallback(_start))
      if (x.kind != 'projects') _Draft(x.title, x.kind, x.lines),
  ];
  late final Map<String, TextEditingController> _bullets = {
    for (final p in _start.projects) p.id: TextEditingController(text: (p.bullets.isEmpty && p.oneLiner.isNotEmpty ? [p.oneLiner] : p.bullets).join('\n')),
  };
  bool _saving = false;

  /// Profiles imported before sections were kept: start from the fields we have.
  static List<ResumeSection> _fallback(StudentProfile s) => [
        const ResumeSection('Summary', 'summary', []),
        if (s.skills.isNotEmpty) ResumeSection('Skills', 'skills', ['Technical Skills: ${s.skills.join(', ')}']),
        if (s.experience.isNotEmpty) ResumeSection('Experience', 'experience', s.experience),
        ResumeSection('Education', 'education', [
          if (s.college.isNotEmpty) s.college,
          [s.degree, if (s.graduationYear != null) '${s.graduationYear}', if (s.cgpa != null) 'CGPA ${s.cgpa}'].where((e) => e.isNotEmpty).join('  |  '),
        ]),
        if (s.extras.isNotEmpty) ResumeSection('Achievements', 'other', [for (final e in s.extras) '• $e']),
      ];

  Future<void> _save() async {
    setState(() => _saving = true);
    final cur = ref.read(profileProvider);
    final next = cur.copyWith(
      resumeSections: [for (final d in _sections) if (d.section.title.isNotEmpty || d.section.lines.isNotEmpty) d.section],
      projects: [
        for (final p in cur.projects)
          Project(
            id: p.id,
            name: p.name,
            url: p.url,
            kind: p.kind,
            tags: p.tags,
            oneLiner: p.oneLiner,
            bullets: [for (final l in (_bullets[p.id]?.text ?? '').split('\n')) if (l.trim().isNotEmpty) l.trim()],
          ),
      ],
    );
    final messenger = ScaffoldMessenger.of(context);
    String? path;
    try {
      path = await writeTailoredResume(next);
    } catch (_) {}
    ref.read(profileProvider.notifier).save(path == null ? next : next.copyWith(resumePath: path));
    if (!mounted) return;
    setState(() => _saving = false);
    messenger.showSnackBar(SnackBar(
      content: Text(path == null ? 'Saved. (No PDF on this device.)' : 'Saved ✨ Emails now attach your edited resume.'),
      action: path == null
          ? null
          : SnackBarAction(
              label: 'SHARE PDF',
              textColor: C.white,
              onPressed: () => const MethodChannel('proofpitch/share').invokeMethod('sharePdf', {'path': path}).catchError((Object _) => null),
            ),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit resume')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
          children: [
            const Text(
              'Fix anything the import got wrong, add what\'s missing. One line per line; start a line with "•" for a bullet. '
              'Name, contact and links come from the ME tab.',
              style: TextStyle(color: muted),
            ),
            if (_start.projects.isNotEmpty) ...[
              const SectionTitle('Project bullet points'),
              for (final p in _start.projects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _bullets[p.id],
                    maxLines: null,
                    minLines: 2,
                    decoration: InputDecoration(labelText: p.name, hintText: 'What you built, with numbers if you have them'),
                  ),
                ),
            ],
            const SectionTitle('Sections'),
            for (final (i, d) in _sections.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Brutal(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: TextField(controller: d.title, decoration: const InputDecoration(labelText: 'Heading', isDense: true))),
                      IconButton(
                        tooltip: 'Remove section',
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => setState(() => _sections.removeAt(i)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextField(controller: d.body, maxLines: null, minLines: 3, decoration: const InputDecoration(labelText: 'Lines')),
                  ]),
                ),
              ),
            BrutalButton('Add a section', icon: Icons.add_rounded, color: C.white, onTap: () => setState(() => _sections.add(_Draft('', 'other', const [])))),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: BrutalButton(_saving ? 'Saving…' : 'Save & make PDF', big: true, onTap: _saving ? null : _save),
          ),
        ),
      );
}
