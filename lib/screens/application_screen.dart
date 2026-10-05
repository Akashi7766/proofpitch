import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../engines.dart';
import '../feed.dart' show sourceLabel;
import '../followup.dart';
import '../insights.dart';
import '../models.dart';
import '../outreach.dart' show ContactRole;
import '../theme.dart';
import 'job_screen.dart';

const _stages = [
  (AppStatus.draft, '📝 Draft', C.white),
  (AppStatus.sent, '📤 Sent', C.lime),
  (AppStatus.followedUp, '👋 Followed up', C.yellow),
  (AppStatus.replied, '🎉 Replied', C.pink),
  (AppStatus.rejected, '🪦 Nope', Color(0xFFD9D9D9)),
];

/// One application: where it stands, the company, what you sent, and what to do if they reply.
class ApplicationScreen extends ConsumerStatefulWidget {
  const ApplicationScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends ConsumerState<ApplicationScreen> {
  late final _notes = TextEditingController(text: ref.read(appsProvider)[widget.jobId]?.notes ?? '');
  bool _showSent = false;

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied 📋')));
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(appsProvider)[widget.jobId];
    if (a == null) return const Scaffold(body: EmptyState('🪦', 'Gone', 'This application was deleted.'));
    final profile = ref.watch(profileProvider);
    final job = a.job;
    final company = cleanCompany(job.company);
    final kit = followUpKit(a, profile);
    final domain = knownDomain(company);
    final people = checkedCompanies()[company] ?? const [];
    final gist = summarize(job);
    // The summary, else what you'd do, else the post's first real line (not a "Responsibilities:" heading).
    final about = gist.tldr.isNotEmpty
        ? gist.tldr
        : gist.doing.isNotEmpty
            ? "You'd ${gist.doing.take(2).map((d) => d.isEmpty ? d : d[0].toLowerCase() + d.substring(1)).join('; ')}."
            : job.description.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 30 && !l.endsWith(':'), orElse: () => '');
    final n = ref.read(appsProvider.notifier);
    final email = a.to.contains('@');

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: display(12, C.blue)),
            const SizedBox(height: 8),
            ...children,
          ]),
        );
    Widget bullet(String t, [String mark = '•']) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(mark)),
            Expanded(child: Text(t)),
          ]),
        );
    Widget link(String label, String url) => GestureDetector(
          onTap: () => _open(url),
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(company),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              n.remove(job.id);
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
        children: [
          Text(job.title, style: display(22).copyWith(height: 1.15)),
          const SizedBox(height: 4),
          Text([sourceLabel(job), if (a.to.isNotEmpty) 'to ${a.to}', 'updated ${ageLabel(a.updatedAt)}'].join('  ·  '),
              style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (s, label, color) in _stages)
              BrutalChip(label, selected: a.status == s, color: color, onTap: () => n.put(a.copyWith(status: s))),
          ]),
          const SizedBox(height: 14),
          Brutal(
            color: a.status == AppStatus.replied ? C.lime : C.yellow,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('👉 ', style: TextStyle(fontSize: 18)),
              Expanded(child: Text(kit.nextStep, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700))),
            ]),
          ),

          // ── The company ──
          section('About $company', [
            Brutal(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (about.isNotEmpty) Text(about),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  if (job.location.isNotEmpty) Pill('📍 ${job.location}'),
                  if (job.stipend.isNotEmpty) Pill('💰 ${job.stipend}'),
                  if (workplaceOf(job).isNotEmpty)
                    Pill(switch (workplaceOf(job)) { 'remote' => '🏠 Remote', 'hybrid' => '🔀 Hybrid', _ => '🏢 On-site' }),
                  if (job.postedAt != null) Pill('posted ${ageLabel(job.postedAt)}'),
                ]),
                const SizedBox(height: 10),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  if (domain != null) link('🌐 $domain', 'https://$domain'),
                  if (job.applyTarget.startsWith('http')) link('Job post', job.applyTarget),
                  if (job.sourceUrl.isNotEmpty) link('Original post', job.sourceUrl),
                  link('LinkedIn page', 'https://www.linkedin.com/search/results/companies/?keywords=${Uri.encodeComponent(company)}'),
                  if (job.source != 'Cold pitch')
                    GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobScreen(job: job))),
                      child: const Text('Full job details', style: TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                    ),
                ]),
              ]),
            ),
            if (people.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('People we found on their site:', style: TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 4),
              for (final p in people)
                bullet('${p.label}: ${p.email}${p.guessed ? ' (guess)' : ''}', p.role.index <= ContactRole.techLead.index ? '🎯' : '📧'),
            ],
          ]),

          // ── What you sent ──
          if (a.body.isNotEmpty || a.subject.isNotEmpty)
            section('What you sent', [
              Brutal(
                onTap: () => setState(() => _showSent = !_showSent),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (a.subject.isNotEmpty) Text(a.subject, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
                  if (a.body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(a.body, maxLines: _showSent ? null : 4, overflow: _showSent ? null : TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(_showSent ? 'Show less' : 'Show all', style: const TextStyle(color: muted, decoration: TextDecoration.underline)),
                  ],
                ]),
              ),
            ]),

          // ── If they reply ──
          section('If they call you: prepare', [for (final p in kit.prep) bullet(p, '✅')]),
          section('Ask them', [for (final q in kit.askThem) bullet(q, '❓')]),
          section('Red flags: walk away if…', [for (final r in kit.redFlags) bullet(r, '🚩')]),
          section('Replies, ready to send', [
            for (final r in kit.replies)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Brutal(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.when, style: display(14)),
                    const SizedBox(height: 6),
                    Text(r.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
                    const SizedBox(height: 8),
                    Row(children: [
                      GestureDetector(
                        onTap: () => _copy(r.body, 'Reply'),
                        child: const Text('Copy', style: TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                      ),
                      if (email) ...[
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => launchUrl(buildMailto(a.to, r.subject, r.body)),
                          child: Text('Email ${a.to}', style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                        ),
                      ],
                    ]),
                  ]),
                ),
              ),
            const Text('Fill in the [brackets] before sending.', style: TextStyle(color: muted, fontSize: 13)),
          ]),

          // ── Notes ──
          section('Your notes', [
            TextField(
              controller: _notes,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Who replied, interview date, what they asked…'),
              onChanged: (v) => n.put(a.copyWith(notes: v)),
            ),
          ]),
        ],
      ),
    );
  }
}
