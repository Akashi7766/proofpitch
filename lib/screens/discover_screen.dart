import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data.dart';
import '../engines.dart';
import '../feed.dart';
import '../insights.dart';
import '../models.dart';
import '../outreach.dart' show SharedLead, SiteContact, ContactRole;
import '../theme.dart';
import 'job_screen.dart';
import 'leads_sheet.dart';
import '../telegram.dart' show telegramName;
import 'profile_screen.dart' show editInterests;
import 'resume_import.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  FeedFilter _f = const FeedFilter();
  Map<String, List<SiteContact>> _checked = checkedCompanies();
  bool _scanning = false;
  int _scanDone = 0, _scanTotal = 0;

  Set<String> get _emailCompanies => {for (final e in _checked.entries) if (e.value.any((c) => !c.guessed)) e.key};

  /// Looks up the website + inbox of the next [batch] companies in the list (3 at a time, cached for good).
  Future<void> _scanEmails({int batch = 30}) async {
    if (_scanning) return;
    final profile = ref.read(profileProvider);
    final hidden = ref.read(hiddenProvider);
    final jobs = [for (final j in [...ref.read(manualJobsProvider), ...?ref.read(boardJobsProvider).value?.jobs]) if (!hidden.contains(j.id)) j];
    final seen = <String>{};
    final todo = [
      for (final r in rankFeed(jobs, profile, _f.copyWith(applyVia: ApplyVia.any), query: _q))
        if (!postHasEmail(r.job) && !_checked.containsKey(cleanCompany(r.job.company)) && seen.add(cleanCompany(r.job.company))) r.job,
    ].take(batch).toList();
    if (todo.isEmpty) return;
    setState(() {
      _scanning = true;
      _scanDone = 0;
      _scanTotal = todo.length;
    });
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length && mounted) {
        final j = todo[next++];
        try {
          await findCompanyEmails(j);
        } catch (_) {}
        if (mounted) {
          setState(() {
            _scanDone++;
            _checked = checkedCompanies();
          });
        }
      }
    }

    await Future.wait([worker(), worker(), worker()]);
    if (mounted) setState(() => _scanning = false);
  }

  void _setFilter(FeedFilter f) {
    setState(() => _f = f);
    if (f.applyVia == ApplyVia.email) _scanEmails();
  }

  /// "🎯 HR email" when we know the inbox reaches the hirer, "📧 Email" for any other real one.
  String? _emailBadge(JobListing j) {
    if (postHasEmail(j)) return '📧 Email in post';
    final best = _checked[cleanCompany(j.company)]?.where((c) => !c.guessed).firstOrNull;
    if (best == null) return null;
    return best.role.index <= ContactRole.techLead.index ? '🎯 ${best.role.label} email' : '📧 Email';
  }
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(boardJobsProvider);
    final manual = ref.watch(manualJobsProvider);
    final apps = ref.watch(appsProvider);
    final saved = ref.watch(savedProvider);
    final hidden = ref.watch(hiddenProvider);
    final lastVisit = ref.watch(lastVisitProvider);
    final profile = ref.watch(profileProvider);
    final fast = ref.watch(fastModeProvider);
    final mine = profile.allSkills;

    final jobs = [for (final j in [...manual, ...?feed.value?.jobs]) if (!hidden.contains(j.id)) j];
    final filter = fast ? FeedFilter.fast.copyWith(skills: _f.skills) : _f;
    final ranked = rankFeed(jobs, profile, filter.copyWith(eligibleOnly: false), query: _q, emailCompanies: _emailCompanies);
    final ineligible = ranked.where((e) => !e.ok).length;
    final shown = filter.eligibleOnly ? ranked.where((e) => e.ok).toList() : ranked;
    // Most internships are business/marketing; a narrow field can leave 0–5. Say so, and say how many exist elsewhere.
    final fieldLimited = filter.fields.isNotEmpty || (filter.myInterests && profile.interests.isNotEmpty);
    final elsewhere = fieldLimited && shown.length < 10
        ? rankFeed(jobs, profile, filter.copyWith(myInterests: false, fields: {}), query: _q, emailCompanies: _emailCompanies)
                .where((e) => e.ok || !filter.eligibleOnly)
                .length -
            shown.length
        : 0;

    final demand = <String, int>{};
    for (final j in jobs) {
      for (final s in j.rules.skills) {
        demand[s] = (demand[s] ?? 0) + 1;
      }
    }
    final now = DateTime.now();
    final sentToday = apps.values
        .where((a) => a.status != AppStatus.draft && a.updatedAt.year == now.year && a.updatedAt.month == now.month && a.updatedAt.day == now.day)
        .length;

    return Scaffold(
      floatingActionButton: BrutalButton('Lead', icon: Icons.add_rounded, color: C.pink, onTap: () => pasteLead(context, ref)),
      body: SafeArea(
        child: RefreshIndicator(
          color: C.ink,
          backgroundColor: C.lime,
          onRefresh: () => ref.refresh(boardJobsProvider.future),
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverList.list(children: [
                Row(children: [
                  Text('Hunt.', style: display(36)),
                  const SizedBox(width: 10),
                  if (feed.hasValue) Sticker('${shown.length}', color: C.lime, angle: -6),
                  const Spacer(),
                  _IconBox(Icons.travel_explore_rounded, 'Find more leads', () => showLeadsSheet(context, ref)),
                  const SizedBox(width: 8),
                  _IconBox(Icons.tune_rounded, 'Where jobs come from', () => _editBoards(context)),
                ]),
                const SizedBox(height: 14),
                if (fast)
                  _FastBanner(sent: sentToday, onExit: () => ref.read(fastModeProvider.notifier).set(false))
                else
                  Brutal(
                    color: C.white,
                    shadow: 3,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    onTap: () => ref.read(fastModeProvider.notifier).set(true),
                    child: Row(children: [
                      const Text('🚨', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Need an internship, any internship?', style: display(14)),
                          const Text('For OJT or a deadline: easiest wins you qualify for, first.', style: TextStyle(color: muted, fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.arrow_forward_rounded),
                    ]),
                  ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search roles, companies, skills', isDense: true),
                  onChanged: (v) => setState(() => _q = v),
                ),
                if (mine.isEmpty) ...[
                  const SizedBox(height: 14),
                  _Nudge('📄', 'Drop your resume', "We'll fill your profile and rank every job by how well you match.", () => importResume(context, ref)),
                ] else if (profile.interests.isEmpty && !fast) ...[
                  const SizedBox(height: 14),
                  _Nudge('🎯', 'What do you want to work on?', 'Pick a few fields. We search for them and show them first.',
                      () => editInterests(context, ref)),
                ],
              ]),
            ),
            if (!fast)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Row(children: [
                    _chip('⚙️ Filters${_f.advancedCount == 0 ? '' : ' · ${_f.advancedCount}'}', _f.advancedCount > 0, () => _openFilters(context),
                        color: C.yellow),
                    if (profile.interests.isNotEmpty)
                      _chip('🎯 My fields', _f.myInterests && _f.fields.isEmpty, () => setState(() => _f = _f.copyWith(myInterests: !_f.myInterests, fields: {}))),
                    _chip('✅ I qualify', _f.eligibleOnly, () => setState(() => _f = _f.copyWith(eligibleOnly: !_f.eligibleOnly))),
                    _chip('📍 Near me', _f.near, () => setState(() => _f = _f.copyWith(near: !_f.near))),
                    _chip('📧 Email', _f.applyVia == ApplyVia.email,
                        () => _setFilter(_f.copyWith(applyVia: _f.applyVia == ApplyVia.email ? ApplyVia.any : ApplyVia.email))),
                    _chip('🏢 Their careers page', _f.applyVia == ApplyVia.careersPage,
                        () => _setFilter(_f.copyWith(applyVia: _f.applyVia == ApplyVia.careersPage ? ApplyVia.any : ApplyVia.careersPage))),
                    _chip('💰 Paid', _f.paidOnly, () => setState(() => _f = _f.copyWith(paidOnly: !_f.paidOnly))),
                    _chip('🏠 Remote', _f.mode == WorkMode.remote,
                        () => setState(() => _f = _f.copyWith(mode: _f.mode == WorkMode.remote ? WorkMode.any : WorkMode.remote))),
                    _chip('🔥 This week', _f.maxAge == 7, () => setState(() => _f = _f.copyWith(maxAge: _f.maxAge == 7 ? maxAgeDays : 7))),
                  ]),
                ),
              ),
            if (mine.isNotEmpty)
              SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Row(children: [
                    Text('Jobs using:', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: muted)),
                    const SizedBox(width: 8),
                    // Your skills, most in-demand first; skills no listed job asks for are left out.
                    for (final s in (mine.where((s) => (demand[s] ?? 0) > 0).toList()..sort((a, b) => (demand[b] ?? 0).compareTo(demand[a] ?? 0))))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setState(() => _f = _f.copyWith(skills: _f.skills.contains(s) ? ({..._f.skills}..remove(s)) : {..._f.skills, s})),
                          child: Pill(s, color: _f.skills.contains(s) ? C.ink : C.white, textColor: _f.skills.contains(s) ? C.lime : C.ink),
                        ),
                      ),
                  ]),
                ),
              ),
            if (!fast && _f.applyVia == ApplyVia.email)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Brutal(
                    color: const Color(0xFFDDF4FF),
                    shadow: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      if (_scanning) ...[
                        const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 3, color: C.ink)),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          _scanning
                              ? 'Checking company websites for the person who hires… $_scanDone/$_scanTotal. Results appear as they come in.'
                              : 'Jobs with an inbox in the post or on their website. Checked ${_checked.length} companies so far.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      if (!_scanning) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _scanEmails,
                          child: const Text('Check 30 more', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            if (feed.value?.failed.isNotEmpty ?? false)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Text("Couldn't reach: ${feed.value!.failed.map(boardLabel).join(', ')}", style: const TextStyle(color: muted, fontSize: 13)),
                ),
              ),
            if (feed.isLoading && !feed.hasValue)
              // hasScrollBody: false lets it grow past the space left under a tall header instead of overflowing;
              // the bottom padding keeps the text clear of the LEAD button.
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 90),
                  child: EmptyState('🛰️', 'Scanning boards…', 'Pulling fresh listings from Unstop, company careers pages and Telegram. '
                      'The first load takes up to half a minute.'),
                ),
              )
            else if (feed.hasError && manual.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(padding: EdgeInsets.only(bottom: 90), child: EmptyState('🔌', 'No signal', 'Check your connection and pull to refresh.')),
              )
            else if (shown.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 90), // clear of the LEAD button
                  child: EmptyState(
                    '🦗',
                    'Crickets.',
                    _f.fields.isNotEmpty
                        ? 'No ${_f.fields.map((i) => i.label).join(' / ')} internships on your sources right now — Unstop has few of these. '
                            'Follow studios on Greenhouse/Lever (top-right), or Share → ProofPitch from a LinkedIn post.'
                        : 'Nothing matches these filters. Loosen them up or follow more companies.',
                    action: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (elsewhere > 0) ...[_fieldsHint(elsewhere), const SizedBox(height: 12)],
                      BrutalButton('Find more leads', icon: Icons.travel_explore_rounded, onTap: () => showLeadsSheet(context, ref)),
                      const SizedBox(height: 12),
                      BrutalButton('Reset filters', color: C.white, onTap: () => setState(() => _f = const FeedFilter(myInterests: false))),
                    ]),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                sliver: SliverList.builder(
                  itemCount: shown.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (elsewhere > 0) ...[_fieldsHint(elsewhere), const SizedBox(height: 12)],
                          Text(
                          [
                            'Sorted: ${filter.sort.label}',
                            if (filter.eligibleOnly && ineligible > 0) "$ineligible you don't qualify for hidden",
                            'posted in the last ${filter.maxAge} days',
                            'swipe → save, ← hide',
                          ].join(' · '),
                          style: const TextStyle(color: muted, fontSize: 13),
                          ),
                        ]),
                      );
                    }
                    final (job: j, :score, near: _, :ok, :ease) = shown[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _Swipeable(
                        job: j,
                        child: JobCard(
                          job: j,
                          score: mine.isEmpty ? null : score,
                          showScore: mine.isNotEmpty,
                          mine: mine,
                          isNew: j.postedAt != null && j.postedAt!.isAfter(lastVisit),
                          saved: saved.containsKey(j.id),
                          status: apps[j.id]?.status,
                          eligible: ok,
                          easyWin: fast && ease >= 6,
                          emailBadge: _emailBadge(j),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _fieldsHint(int elsewhere) => Brutal(
        color: C.yellow,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Few internships in your fields right now', style: display(15)),
          const SizedBox(height: 4),
          const Text('Most posted internships are in business and marketing. Small companies in your field are often '
              "hiring without posting: that's what Cold pitch is for."),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 8, children: [
            GestureDetector(
              onTap: () => setState(() => _f = _f.copyWith(myInterests: false, fields: {})),
              child: Text('See $elsewhere in other fields', style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
            ),
            GestureDetector(
              onTap: () => ref.read(coldModeProvider.notifier).set(true),
              child: const Text('❄️ Cold pitch companies in my field', style: TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline)),
            ),
          ]),
        ]),
      );

  Widget _chip(String label, bool on, VoidCallback onTap, {Color color = C.lime}) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: BrutalChip(label, selected: on, color: color, onTap: onTap),
      );

  Future<void> _openFilters(BuildContext context) async {
    final picked = await showModalBottomSheet<FeedFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const Border(top: border),
      builder: (_) => _FilterSheet(start: _f),
    );
    if (picked != null) _setFilter(picked);
  }

  void _editBoards(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: C.cream,
        shape: const Border(top: border),
        builder: (_) => const _BoardsSheet(),
      );
}

class _Nudge extends StatelessWidget {
  const _Nudge(this.emoji, this.title, this.body, this.onTap);
  final String emoji, title, body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Brutal(
        color: C.yellow,
        onTap: onTap,
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: display(16)), Text(body)])),
          const Icon(Icons.arrow_forward_rounded),
        ]),
      );
}

class _FastBanner extends StatelessWidget {
  const _FastBanner({required this.sent, required this.onExit});
  final int sent;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => Brutal(
        color: const Color(0xFFFFD6CC),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('🚨 NEED ONE FAST', style: display(18))),
            GestureDetector(onTap: onExit, child: const Text('Exit', style: TextStyle(decoration: TextDecoration.underline))),
          ]),
          const SizedBox(height: 6),
          const Text('Only jobs you qualify for, from the last 30 days, easiest first: small teams, few applicants, remote, '
              'fresh posts. Volume wins here: send a short pitch to each.'),
          const SizedBox(height: 12),
          Row(children: [
            Text('Today: $sent/$dailyFastGoal sent', style: display(13)),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 14,
                decoration: const BoxDecoration(color: C.white, border: Border.fromBorderSide(border)),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: (sent / dailyFastGoal).clamp(0, 1).toDouble(), child: Container(color: C.lime)),
              ),
            ),
          ]),
        ]),
      );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.start});
  final FeedFilter start;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late FeedFilter f = widget.start;

  Widget _group(String title, List<Widget> chips, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(), style: display(12, C.blue)),
          if (hint != null) Text(hint, style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ]),
      );

  Widget _c(String label, bool on, VoidCallback tap) => BrutalChip(label, selected: on, color: C.lime, onTap: () => setState(tap));

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(children: [
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), children: [
              Row(children: [
                Expanded(child: Text('Filters', style: display(24))),
                GestureDetector(
                  onTap: () => setState(() => f = const FeedFilter()),
                  child: const Text('Reset', style: TextStyle(decoration: TextDecoration.underline)),
                ),
              ]),
              _group('Sort by', [for (final s in SortBy.values) _c(s.label, f.sort == s, () => f = f.copyWith(sort: s))]),
              _group(
                'Fields',
                hint: 'None picked = your fields from the ME tab.',
                [
                  for (final i in Interest.values)
                    _c('${i.emoji} ${i.label}', f.fields.contains(i),
                        () => f = f.copyWith(fields: f.fields.contains(i) ? ({...f.fields}..remove(i)) : {...f.fields, i})),
                ],
              ),
              _group('Posted within', [
                for (final d in const [7, 14, 30, maxAgeDays]) _c(d == maxAgeDays ? '3 months' : '$d days', f.maxAge == d, () => f = f.copyWith(maxAge: d)),
              ]),
              _group('Work mode', [
                for (final (m, label) in const [
                  (WorkMode.any, 'Any'),
                  (WorkMode.remote, '🏠 Remote'),
                  (WorkMode.hybrid, '🔀 Hybrid'),
                  (WorkMode.onSite, '🏢 On-site'),
                ])
                  _c(label, f.mode == m, () => f = f.copyWith(mode: m)),
              ]),
              _group('Stipend (per month)', [
                _c('Any', !f.paidOnly && f.minStipend == 0, () => f = f.copyWith(paidOnly: false, minStipend: 0)),
                _c('Paid only', f.paidOnly && f.minStipend == 0, () => f = f.copyWith(paidOnly: true, minStipend: 0)),
                for (final k in const [5000, 10000, 20000])
                  _c('₹${k ~/ 1000}k+', f.minStipend == k, () => f = f.copyWith(paidOnly: true, minStipend: k)),
              ]),
              _group('How to apply', hint: 'Email = an inbox in the post or on their website (we check their site for you).', [
                _c('Any way', f.applyVia == ApplyVia.any, () => f = f.copyWith(applyVia: ApplyVia.any)),
                _c('📧 Email', f.applyVia == ApplyVia.email, () => f = f.copyWith(applyVia: ApplyVia.email)),
                _c('🏢 Their careers page', f.applyVia == ApplyVia.careersPage, () => f = f.copyWith(applyVia: ApplyVia.careersPage)),
              ]),
              _group('Where from', [
                _c('Everywhere', f.source == Source.all, () => f = f.copyWith(source: Source.all)),
                _c('Unstop', f.source == Source.unstop, () => f = f.copyWith(source: Source.unstop)),
                _c('Company careers pages', f.source == Source.companies, () => f = f.copyWith(source: Source.companies)),
                _c('✈️ Telegram', f.source == Source.telegram, () => f = f.copyWith(source: Source.telegram)),
              ]),
              _group('Type', [
                _c('🎓 Internships only', f.internsOnly, () => f = f.copyWith(internsOnly: true)),
                _c('All roles', !f.internsOnly, () => f = f.copyWith(internsOnly: false)),
              ]),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(width: double.infinity, child: BrutalButton('Show jobs', big: true, onTap: () => Navigator.pop(context, f))),
            ),
          ),
        ]),
      );
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Brutal(onTap: onTap, color: C.yellow, shadow: 3, padding: const EdgeInsets.all(8), child: Icon(icon, color: C.ink)),
      );
}

/// Swipe right to save, left to hide (with undo).
class _Swipeable extends ConsumerWidget {
  const _Swipeable({required this.job, required this.child});
  final JobListing job;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
        key: ValueKey('swipe-${job.id}'),
        background: _bg('♥ SAVE', C.pink, Alignment.centerLeft),
        secondaryBackground: _bg('HIDE ✕', const Color(0xFFD9D9D9), Alignment.centerRight),
        confirmDismiss: (dir) async {
          HapticFeedback.mediumImpact();
          final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
          if (dir == DismissDirection.startToEnd) {
            final nowSaved = ref.read(savedProvider.notifier).toggle(job);
            m.showSnackBar(SnackBar(content: Text(nowSaved ? 'Saved ♥ ${job.company}' : 'Removed from saved')));
            return false;
          }
          ref.read(hiddenProvider.notifier).hide(job.id);
          m.showSnackBar(SnackBar(
            content: Text('Hid ${job.title}'),
            action: SnackBarAction(label: 'UNDO', textColor: C.white, onPressed: () => ref.read(hiddenProvider.notifier).unhide(job.id)),
          ));
          return true;
        },
        child: child,
      );

  Widget _bg(String text, Color color, Alignment align) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: color, border: const Border.fromBorderSide(border)),
        child: Text(text, style: display(16)),
      );
}

class JobCard extends ConsumerWidget {
  const JobCard({
    super.key,
    required this.job,
    this.score,
    this.showScore = false,
    this.mine = const {},
    this.isNew = false,
    this.saved = false,
    this.status,
    this.onTap,
    this.eligible = true,
    this.easyWin = false,
    this.emailBadge,
  });

  final JobListing job;
  final int? score;
  final bool showScore;
  final Set<String> mine;
  final bool isNew;
  final bool saved;
  final AppStatus? status;
  final VoidCallback? onTap;
  final bool eligible;
  final bool easyWin;
  final String? emailBadge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final age = ageLabel(job.postedAt);
    final where = job.location;
    final mode = workplaceOf(job);
    final skills = [...job.rules.skills.where(mine.contains), ...job.rules.skills.where((s) => !mine.contains(s))].take(4);

    return Brutal(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(builder: (_) => JobScreen(job: job))),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: cleanCompany(job.company).toUpperCase(), style: display(12, C.blue)),
                if (age.isNotEmpty) TextSpan(text: '  ·  $age', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isNew) ...[const SizedBox(width: 8), const Pill('NEW', color: C.pink)],
          if (status != null) ...[const SizedBox(width: 8), Pill(status!.name.toUpperCase(), color: C.yellow)],
          SaveButton(saved: saved, onTap: () => ref.read(savedProvider.notifier).toggle(job)),
        ]),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(job.title, style: display(18).copyWith(height: 1.2)),
        ),
        if (where.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Pill(sourceLabel(job), color: const Color(0xFFF1ECE2), textColor: muted),
          Pill(switch (mode) { 'remote' => '🏠 Remote', 'hybrid' => '🔀 Hybrid', 'on-site' => '🏢 On-site', _ => '❔ Mode not stated' },
              color: mode == 'remote' ? const Color(0xFFDDF4FF) : C.white),
          Pill(
            job.stipend.isEmpty ? '💰 Stipend not listed' : (job.stipend == 'Unpaid' ? '🚫 Unpaid' : '💰 ${job.stipend}'),
            color: job.stipend.isEmpty || job.stipend == 'Unpaid' ? C.white : const Color(0xFFFFF0B3),
            textColor: job.stipend.isEmpty ? muted : C.ink,
          ),
          if (job.applicants != null) Pill('👥 ${applicantsLabel(job.applicants!)}', color: job.applicants! < 200 ? const Color(0xFFEAFFC2) : C.white),
          if (easyWin) const Pill('🎯 Easy win', color: C.lime),
          if (emailBadge != null) Pill(emailBadge!, color: const Color(0xFFDDF4FF)),
          if (!eligible) const Pill('⛔ Not eligible', color: Color(0xFFFFD6CC)),
        ]),
        if (showScore || skills.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (showScore) MatchBadge(score),
            for (final s in skills) Pill(mine.contains(s) ? '✓ $s' : s, color: mine.contains(s) ? const Color(0xFFEAFFC2) : C.white),
          ]),
        ],
      ]),
    );
  }
}

class _BoardsSheet extends ConsumerStatefulWidget {
  const _BoardsSheet();
  @override
  ConsumerState<_BoardsSheet> createState() => _BoardsSheetState();
}

class _BoardsSheetState extends ConsumerState<_BoardsSheet> {
  String _provider = 'greenhouse';
  final _slug = TextEditingController();
  final _channel = TextEditingController();
  String? _channelError;
  bool _showGlobal = false;

  void _addChannel(List<String> followed) {
    final name = telegramName(_channel.text);
    if (name == null) {
      setState(() => _channelError = 'Paste @name or a t.me/name link');
      return;
    }
    if (!followed.contains('telegram:$name')) ref.read(boardsProvider.notifier).toggle('telegram:$name');
    _channel.clear();
    setState(() => _channelError = null);
  }

  @override
  Widget build(BuildContext context) {
    final followed = ref.watch(boardsProvider);
    final india = {...indiaBoards, ...followed.where((b) => !b.startsWith('telegram:') && !b.startsWith('unstop:') && !globalBoards.contains(b))}.toList();
    final channels = {...suggestedChannels, ...followed.where((b) => b.startsWith('telegram:'))}.toList();
    final n = ref.read(boardsProvider.notifier);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Where jobs come from', style: display(22)),
          const SizedBox(height: 6),
          const Text('Tap to switch a source on or off. All public; nothing needs a login.', style: TextStyle(color: muted)),
          const SizedBox(height: 16),
          Text('🟣 Unstop', style: display(16)),
          const SizedBox(height: 4),
          const Text("India's biggest public internship feed. Searched with your fields and skills.", style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          BrutalChip('Unstop internships', selected: followed.contains('unstop:internships'), color: C.lime, onTap: () => n.toggle('unstop:internships')),
          const SizedBox(height: 24),
          Text('✈️ Telegram channels', style: display(16)),
          const SizedBox(height: 4),
          const Text(
            'Public job channels you trust. We read their newest posts (no login) and tag every job with its channel. '
            'Suggestions were live and posting Indian jobs as of Oct 2026; channels mix in reposts and ads, so keep the ones that help.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 10, children: [
            for (final b in channels)
              BrutalChip('@${b.split(':')[1]}', selected: followed.contains(b), color: const Color(0xFF9AD8FF), onTap: () => n.toggle(b)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _channel,
                decoration: InputDecoration(labelText: '@channel or t.me/channel', errorText: _channelError),
                onSubmitted: (_) => _addChannel(followed),
              ),
            ),
            const SizedBox(width: 12),
            BrutalButton('Add', onTap: () => _addChannel(followed)),
          ]),
          const SizedBox(height: 24),
          Text("🏢 Indian companies' careers pages", style: display(16)),
          const SizedBox(height: 4),
          const Text('Straight from their own job boards. Mostly full-time roles; internships show up a few times a year.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 10, children: [
            for (final b in india) BrutalChip(boardLabel(b), selected: followed.contains(b), color: C.lime, onTap: () => n.toggle(b)),
          ]),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _showGlobal = !_showGlobal),
            child: Text(_showGlobal ? '▾ Global companies' : '▸ Global companies (mostly US roles)',
                style: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          ),
          if (_showGlobal) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 10, children: [
              for (final b in globalBoards) BrutalChip(boardLabel(b), selected: followed.contains(b), color: C.lime, onTap: () => n.toggle(b)),
            ]),
          ],
          const SizedBox(height: 24),
          Text('Add any company board', style: display(16)),
          const SizedBox(height: 4),
          const Text('The slug is the company bit in the careers URL, e.g. jobs.lever.co/<slug>.', style: TextStyle(color: muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final p in ['greenhouse', 'lever', 'ashby', 'smartrecruiters'])
              BrutalChip(p, selected: _provider == p, color: C.yellow, onTap: () => setState(() => _provider = p)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _slug, decoration: const InputDecoration(labelText: 'Board slug'))),
            const SizedBox(width: 12),
            BrutalButton('Follow', onTap: () {
              final s = _slug.text.trim().toLowerCase();
              if (s.isEmpty) return;
              final key = '$_provider:$s';
              if (!followed.contains(key)) n.toggle(key);
              _slug.clear();
            }),
          ]),
        ]),
      ),
    );
  }
}

/// Add a lead by hand, or confirm one parsed from a shared post ([prefill]). Opens the job once added.
Future<void> pasteLead(BuildContext context, WidgetRef ref, {SharedLead? prefill}) async {
  final company = TextEditingController(text: prefill?.company);
  final title = TextEditingController(text: prefill?.title ?? 'Software Engineering Intern');
  final target = TextEditingController(text: prefill?.target);
  final where = TextEditingController(text: prefill?.location);
  final desc = TextEditingController(text: prefill?.description);

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.cream,
    shape: const Border(top: border),
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(prefill == null ? 'Found a lead?' : 'From the post you shared', style: display(24)),
          const SizedBox(height: 6),
          Text(prefill == null ? "A founder's email from a tweet, a careers link, a Workday page — drop it here. Tip: in LinkedIn or Reddit, tap Share → ProofPitch." : 'We filled what we could. Check the company and the email or link, then add it.', style: const TextStyle(color: muted)),
          const SizedBox(height: 14),
          TextField(controller: company, decoration: const InputDecoration(labelText: 'Company')),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Role')),
          const SizedBox(height: 12),
          TextField(controller: target, decoration: const InputDecoration(labelText: 'Apply link or email')),
          const SizedBox(height: 12),
          TextField(controller: where, decoration: const InputDecoration(labelText: 'Location (e.g. Mumbai, India — or Remote)')),
          const SizedBox(height: 12),
          TextField(
            controller: desc,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Paste the job description (optional, powers matching)'),
          ),
          const SizedBox(height: 20),
          BrutalButton('Add lead', icon: Icons.add, onTap: () => Navigator.pop(ctx, true)),
        ]),
      ),
    ),
  );
  if (ok != true || company.text.trim().isEmpty || target.text.trim().isEmpty) return;
  final job = JobListing(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        company: company.text.trim(),
        title: title.text.trim(),
        applyTarget: target.text.trim(),
        description: desc.text.trim(),
        location: where.text.trim(),
        rules: parseRules('${title.text}\n${desc.text}', company: company.text.trim()),
        stipend: payFromText(desc.text) ?? '',
        postedAt: DateTime.now(),
        source: prefill != null ? 'Shared post' : 'Added by you',
      );
  ref.read(manualJobsProvider.notifier).add(job);
  if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => JobScreen(job: job)));
}
