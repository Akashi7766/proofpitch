import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cold.dart';
import '../data.dart';
import '../engines.dart';
import '../feed.dart';
import '../models.dart';
import '../outreach.dart';
import '../snow.dart';
import '../theme.dart';
import 'composer_screen.dart';

TextStyle _ice([double size = 16]) => display(size, Ice.ink);
const _iceMuted = TextStyle(color: Color(0xFF3E6A96));

/// ❄️ The cold-pitch list: small companies from your feed (and any you add), ready to write to.
class ColdScreen extends ConsumerStatefulWidget {
  const ColdScreen({super.key});
  @override
  ConsumerState<ColdScreen> createState() => _ColdScreenState();
}

class _ColdScreenState extends ConsumerState<ColdScreen> {
  final _add = TextEditingController();
  int _shown = 25;
  // Starts on the student's first field; "All" = null.
  late Interest? _field = interestByName(ref.read(profileProvider).interests.firstOrNull ?? '');

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final hidden = ref.watch(hiddenProvider);
    final manual = ref.watch(coldManualProvider);
    final apps = ref.watch(appsProvider);
    final jobs = [for (final j in [...ref.watch(manualJobsProvider), ...?ref.watch(boardJobsProvider).value?.jobs]) if (!hidden.contains(j.id)) j];
    final checked = checkedCompanies();
    final fromFeed = coldTargets(jobs, profile);
    final yc = ref.watch(ycTargetsProvider);
    final gh = _field == null ? null : ref.watch(githubTargetsProvider(_field!));
    final loading = [
      if (yc.isLoading) 'Y Combinator startups',
      if (gh?.isLoading ?? false) 'GitHub for ${_field!.label.toLowerCase()} companies in India',
    ];
    final targets = [
      for (final m in manual.reversed) ColdTarget(m, const [], const {'✍️ Added by you'}, const {}, JobListing(id: 'cold-$m', company: m, title: '', applyTarget: '')),
      ...mergeTargets([fromFeed, yc.value ?? const [], gh?.value ?? const []], field: _field)
          .where((t) => !manual.contains(t.company)),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          Row(children: [
            Text('Cold.', style: _ice(36)),
            const SizedBox(width: 10),
            const Sticker('no job post needed', color: Ice.glow, angle: -4),
          ]),
          const SizedBox(height: 8),
          const Text('Write to small companies that aren\'t advertising. No queue, a real person reads it, '
              'and you open with something useful you noticed about them.', style: _iceMuted),
          const SizedBox(height: 14),
          IceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How it works', style: _ice(14)),
              const SizedBox(height: 6),
              for (final step in const [
                '1  Pick a small company below (or add one).',
                '2  We find who hires there and check their website for visible problems.',
                '3  You send a short note offering to fix one. That\'s the pitch.',
              ])
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(step, style: const TextStyle(color: Ice.ink))),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _add,
                decoration: const InputDecoration(labelText: 'Add a company (name or website)', isDense: true),
                onSubmitted: (_) => _addCompany(),
              ),
            ),
            const SizedBox(width: 10),
            IceCard(onTap: _addCompany, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text('ADD', style: _ice(14))),
          ]),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in <Interest?>[null, ...Interest.values])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: BrutalChip(f == null ? 'All fields' : '${f.emoji} ${f.label}',
                      selected: _field == f, color: Ice.glow, onTap: () => setState(() {
                            _field = f;
                            _shown = 25;
                          })),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          Text('${targets.length} small companies to try', style: _ice(18)),
          const SizedBox(height: 4),
          const Text('Companies hiring in your feed first, then startups and studios found on the web. '
              'Big brands are left out: their inboxes are queues.', style: _iceMuted),
          for (final l in loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Ice.ink)),
                const SizedBox(width: 10),
                Expanded(child: Text('Searching $l…', style: const TextStyle(color: Ice.ink))),
              ]),
            ),
          const SizedBox(height: 12),
          if (targets.isEmpty)
            const IceCard(child: Text('Pull to refresh on 🔥 Jobs to load companies, or add one above.', style: TextStyle(color: Ice.ink))),
          for (final t in targets.take(_shown))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TargetCard(t, checked: checked[t.company], pitched: apps.containsKey(coldId(t.company))),
            ),
          if (targets.length > _shown)
            Center(child: TextButton(onPressed: () => setState(() => _shown += 25), child: const Text('Show more', style: TextStyle(color: Ice.ink)))),
        ],
      ),
    );
  }

  void _addCompany() {
    final v = _add.text.trim();
    if (v.isEmpty) return;
    ref.read(coldManualProvider.notifier).add(v);
    _add.clear();
    Navigator.push(context, MaterialPageRoute(builder: (_) => ColdTargetScreen(ColdTarget(v, const [], const {'✍️ Added by you'}, const {}, JobListing(id: coldId(v), company: v, title: '', applyTarget: v.contains('.') ? 'https://$v' : '')))));
  }
}

String coldId(String company) => 'cold-${company.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';

class _TargetCard extends StatelessWidget {
  const _TargetCard(this.t, {this.checked, this.pitched = false});
  final ColdTarget t;
  final List<SiteContact>? checked;
  final bool pitched;

  @override
  Widget build(BuildContext context) {
    final best = checked?.where((c) => !c.guessed).firstOrNull;
    final inbox = checked == null
        ? '❔ Not checked yet'
        : best == null
            ? '🕳 No inbox on their site'
            : best.role.index <= ContactRole.techLead.index
                ? '🎯 ${best.role.label} email found'
                : '📧 ${best.role.label}';
    return IceCard(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ColdTargetScreen(t))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(t.company, style: _ice(18), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (pitched) const Pill('PITCHED ✓', color: C.lime),
        ]),
        if (t.roles.isNotEmpty || t.about.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(t.roles.isNotEmpty ? 'They posted: ${t.roles.join(' · ')}' : t.about,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Ice.ink)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in t.sources) Pill(s, color: Colors.white, textColor: Ice.ink),
          if (t.githubOrg.isEmpty || checked != null) Pill(inbox, color: best != null ? const Color(0xFFDDF4FF) : Colors.white, textColor: Ice.ink),
        ]),
      ]),
    );
  }
}

/// One company: who to write to, what to offer, then the email.
class ColdTargetScreen extends ConsumerStatefulWidget {
  const ColdTargetScreen(this.target, {super.key});
  final ColdTarget target;
  @override
  ConsumerState<ColdTargetScreen> createState() => _ColdTargetScreenState();
}

class _ColdTargetScreenState extends ConsumerState<ColdTargetScreen> {
  EmailSearch? _found;
  SiteCheck? _site;
  bool _looking = true, _checking = false;
  final Set<int> _picked = {0, 1};
  SiteContact? _contact;
  final _own = TextEditingController();
  late String _company = widget.target.company; // a GitHub login becomes the real name once read
  late String _about = widget.target.about;
  bool _notCompany = false;

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    final sample = widget.target.sample;
    var job = sample.applyTarget.isEmpty ? JobListing(id: coldId(_company), company: _company, title: '', applyTarget: '') : sample;
    var orgEmail = '';
    if (widget.target.githubOrg.isNotEmpty) {
      final org = await fetchGithubOrg(widget.target.githubOrg).catchError((Object _) => null);
      if (!mounted) return;
      if (org == null) {
        setState(() {
          _notCompany = true;
          _looking = false;
          _found = const EmailSearch(null, []);
        });
        return;
      }
      final site = org.website.isEmpty || org.website.startsWith('http') ? org.website : 'https://${org.website}';
      setState(() {
        _company = org.name;
        _about = org.about;
      });
      // Their public email (if any) names the domain; else the website does; else we guess from the name.
      job = JobListing(id: coldId(widget.target.company), company: org.name, title: '', applyTarget: site, description: org.email);
      orgEmail = org.email;
    }
    EmailSearch found;
    try {
      found = await findCompanyEmails(job);
    } catch (_) {
      found = const EmailSearch(null, []);
    }
    if (orgEmail.isNotEmpty && !found.emails.contains(orgEmail)) {
      // The email on their GitHub profile is one they chose to publish: it goes in the list.
      final c = contactsInHtml('<a href="mailto:$orgEmail">$orgEmail</a>', domain: found.domain ?? '').firstOrNull ?? SiteContact(orgEmail, ContactRole.general);
      found = EmailSearch(found.domain, [...found.contacts, c]..sort((a, b) => a.role.index.compareTo(b.role.index)));
    }
    if (!mounted) return;
    setState(() {
      _found = found;
      _contact = found.contacts.firstOrNull;
      _looking = false;
    });
    if (found.domain != null) _checkSite(found.domain!);
  }

  Future<void> _checkSite(String domain) async {
    setState(() => _checking = true);
    SiteCheck? s;
    try {
      s = await checkSite(domain);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _site = s;
        _checking = false;
      });
    }
  }

  String get _whatTheyDo => (_site?.description ?? '').isNotEmpty ? _site!.description : _about;

  Interest? get _field {
    final mine = {for (final n in ref.read(profileProvider).interests) ?interestByName(n)};
    return widget.target.fields.where(mine.contains).firstOrNull ?? mine.firstOrNull;
  }

  void _write() {
    final profile = ref.read(profileProvider);
    final domain = _found?.domain;
    final holes = [for (final (i, h) in (_site?.holes ?? const <Hole>[]).indexed) if (_picked.contains(i)) h];
    final job = JobListing(
      id: coldId(widget.target.company),
      company: _company,
      title: 'Internship (cold pitch)',
      applyTarget: _contact?.email ?? (domain == null ? '' : 'https://$domain'),
      description: [_whatTheyDo, if (widget.target.roles.isNotEmpty) 'They posted: ${widget.target.roles.join(', ')}'].where((x) => x.isNotEmpty).join('\n'),
      source: 'Cold pitch',
      postedAt: DateTime.now(),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComposerScreen(
          job: job,
          projects: orderForPersona(profile.projects, Persona.founder),
          cold: ColdBrief(company: _company, domain: domain, contact: _contact, holes: holes, ownNote: _own.text, field: _field),
          knownContacts: _found?.contacts ?? const [],
          knownDomain: domain,
        ),
      ),
    );
  }

  Widget _step(String n, String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Container(width: 26, height: 26, alignment: Alignment.center, color: Ice.ink, child: Text(n, style: display(14, Colors.white))),
          const SizedBox(width: 10),
          Text(title, style: _ice(18)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = widget.target;
    final domain = _found?.domain;
    final holes = _site?.holes ?? const <Hole>[];
    return Stack(children: [
      const Positioned.fill(child: DecoratedBox(decoration: iceBackground)),
      const Positioned.fill(child: Snowfall(count: 45)),
      Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text('❄️ $_company', style: _ice(20)), iconTheme: const IconThemeData(color: Ice.ink)),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 140), children: [
          if (t.roles.isNotEmpty) Text('They posted: ${t.roles.join(' · ')}', style: const TextStyle(color: Ice.ink)),
          Text('Seen on: ${t.sources.join(', ')}', style: _iceMuted),
          if (_notCompany) ...[
            const SizedBox(height: 10),
            const IceCard(child: Text("Couldn't read their GitHub profile, or it's a college club rather than a company. Try another one.", style: TextStyle(color: Ice.ink))),
          ],
          if (_whatTheyDo.isNotEmpty) ...[
            const SizedBox(height: 10),
            IceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('WHAT THEY SAY THEY DO', style: display(11, Ice.ink)),
                const SizedBox(height: 4),
                Text(_whatTheyDo, style: const TextStyle(color: Ice.ink)),
              ]),
            ),
          ],

          _step('1', 'Who reads it'),
          if (_looking)
            const Row(children: [
              SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 3, color: Ice.ink)),
              SizedBox(width: 12),
              Expanded(child: Text('Finding their website and the person who hires…', style: TextStyle(color: Ice.ink))),
            ])
          else if (_found!.contacts.isEmpty)
            IceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(domain == null ? "Couldn't find their website." : 'No email listed on $domain.', style: const TextStyle(color: Ice.ink)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.linkedin.com/search/results/people/?keywords=${Uri.encodeComponent('$_company founder')}'),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('Find the founder on LinkedIn →', style: TextStyle(color: Ice.ink, fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
                ),
              ]),
            )
          else
            for (final c in _found!.contacts)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IceCard(
                  onTap: () => setState(() => _contact = c),
                  color: c == _contact ? const Color(0xFFD7F0FF) : Ice.frost,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(c == _contact ? Icons.radio_button_checked : Icons.radio_button_off, color: Ice.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.email, style: _ice(13)),
                        Text(c.label, style: _iceMuted.copyWith(fontSize: 12)),
                      ]),
                    ),
                    if (c.guessed) const Pill('GUESS', color: C.yellow),
                  ]),
                ),
              ),

          _step('2', 'Find a hole'),
          const Text('Only what any visitor can see. We never test their security: that\'s illegal without permission.', style: _iceMuted),
          const SizedBox(height: 10),
          if (_checking)
            const Row(children: [
              SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 3, color: Ice.ink)),
              SizedBox(width: 12),
              Expanded(child: Text('Checking their homepage: speed, phone layout, broken links…', style: TextStyle(color: Ice.ink))),
            ])
          else if (_site != null && holes.isEmpty)
            const IceCard(child: Text('Their homepage looks solid. Use the product yourself and write what you notice below: that\'s the best pitch anyway.', style: TextStyle(color: Ice.ink)))
          else
            for (final (i, h) in holes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IceCard(
                  onTap: () => setState(() => _picked.contains(i) ? _picked.remove(i) : _picked.add(i)),
                  color: _picked.contains(i) ? const Color(0xFFD7F0FF) : Ice.frost,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(_picked.contains(i) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, color: Ice.ink),
                    const SizedBox(width: 10),
                    Expanded(child: Text(h.title, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: Ice.ink))),
                  ]),
                ),
              ),
          const SizedBox(height: 10),
          TextField(
            controller: _own,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Noticed something yourself? (the strongest pitch)',
              hintText: 'e.g. "the signup OTP takes a minute to arrive"',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            if (domain != null)
              GestureDetector(
                onTap: () => launchUrl(Uri.parse('https://$domain'), mode: LaunchMode.externalApplication),
                child: const Text('Open their site', style: TextStyle(color: Ice.ink, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
              ),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://play.google.com/store/search?q=${Uri.encodeComponent(_company)}&c=apps'), mode: LaunchMode.externalApplication),
              child: const Text('Their app on Play Store (read the 1★ reviews)', style: TextStyle(color: Ice.ink, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ),
          ]),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            // Width-only sizing: in a bottom bar, Center would stretch to the whole screen height.
            child: SizedBox(
              width: double.infinity,
              child: IceCard(
                onTap: _looking ? null : _write,
                color: _looking ? Ice.frost : Ice.glow,
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(_looking ? 'LOOKING THEM UP…' : 'WRITE THE COLD EMAIL ❄️', style: _ice(18), textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
