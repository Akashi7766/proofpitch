import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../engines.dart';
import '../feed.dart' show sourceLabel;
import '../insights.dart';
import '../models.dart';
import '../theme.dart';
import 'composer_screen.dart';

class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({super.key, required this.job});
  final JobListing job;
  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  late ParsedRules _rules = widget.job.rules;
  late Set<String> _selected;
  late final JobSummary _sum = summarize(widget.job);
  bool _showDesc = false;
  bool _showRules = false;

  int _hits(Project p) => p.tags.where(_rules.skills.contains).length;

  @override
  void initState() {
    super.initState();
    // Pre-select the two projects that cover the most job skills.
    final ps = [...ref.read(profileProvider).projects]..sort((a, b) => _hits(b).compareTo(_hits(a)));
    // Only attach projects that prove something this job asks for (a Unity game doesn't help a Flutter pitch).
    final relevant = ps.where((p) => _hits(p) > 0).take(2);
    _selected = (relevant.isEmpty ? ps.take(1) : relevant).map((p) => p.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final saved = ref.watch(savedProvider).containsKey(widget.job.id);
    final job = widget.job.copyWith(rules: _rules);
    final picked = profile.projects.where((p) => _selected.contains(p.id)).toList();
    final report = runPreflight(profile, job, picked);
    final ch = detectChannel(job.applyTarget);
    final hardFails = report.checks.where((c) => c.hard && !c.ok).length;
    final mine = profile.allSkills;
    final score = matchScore(mine, job);
    final age = ageLabel(job.postedAt);
    final daysLeft = job.deadline?.difference(DateTime.now()).inDays;

    final mode = workplaceOf(job);
    final facts = [
      _sum.pay == null ? '💰 Stipend not listed' : (_sum.pay == 'Unpaid' ? '🚫 Unpaid' : '💰 ${_sum.pay}'),
      switch (_sum.workplace) {
        'remote' => '🏠 Remote',
        'hybrid' => '🔀 Hybrid',
        'on-site' => '🏢 On-site',
        _ => '❔ Work mode not stated',
      },
      if (mode != 'remote' && job.location.isNotEmpty) '📍 ${job.location}',
      if (_sum.duration != null) '⏱ ${_sum.duration}',
      if (_rules.allowedBatches.isNotEmpty) '🎓 ${_rules.allowedBatches.join('/')} batch',
      if (_rules.minCgpa != null) '📊 CGPA ${_rules.minCgpa}+',
      if (job.department.isNotEmpty) '🏷 ${job.department}',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(cleanCompany(job.company)),
        actions: [
          SaveButton(
            saved: saved,
            onTap: () {
              final now = ref.read(savedProvider.notifier).toggle(widget.job);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(now ? 'Saved ♥' : 'Removed from saved')));
            },
          ),
          IconButton(
            tooltip: 'Copy link',
            icon: const Icon(Icons.link_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: job.applyTarget));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
            },
          ),
          IconButton(
            tooltip: 'Not interested',
            icon: const Icon(Icons.visibility_off_outlined),
            onPressed: () {
              ref.read(hiddenProvider.notifier).hide(job.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
        children: [
          Text(job.title, style: display(26).copyWith(height: 1.15)),
          const SizedBox(height: 8),
          Text(
            [job.location, if (age.isNotEmpty) 'posted $age'].where((e) => e.isNotEmpty).join('  ·  '),
            style: const TextStyle(color: muted),
          ),
          const SizedBox(height: 4),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Text('Found via ${sourceLabel(job)}', style: const TextStyle(color: muted, fontSize: 13)),
            if (job.sourceUrl.isNotEmpty)
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(job.sourceUrl), mode: LaunchMode.externalApplication),
                child: const Text('View original post',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill('${ch.emoji} ${channelLabel(job)}', color: channelColor[ch]!),
            if (daysLeft != null && daysLeft >= 0)
              Pill(daysLeft == 0 ? '⏰ closes today' : '⏰ closes in ${daysLeft}d', color: daysLeft < 7 ? C.red : C.white),
          ]),

          // ── Match ──
          if (mine.isNotEmpty && _rules.skills.isNotEmpty) ...[
            const SizedBox(height: 20),
            Brutal(
              color: Color.lerp(matchColor(score), C.white, 0.45)!,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  MatchBadge(score),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      !report.cleared
                          ? "You don't qualify yet — see pre-flight below."
                          : switch (score ?? 0) {
                              >= 70 => 'Strong fit. Your resume covers most of this.',
                              >= 40 => 'Decent fit. Lead with the overlap.',
                              _ => 'Stretch role. Show you learn fast.',
                            },
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in _rules.skills.where(mine.contains)) Pill('✓ $s', color: const Color(0xFFEAFFC2)),
                  for (final s in _rules.skills.where((s) => !mine.contains(s)))
                    GestureDetector(onTap: () => _claimSkill(s), child: Pill('✗ $s  +', color: C.white, textColor: muted)),
                ]),
                if (_rules.skills.any((s) => !mine.contains(s))) ...[
                  const SizedBox(height: 8),
                  const Text('Have one of the ✗ skills? Tap it to add it to your profile.', style: TextStyle(color: muted, fontSize: 12)),
                ],
              ]),
            ),
          ],

          // ── Summary ──
          const SectionTitle('The gist'),
          if (facts.isNotEmpty) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [for (final f in facts) Pill(f)]),
            const SizedBox(height: 12),
          ],
          Brutal(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_sum.tldr.isNotEmpty) Text(_sum.tldr, style: const TextStyle(fontSize: 16, height: 1.5)),
              if (_sum.tldr.isEmpty && _sum.doing.isEmpty && _sum.wants.isEmpty)
                const Text('No description to summarise. Check the full post.', style: TextStyle(color: muted)),
              if (_sum.doing.isNotEmpty) _Bullets("What you'll do", _sum.doing),
              if (_sum.wants.isNotEmpty) _Bullets('What they want', _sum.wants),
            ]),
          ),

          // ── Pre-flight ──
          SectionTitle(
            'Pre-flight',
            trailing: Stamp(
              key: ValueKey(report.cleared),
              child: StampLabel(report.cleared ? 'CLEARED' : 'GROUNDED', size: 16,
                  color: report.cleared ? const Color(0xFF1E9E3A) : C.red),
            ),
          ),
          Shake(
            trigger: hardFails,
            child: Brutal(
              color: report.cleared ? C.white : const Color(0xFFFFE1DB),
              child: Column(children: [
                if (report.checks.isEmpty) const Text('No hard requirements found. Send it.'),
                for (final c in report.checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.ok ? '✅' : (c.hard ? '⛔' : '⚠️'), style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c.label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 15)),
                          if (c.detail.isNotEmpty) Text(c.detail, style: const TextStyle(color: muted, fontSize: 13)),
                        ]),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
          if (report.swap != null) ...[
            const SizedBox(height: 12),
            Brutal(
              color: C.yellow,
              child: Row(children: [
                const Text('🔁', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Text(report.swap!, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                BrutalButton('Swap', color: C.white, onTap: () => setState(_applySwap)),
              ]),
            ),
          ],

          // ── Attach proof ──
          const SectionTitle('Attach proof'),
          if (profile.projects.isEmpty) const Text('Add projects on the ME tab first.', style: TextStyle(color: muted)),
          Wrap(spacing: 8, runSpacing: 10, children: [
            for (final p in profile.projects)
              BrutalChip(
                '${p.name} · ${_hits(p)} hits',
                selected: _selected.contains(p.id),
                color: C.lime,
                onTap: () => setState(() => _selected.contains(p.id) ? _selected.remove(p.id) : _selected.add(p.id)),
              ),
          ]),
          const SizedBox(height: 24),

          // ── Expandables ──
          _Expander(
            title: 'Fine-tune detected rules',
            open: _showRules,
            onTap: () => setState(() => _showRules = !_showRules),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Parsed from the post. Wrong? Fix it.", style: TextStyle(color: muted)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _rules.minCgpa?.toString() ?? '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min CGPA', isDense: true),
                    onChanged: (v) => setState(() => _rules = ParsedRules(
                        minCgpa: double.tryParse(v), allowedBatches: _rules.allowedBatches, skills: _rules.skills, minYears: _rules.minYears)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _rules.allowedBatches.join(', '),
                    decoration: const InputDecoration(labelText: 'Batches', isDense: true),
                    onChanged: (v) => setState(() => _rules = ParsedRules(
                          minCgpa: _rules.minCgpa,
                          allowedBatches: [for (final y in v.split(RegExp(r'[,\s]+'))) ?int.tryParse(y)],
                          skills: _rules.skills,
                          minYears: _rules.minYears,
                        )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: _rules.minYears == 0 ? '' : '${_rules.minYears}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Years exp.', isDense: true),
                    onChanged: (v) => setState(() => _rules = ParsedRules(
                        minCgpa: _rules.minCgpa, allowedBatches: _rules.allowedBatches, skills: _rules.skills, minYears: int.tryParse(v) ?? 0)),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 8, children: [
                for (final s in _rules.skills)
                  GestureDetector(
                    onTap: () => setState(() => _rules = ParsedRules(
                        minCgpa: _rules.minCgpa, allowedBatches: _rules.allowedBatches, skills: [..._rules.skills]..remove(s), minYears: _rules.minYears)),
                    child: Pill('$s  ✕'),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
          if (job.description.isNotEmpty)
            _Expander(
              title: 'Full job post',
              open: _showDesc,
              onTap: () => setState(() => _showDesc = !_showDesc),
              child: SelectableText(job.description, style: const TextStyle(height: 1.5)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          // No "pitch anyway": if you don't meet a hard requirement, the app won't let you send.
          child: report.cleared
              ? BrutalButton(
                  'Apply ✍️',
                  big: true,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComposerScreen(job: job, projects: picked))),
                )
              : BrutalButton(
                  report.blockers.length == 1 && picked.isEmpty ? 'Attach a project first' : '⛔ Not eligible — why?',
                  big: true,
                  color: const Color(0xFFFFD6CC),
                  onTap: () => _whyNot(context, report),
                ),
        ),
      ),
    );
  }

  void _whyNot(BuildContext context, PreflightReport report) => showModalBottomSheet(
        context: context,
        backgroundColor: C.cream,
        shape: const Border(top: border),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Why you can't apply", style: display(22)),
            const SizedBox(height: 12),
            for (final c in report.blockers)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('⛔ ', style: TextStyle(fontSize: 18)),
                  Expanded(child: Text('${c.label} — ${c.detail}')),
                ]),
              ),
            const SizedBox(height: 6),
            const Text('If something here is wrong (a skill you do have, a wrong batch), fix it on the ME tab or in '
                '"Fine-tune detected rules".', style: TextStyle(color: muted)),
          ]),
        ),
      );

  /// "I do have Docker": adds it to the profile (match %, pre-flight and every other job update), with undo.
  void _claimSkill(String skill) {
    final n = ref.read(profileProvider.notifier);
    final before = ref.read(profileProvider);
    n.save(before.copyWith(skills: [...before.skills, skill]));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Added $skill to your skills ✓'),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: C.white,
          onPressed: () {
            final now = ref.read(profileProvider);
            n.save(now.copyWith(skills: [...now.skills]..remove(skill)));
          },
        ),
      ));
  }

  void _applySwap() {
    final ps = ref.read(profileProvider).projects;
    final best = ps.reduce((a, b) => _hits(b) > _hits(a) ? b : a);
    final weakest = ps.where((p) => _selected.contains(p.id)).fold<Project?>(null, (w, p) => w == null || _hits(p) < _hits(w) ? p : w);
    if (weakest != null) _selected.remove(weakest.id);
    _selected.add(best.id);
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.title, this.items);
  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: display(12, C.blue)),
          const SizedBox(height: 6),
          for (final b in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 7, right: 10), child: SizedBox.square(dimension: 6, child: ColoredBox(color: C.ink))),
                Expanded(child: Text(b)),
              ]),
            ),
        ]),
      );
}

class _Expander extends StatelessWidget {
  const _Expander({required this.title, required this.open, required this.onTap, required this.child});
  final String title;
  final bool open;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: C.white, border: Border.fromBorderSide(border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(child: Text(title, style: display(15))),
                AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 250), child: const Icon(Icons.expand_more_rounded)),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open ? Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child) : const SizedBox.shrink(),
          ),
        ]),
      );
}
