import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data.dart';
import '../engines.dart' show canonSkill, splitSkills, defaultTemplateSubject, defaultTemplateBody;
import '../feed.dart';
import '../insights.dart';
import '../models.dart';
import '../theme.dart';
import 'resume_editor.dart';
import 'resume_import.dart';

/// Toggles fields of interest straight into the profile.
class InterestChips extends ConsumerWidget {
  const InterestChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picked = ref.watch(profileProvider.select((p) => p.interests));
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final i in Interest.values)
        BrutalChip('${i.emoji} ${i.label}', selected: picked.contains(i.name), color: C.lime, onTap: () {
          final p = ref.read(profileProvider);
          final next = picked.contains(i.name) ? ([...picked]..remove(i.name)) : [...picked, i.name];
          ref.read(profileProvider.notifier).save(p.copyWith(interests: next));
        }),
    ]);
  }
}

Future<void> editInterests(BuildContext context, WidgetRef ref) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const Border(top: border),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('What do you want to work on?', style: display(22)),
          const SizedBox(height: 6),
          const Text('We search Unstop for these and show them first. Change anytime on ME.', style: TextStyle(color: muted)),
          const SizedBox(height: 14),
          const InterestChips(),
          const SizedBox(height: 20),
          BrutalButton('Done', big: true, onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    );

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // Bumped after a resume import so the text fields rebuild with the new values.
  int _gen = 0;
  final _skill = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider);
    final n = ref.read(profileProvider.notifier);
    StudentProfile cur() => ref.read(profileProvider);

    Widget field(String label, String value, void Function(String) onChanged, {TextInputType? type, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: ValueKey('$label-$_gen'),
            initialValue: value,
            keyboardType: type,
            decoration: InputDecoration(labelText: label, isDense: true, helperText: hint, helperMaxLines: 2),
            onChanged: onChanged,
          ),
        );

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Row(children: [
            Expanded(child: Text(p.name.isEmpty ? 'Who are you?' : 'Hey, ${p.firstName}.', style: display(32))),
            const Sticker('proof > pdf', color: C.lime, angle: 6),
          ]),
          const SizedBox(height: 4),
          Text(
            p.isEmpty
                ? 'ProofPitch finds internships you actually qualify for and helps you pitch with your projects, not just a PDF. Start with your resume.'
                : 'Fill this once. Matching and every pitch pull from here.',
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          Brutal(
            color: C.yellow,
            onTap: () async {
              await importResume(context, ref);
              setState(() => _gen++);
            },
            child: Row(children: [
              const Text('📄', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.isEmpty ? 'Upload resume (PDF)' : 'Re-import resume', style: display(16)),
                  const Text('Auto-fills everything below. Read on your phone, never uploaded.'),
                ]),
              ),
              const Icon(Icons.upload_file_rounded),
            ]),
          ),
          const SectionTitle('Basics'),
          field('Name', p.name, (v) => n.save(cur().copyWith(name: v))),
          field('Call me', p.callMe, (v) => n.save(cur().copyWith(callMe: v.trim())),
              hint: "What emails say: “I'm ${p.firstName.isEmpty ? '…' : p.firstName}”. Leave empty to use your first name."),
          field('College', p.college, (v) => n.save(cur().copyWith(college: v))),
          Row(children: [
            Expanded(
              child: field('CGPA (out of 10)', p.cgpa?.toString() ?? '', type: const TextInputType.numberWithOptions(decimal: true),
                  (v) => n.save(cur().copyWith(cgpa: double.tryParse(v)))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: field('Grad year', p.graduationYear?.toString() ?? '', type: TextInputType.number,
                  (v) => n.save(cur().copyWith(graduationYear: int.tryParse(v)))),
            ),
          ]),
          field('Degree (B.Sc, B.Tech, BCA…)', p.degree, (v) => n.save(cur().copyWith(degree: v))),
          field('Email', p.email, type: TextInputType.emailAddress, (v) => n.save(cur().copyWith(email: v))),
          field('Phone', p.phone, type: TextInputType.phone, (v) => n.save(cur().copyWith(phone: v))),
          const SectionTitle('What do you want to work on?'),
          const Text('We search for these and show them first. Pick as many as you like.', style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          const InterestChips(),
          const SectionTitle('Where are you?'),
          const Text('Jobs in your city and remote jobs in your country rank first.', style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: field('City', p.city, (v) => n.save(cur().copyWith(city: v)))),
            const SizedBox(width: 12),
            Expanded(child: field('Country', p.country, (v) => n.save(cur().copyWith(country: v)))),
          ]),
          const SectionTitle('Links'),
          field('GitHub', p.github, type: TextInputType.url, (v) => n.save(cur().copyWith(github: v))),
          field('LinkedIn', p.linkedin, type: TextInputType.url, (v) => n.save(cur().copyWith(linkedin: v))),
          field('Portfolio', p.portfolio, type: TextInputType.url, (v) => n.save(cur().copyWith(portfolio: v))),
          const SectionTitle('Resume for emails'),
          Brutal(
            onTap: () => pickResumeFile(ref),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              const Text('📎', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.resumePath.isEmpty ? 'No PDF yet. Tap to pick the resume that goes with every email.' : p.resumePath.split(RegExp(r'[\\/]')).last,
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
                ),
              ),
              Text(p.resumePath.isEmpty ? 'Pick' : 'Change', style: const TextStyle(decoration: TextDecoration.underline)),
            ]),
          ),
          const SizedBox(height: 10),
          BrutalButton(
            'Edit my resume',
            icon: Icons.edit_note_rounded,
            color: C.yellow,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResumeEditorScreen())),
          ),
          const SizedBox(height: 4),
          const Text('Fix what the import got wrong or add sections; saving makes a fresh PDF for your emails.',
              style: TextStyle(color: muted, fontSize: 13)),
          SectionTitle('Skills · ${p.skills.length}'),
          const Text('These drive your match %. Tap one to remove it.', style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 8, children: [
            for (final s in p.skills)
              GestureDetector(
                onTap: () => n.save(cur().copyWith(skills: [...cur().skills]..remove(s))),
                child: Pill('$s  ✕', color: const Color(0xFFEAFFC2)),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _skill,
                decoration: const InputDecoration(labelText: 'Add a skill', isDense: true),
                onSubmitted: (_) => _addSkill(),
              ),
            ),
            const SizedBox(width: 10),
            BrutalButton('Add', onTap: _addSkill),
          ]),
          SectionTitle('Proof of work',
              trailing: BrutalButton('New', icon: Icons.add, color: C.yellow, onTap: () => _editProject(context, ref, null))),
          if (p.projects.isEmpty)
            const Brutal(
              child: Text('No projects yet. Add a repo, a Play Store app, a live demo or a Figma file. '
                  'Tag them with skills so pre-flight can match them to jobs.'),
            ),
          for (final proj in p.projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Brutal(
                onTap: () => _editProject(context, ref, proj),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(proj.name, style: display(16)),
                      if (proj.oneLiner.isNotEmpty) Text(proj.oneLiner, style: const TextStyle(color: muted)),
                      Text(proj.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      if (proj.tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 4, runSpacing: 4, children: [for (final t in proj.tags) Pill(t)]),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Pill(proj.kind.label, color: C.pink),
                ]),
              ),
            ),
          SectionTitle('Your email template',
              trailing: GestureDetector(
                onTap: () {
                  n.save(cur().copyWith(templateSubject: '', templateBody: ''));
                  setState(() => _gen++);
                },
                child: const Text('Reset', style: TextStyle(decoration: TextDecoration.underline)),
              )),
          const Text('Pick "My template" when you apply and this gets filled in for that job. You can still edit it before sending.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          field('Subject', p.templateSubject.isEmpty ? defaultTemplateSubject : p.templateSubject,
              (v) => n.save(cur().copyWith(templateSubject: v))),
          TextFormField(
            key: ValueKey('tpl-$_gen'),
            initialValue: p.templateBody.isEmpty ? defaultTemplateBody : p.templateBody,
            maxLines: null,
            minLines: 10,
            decoration: const InputDecoration(labelText: 'Body'),
            onChanged: (v) => n.save(cur().copyWith(templateBody: v)),
          ),
          const SizedBox(height: 8),
          const Text('Fill-ins: {company} {role} {name} {first_name} {college} {degree} {year} {cgpa} {skills} '
              '{project} {project_line} {project_link} {projects} {github} {linkedin} {portfolio} {phone} {email}',
              style: TextStyle(color: muted, fontSize: 13)),
        ],
      ),
    );
  }

  void _addSkill() {
    final s = canonSkill(_skill.text);
    if (s.isEmpty) return;
    final p = ref.read(profileProvider);
    if (!p.skills.contains(s)) ref.read(profileProvider.notifier).save(p.copyWith(skills: [...p.skills, s]));
    _skill.clear();
  }
}

Future<void> _editProject(BuildContext context, WidgetRef ref, Project? existing) async {
  final name = TextEditingController(text: existing?.name);
  final url = TextEditingController(text: existing?.url);
  final line = TextEditingController(text: existing?.oneLiner);
  final tags = TextEditingController(text: existing?.tags.join(', '));
  var kind = existing?.kind ?? ProjectKind.repo;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.cream,
    shape: const Border(top: border),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(existing == null ? 'New proof' : 'Edit proof', style: display(24)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ProjectKind.values)
                BrutalChip(k.label, selected: k == kind, onTap: () => setSheet(() => kind = k)),
            ]),
            const SizedBox(height: 14),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Project name')),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link'),
              onChanged: (v) => setSheet(() => kind = kindForUrl(v)),
            ),
            const SizedBox(height: 12),
            TextField(controller: line, decoration: const InputDecoration(labelText: 'One-liner (e.g. "2k installs, 4.6★")')),
            const SizedBox(height: 12),
            TextField(controller: tags, decoration: const InputDecoration(labelText: 'Skill tags, comma separated')),
            const SizedBox(height: 20),
            Row(children: [
              if (existing != null) ...[
                BrutalButton('Delete', color: C.red, onTap: () => Navigator.pop(ctx, false)),
                const SizedBox(width: 12),
              ],
              Expanded(child: BrutalButton('Save it', onTap: () => Navigator.pop(ctx, true))),
            ]),
          ]),
        ),
      ),
    ),
  );

  if (saved == null) return;
  final n = ref.read(profileProvider.notifier);
  final p = ref.read(profileProvider);
  final others = p.projects.where((x) => x.id != existing?.id).toList();
  if (!saved) {
    n.save(p.copyWith(projects: others));
    return;
  }
  if (name.text.trim().isEmpty || url.text.trim().isEmpty) return;
  final proj = Project(
    id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: name.text.trim(),
    url: url.text.trim(),
    kind: kind,
    oneLiner: line.text.trim(),
    tags: splitSkills(tags.text),
    bullets: existing?.bullets ?? const [],
  );
  final i = p.projects.indexWhere((x) => x.id == proj.id);
  n.save(p.copyWith(projects: i < 0 ? ([...p.projects, proj]) : ([...p.projects]..[i] = proj)));
}
