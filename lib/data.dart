import 'dart:convert';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:http/http.dart' as http;

import 'engines.dart';
import 'cold.dart' show ColdTarget, Hole, auditPage, githubOrgInfo, githubTargets, githubTerms, siteDescription, ycTargets;
import 'feed.dart';
import 'insights.dart' show payFromText;
import 'models.dart';
import 'telegram.dart' show parseTelegramPage;
import 'outreach.dart' show contactsInHtml, robotsAllows, domainFromSuggest, companyDomain, domainCandidates, siteScore, SiteContact, ContactRole;

// ───────────────────────── ATS client ─────────────────────────

/// Board keys look like `greenhouse:figma`, `lever:spotify`, `ashby:ramp`, `unstop:internships`.
/// Unstop's public API is allowed by its robots.txt; Internshala's isn't, so it's not here.
const presetBoards = ['unstop:internships', ...indiaBoards, ...globalBoards];

/// India-based teams on public ATS boards (probed 2026-10-04: each had live India roles).
const indiaBoards = [
  'greenhouse:groww', 'greenhouse:rubrik', 'greenhouse:druva', 'greenhouse:razorpaysoftwareprivatelimited',
  'greenhouse:highradius', 'greenhouse:inmobi', 'greenhouse:sigmoid', 'greenhouse:zenoti', 'greenhouse:glance',
  'greenhouse:stage', 'greenhouse:slice', 'greenhouse:observeai', 'greenhouse:thoughtworks',
  'lever:paytm', 'lever:fampay', 'lever:meesho', 'lever:zeta', 'lever:cred', 'lever:mindtickle', 'lever:pocketfm',
  'ashby:sarvam', 'ashby:plane', 'ashby:atlan', 'ashby:spotdraft',
  'smartrecruiters:swiggy', 'smartrecruiters:freshworks', 'smartrecruiters:ixigo',
];

/// Mostly US/EU roles; kept for students who can work there or want remote.
const globalBoards = [
  'greenhouse:figma', 'greenhouse:discord', 'greenhouse:stripe', 'greenhouse:databricks',
  'greenhouse:robinhood', 'greenhouse:cloudflare', 'greenhouse:duolingo', 'greenhouse:reddit',
  'greenhouse:coinbase', 'greenhouse:anthropic', 'lever:palantir', 'lever:spotify',
  'ashby:ramp', 'ashby:linear', 'ashby:openai', 'ashby:notion', 'ashby:supabase', 'ashby:replit',
];

/// Public Telegram job channels checked on 2026-10-04: live, posting Indian internships/fresher roles.
/// All four are followed by default (more volume); the first two are mostly internships.
const suggestedChannels = ['telegram:jobs_and_internships_updates', 'telegram:goyalarsh', 'telegram:offcampusjobs4u', 'telegram:dot_aware'];

// India first: the old global defaults were mostly US roles the student can't take.
const _defaultBoards = [
  'unstop:internships', 'greenhouse:groww', 'greenhouse:rubrik', 'greenhouse:stage', 'greenhouse:inmobi',
  'greenhouse:sigmoid', 'greenhouse:glance', 'lever:paytm', 'lever:fampay', 'lever:meesho', 'ashby:sarvam',
  'smartrecruiters:swiggy', 'smartrecruiters:freshworks',
  'telegram:jobs_and_internships_updates', 'telegram:goyalarsh', 'telegram:offcampusjobs4u', 'telegram:dot_aware',
];

String boardLabel(String board) => board.startsWith('unstop:')
    ? 'Unstop'
    : board.startsWith('telegram:')
        ? '@${board.split(':').last}'
        : board.split(':').last;

const _entities = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'rsquo': '’', 'lsquo': '‘',
  'rdquo': '”', 'ldquo': '“', 'mdash': '—', 'ndash': '–', 'hellip': '…', 'bull': '•',
};

String _unescape(String s) => s.replaceAllMapped(RegExp(r'&(#x?[0-9a-f]+|[a-z]+);', caseSensitive: false), (m) {
      final e = m[1]!;
      if (e.startsWith('#x') || e.startsWith('#X')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
      return _entities[e.toLowerCase()] ?? m[0]!;
    });

String htmlToText(String html) {
  var s = _unescape(_unescape(html)); // Greenhouse double-escapes.
  s = s
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'<(br|/p|/div|/h\d|/li|/ul)[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n\s*\n\s*(\n\s*)+'), '\n\n');
  return s.trim();
}

String _titleCase(String slug) => slug.isEmpty ? slug : slug[0].toUpperCase() + slug.substring(1);

JobListing _job(String id, String company, String title, String url, String location, String description,
        {DateTime? posted, String department = '', String workplace = '', DateTime? deadline}) =>
    JobListing(
      id: id,
      company: company,
      title: title.trim(),
      applyTarget: url,
      location: location,
      description: description,
      rules: parseRules('$title\n$description', company: company),
      postedAt: posted,
      department: department,
      workplace: workplace.toLowerCase().replaceAll('onsite', 'on-site'),
      deadline: deadline,
      stipend: payFromText(description) ?? '',
    );

DateTime? _date(Object? v) => switch (v) {
      int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      String s => DateTime.tryParse(s),
      _ => null,
    };

String _k(num n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k' : '$n';

/// Unstop's structured job → our model. Stipend, work mode, cities and eligibility come straight from the API.
JobListing unstopJob(Map j) {
  final jd = (j['jobDetail'] as Map?) ?? const {};
  final places = [
    for (final l in (j['locations'] as List? ?? const []))
      if (l is Map && l['city'] != null) (l['city'] as String, (l['country'] as String?) ?? 'India'),
  ];
  final cities = places.map((e) => e.$1).toSet().toList();
  final country = places.isEmpty ? 'India' : places.first.$2;
  final mode = switch (jd['type']) { 'wfh' => 'remote', 'hybrid' => 'hybrid', 'in_office' => 'on-site', _ => '' };
  final where = cities.isEmpty || mode == 'remote'
      ? (mode == 'remote' ? 'Remote, $country' : country)
      : '${cities.take(3).join(', ')}${cities.length > 3 ? ' +${cities.length - 3}' : ''}, $country';

  final min = jd['min_salary'] as num?, max = jd['max_salary'] as num?;
  final per = switch (jd['pay_in']) { 'monthly' => '/month', 'weekly' => '/week', 'hourly' => '/hour', _ => '' };
  final stipend = jd['paid_unpaid'] == 'unpaid'
      ? 'Unpaid'
      : (min == null && max == null) || jd['not_disclosed'] == true
          ? ''
          : '₹${min == null || min == max ? _k(max!) : max == null ? _k(min) : '${_k(min)}–${_k(max)}'}$per';

  final company = ((j['organisation'] as Map?)?['name'] as String?) ?? 'Unstop';
  final desc = htmlToText(j['details'] ?? '');
  final title = (j['title'] as String? ?? '').trim();
  final parsed = parseRules('$title\n$desc', company: company);
  final required = [
    for (final s in (j['required_skills'] as List? ?? const []))
      if (s is Map) canonSkill(s['skill_name'] ?? s['skill'] ?? ''),
  ].where((s) => s.isNotEmpty);

  return JobListing(
    id: 'us-${j['id']}',
    company: company,
    title: title,
    applyTarget: j['seo_url'] ?? 'https://unstop.com/${j['public_url']}',
    location: where,
    description: desc,
    rules: ParsedRules(
      minCgpa: parsed.minCgpa,
      allowedBatches: parsed.allowedBatches,
      skills: {...required, ...parsed.skills}.toList(),
      minYears: parsed.minYears,
    ),
    postedAt: DateTime.tryParse((j['approved_date'] as String? ?? '').replaceFirst(' GMT', '')) ??
        DateTime.tryParse(j['updated_at'] ?? ''),
    department: [for (final w in (j['workfunction'] as List? ?? const [])) if (w is Map) w['name']].join(', '),
    workplace: mode,
    deadline: DateTime.tryParse(j['end_date'] ?? ''),
    stipend: stipend.isEmpty ? (payFromText(desc) ?? '') : stipend,
    eligibleGroups: [
      for (final f in (j['filters'] as List? ?? const []))
        if (f is Map && f['type'] == 'eligible') f['name'] as String,
    ],
    applicants: (j['registerCount'] as num?)?.toInt(),
  );
}

Future<List<JobListing>> _fetchUnstop(http.Client c) async {
  // UNSTOP_BASE lets the web build go through tool/cors_proxy.dart; phones hit unstop.com directly.
  const host = String.fromEnvironment('UNSTOP_BASE', defaultValue: 'https://unstop.com');
  const base = '$host/api/public/opportunity/search-result?opportunity=internships&oppstatus=open';
  final urls = [
    // Every open internship (~730 in Oct 2026, 8 pages); pages past the end just come back empty.
    for (var p = 1; p <= 10; p++) '$base&page=$p&per_page=100',
    // Some companies post internships under "jobs".
    '$host/api/public/opportunity/search-result?opportunity=jobs&oppstatus=open&page=1&per_page=100&searchTerm=intern',
  ];
  final pages = await Future.wait(urls.map((u) async {
    final jobsQuery = u.contains('opportunity=jobs');
    try {
      final r = await c.get(Uri.parse(u)).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return const <dynamic>[];
      final list = (jsonDecode(utf8.decode(r.bodyBytes))['data'] as Map)['data'] as List;
      // The "intern" search on jobs also matches "internal"/"international"; keep real internships.
      return jobsQuery ? [for (final j in list) if (j is Map && isInternship(JobListing(id: '', company: '', title: '${j['title']}', applyTarget: ''))) j] : list;
    } catch (_) {
      return const <dynamic>[];
    }
  }));
  final byId = <String, JobListing>{};
  for (final j in pages.expand((p) => p)) {
    if (j is Map) byId.putIfAbsent('us-${j['id']}', () => unstopJob(j));
  }
  if (byId.isEmpty) throw Exception('unstop unreachable');
  return byId.values.toList();
}

/// SmartRecruiters' list has no descriptions, so details are fetched only for internships, and for the
/// newest few other roles (enough to match skills), to keep it to a handful of requests.
Future<List<JobListing>> _fetchSmartRecruiters(http.Client c, String slug) async {
  final r = await c.get(Uri.parse('https://api.smartrecruiters.com/v1/companies/$slug/postings?limit=100')).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('smartrecruiters:$slug → HTTP ${r.statusCode}');
  final list = (jsonDecode(utf8.decode(r.bodyBytes))['content'] as List).cast<Map>();
  final wanted = {
    for (final j in [...list.where((j) => isInternship(JobListing(id: '', company: '', title: j['name'] ?? '', applyTarget: ''))), ...list.take(15)])
      '${j['id']}',
  };
  // Every posting is kept; only the wanted ones cost an extra request for their description.
  final details = await Future.wait([
    for (final j in list)
      wanted.contains('${j['id']}')
          ? c.get(Uri.parse(j['ref'])).timeout(const Duration(seconds: 20)).then((d) => d.statusCode == 200 ? jsonDecode(utf8.decode(d.bodyBytes)) as Map : j).catchError((Object _) => j)
          : Future.value(j),
  ]);
  return [
    for (final d in details)
      () {
        final loc = (d['location'] as Map?) ?? const {};
        final sections = ((d['jobAd'] as Map?)?['sections'] as Map?) ?? const {};
        final text = [for (final k in ['jobDescription', 'qualifications', 'companyDescription']) htmlToText((sections[k] as Map?)?['text'] ?? '')]
            .where((t) => t.isNotEmpty)
            .join('\n\n');
        final company = ((d['company'] as Map?)?['name'] as String?) ?? _titleCase(slug);
        return _job(
          'sr-${d['id']}',
          company.toUpperCase() == company ? _titleCase(company.toLowerCase()) : company,
          d['name'] ?? '',
          d['postingUrl'] ?? 'https://jobs.smartrecruiters.com/${(d['company'] as Map?)?['identifier'] ?? slug}/${d['id']}',
          [loc['city'], loc['country'] == 'in' ? 'India' : loc['country']].whereType<String>().where((s) => s.isNotEmpty).join(', '),
          text,
          posted: _date(d['releasedDate']),
          department: ((d['department'] as Map?)?['label'] as String?) ?? '',
          workplace: loc['remote'] == true ? 'remote' : (loc['hybrid'] == true ? 'hybrid' : ''),
        );
      }(),
  ];
}

/// A public channel's web preview: the newest page and the one before it (~40 posts).
Future<List<JobListing>> _fetchTelegram(http.Client c, String channel) async {
  Future<String> page([int? before]) async {
    final r = await c
        .get(Uri.parse('https://t.me/s/$channel${before == null ? '' : '?before=$before'}'), headers: _ua)
        .timeout(const Duration(seconds: 20));
    return r.statusCode == 200 ? r.body : '';
  }

  final first = await page();
  // Private channels, groups and typos redirect to a page with no posts.
  if (!first.contains('tgme_widget_message')) throw Exception('telegram:$channel is not a public channel');
  final p1 = parseTelegramPage(channel, first);
  final p2 = p1.oldestId == null ? null : parseTelegramPage(channel, await page(p1.oldestId).catchError((Object _) => ''));
  final seen = <String>{};
  return [for (final j in [...p1.jobs, ...?p2?.jobs]) if (seen.add(j.applyTarget.toLowerCase())) j];
}

Future<List<JobListing>> fetchBoard(String board, {http.Client? client}) async {
  final [provider, slug] = board.split(':');
  final c = client ?? http.Client();
  if (provider == 'unstop') return _fetchUnstop(c);
  if (provider == 'smartrecruiters') return _fetchSmartRecruiters(c, slug);
  if (provider == 'telegram') return _fetchTelegram(c, slug);
  final url = switch (provider) {
    'greenhouse' => 'https://boards-api.greenhouse.io/v1/boards/$slug/jobs?content=true',
    'lever' => 'https://api.lever.co/v0/postings/$slug?mode=json',
    'ashby' => 'https://api.ashbyhq.com/posting-api/job-board/$slug',
    _ => throw ArgumentError('Unknown board provider: $provider'),
  };
  // Big Lever boards (Paytm: 2.7 MB, ~20 s) need the room, especially on mobile data.
  final res = await c.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) throw Exception('$board → HTTP ${res.statusCode}');
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  final co = _titleCase(slug);

  return switch (provider) {
    'greenhouse' => [
        for (final j in data['jobs'] as List)
          _job(
            'gh-${j['id']}',
            j['company_name'] ?? co,
            j['title'] ?? '',
            j['absolute_url'] ?? '',
            (j['location'] as Map?)?['name'] ?? '',
            htmlToText(j['content'] ?? ''),
            posted: _date(j['first_published'] ?? j['updated_at']),
            department: ((j['departments'] as List?)?.firstOrNull as Map?)?['name'] ?? '',
            deadline: _date(j['application_deadline']),
          ),
      ],
    'lever' => [
        for (final j in data as List)
          _job(
            'lv-${j['id']}',
            co,
            j['text'] ?? '',
            j['hostedUrl'] ?? '',
            (j['categories'] as Map?)?['location'] ?? '',
            [
              j['descriptionPlain'] ?? '',
              for (final l in (j['lists'] as List? ?? const [])) '${l['text']}\n${htmlToText(l['content'] ?? '')}',
              j['additionalPlain'] ?? '',
            ].where((e) => e.isNotEmpty).join('\n\n'),
            posted: _date(j['createdAt']),
            department: (j['categories'] as Map?)?['team'] ?? (j['categories'] as Map?)?['department'] ?? '',
            workplace: j['workplaceType'] ?? '',
          ),
      ],
    _ => [
        for (final j in data['jobs'] as List)
          if (j['isListed'] != false)
            _job(
              'ab-${j['id']}',
              co,
              j['title'] ?? '',
              j['jobUrl'] ?? '',
              j['location'] ?? '',
              j['descriptionPlain'] ?? '',
              posted: _date(j['publishedAt']),
              department: j['department'] ?? '',
              workplace: j['isRemote'] == true ? 'remote' : (j['workplaceType'] ?? ''),
            ),
      ],
  };
}

// ───────────────────────── Local store (Hive, JSON maps — no adapters) ─────────────────────────

late Box _box;

Future<void> initStore() async {
  await Hive.initFlutter();
  _box = await Hive.openBox('proofpitch');
}

Map? _read(String key) => _box.get(key) as Map?;

class ProfileNotifier extends Notifier<StudentProfile> {
  @override
  StudentProfile build() {
    final j = _read('profile');
    return j == null ? const StudentProfile() : StudentProfile.fromJson(j);
  }

  void save(StudentProfile p) {
    state = p;
    _box.put('profile', p.toJson());
  }
}

final profileProvider = NotifierProvider<ProfileNotifier, StudentProfile>(ProfileNotifier.new);

class BoardsNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final stored = _box.get('boards') as List?;
    if (stored == null) return [..._defaultBoards];
    // One-time upgrade for older installs: add Unstop + the India boards (v3: probed India list, SmartRecruiters;
    // v4: the two internship Telegram channels, which were opt-in and left the Telegram filter empty;
    // v5: the other two channels, for volume).
    if (_box.get('boardsV5') != true) {
      final up = {...List<String>.from(stored), ..._defaultBoards}.toList();
      _box.put('boards', up);
      _box.put('boardsV5', true);
      return up;
    }
    return List<String>.from(stored);
  }

  void toggle(String board) {
    state = state.contains(board) ? ([...state]..remove(board)) : [...state, board];
    _box.put('boards', state);
  }
}

final boardsProvider = NotifierProvider<BoardsNotifier, List<String>>(BoardsNotifier.new);

class ManualJobsNotifier extends Notifier<List<JobListing>> {
  @override
  List<JobListing> build() => [for (final j in (_box.get('manualJobs') as List? ?? const [])) JobListing.fromJson(j)];

  void add(JobListing j) {
    state = [j, ...state];
    _box.put('manualJobs', [for (final x in state) x.toJson()]);
  }
}

final manualJobsProvider = NotifierProvider<ManualJobsNotifier, List<JobListing>>(ManualJobsNotifier.new);

class BoardResult {
  const BoardResult(this.jobs, this.failed);
  final List<JobListing> jobs;
  final List<String> failed;
}

/// Fetches every followed board in parallel. One dead board never sinks the whole feed.
final boardJobsProvider = FutureProvider<BoardResult>((ref) async {
  final boards = ref.watch(boardsProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  final failed = <String>[];
  final results = await Future.wait(boards.map((b) => fetchBoard(b, client: client).catchError((Object _) {
        failed.add(b);
        return <JobListing>[];
      })));
  // Older than 3 months or past the deadline: usually filled already, so it never reaches the feed.
  // Telegram channels repost each other: keep one copy of the same company + role.
  final seenTg = <String>{};
  bool firstTg(JobListing j) =>
      !j.id.startsWith('tg-') || seenTg.add('${cleanCompany(j.company)}|${j.title}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9|]'), ''));
  return BoardResult(results.expand((e) => e).where((j) => isFresh(j) && firstTg(j)).toList(), failed);
});

class AppsNotifier extends Notifier<Map<String, Application>> {
  @override
  Map<String, Application> build() => {
        for (final e in (_read('apps') ?? const {}).entries) e.key as String: Application.fromJson(e.value),
      };

  void put(Application a) {
    state = {...state, a.job.id: a};
    _persist();
  }

  void remove(String jobId) {
    state = {...state}..remove(jobId);
    _persist();
  }

  void _persist() => _box.put('apps', {for (final e in state.entries) e.key: e.value.toJson()});
}

final appsProvider = NotifierProvider<AppsNotifier, Map<String, Application>>(AppsNotifier.new);

/// Saved jobs keep a full copy, so they survive the company taking the post down.
class SavedNotifier extends Notifier<Map<String, JobListing>> {
  @override
  Map<String, JobListing> build() => {
        for (final e in (_read('saved') ?? const {}).entries) e.key as String: JobListing.fromJson(e.value),
      };

  bool toggle(JobListing j) {
    final saving = !state.containsKey(j.id);
    state = saving ? {j.id: j, ...state} : ({...state}..remove(j.id));
    _box.put('saved', {for (final e in state.entries) e.key: e.value.toJson()});
    return saving;
  }
}

final savedProvider = NotifierProvider<SavedNotifier, Map<String, JobListing>>(SavedNotifier.new);

class HiddenNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => Set<String>.from(_box.get('hidden') ?? const []);

  void hide(String id) => _set({...state, id});
  void unhide(String id) => _set({...state}..remove(id));
  void _set(Set<String> s) {
    state = s;
    _box.put('hidden', s.toList());
  }
}

final hiddenProvider = NotifierProvider<HiddenNotifier, Set<String>>(HiddenNotifier.new);

/// Jobs first seen after this moment get a NEW dot. Bumped once per app launch.
final lastVisitProvider = Provider<DateTime>((ref) {
  final prev = DateTime.tryParse(_box.get('lastVisit') ?? '') ?? DateTime.now().subtract(const Duration(days: 2));
  _box.put('lastVisit', DateTime.now().toIso8601String());
  return prev;
});

class GoalNotifier extends Notifier<int> {
  @override
  int build() => _box.get('weeklyGoal') ?? 5;
  void set(int v) {
    state = v.clamp(1, 30);
    _box.put('weeklyGoal', state);
  }
}

final weeklyGoalProvider = NotifierProvider<GoalNotifier, int>(GoalNotifier.new);

/// "Need one fast" mode: the feed switches to easiest-to-land first. Persists across launches.
class FastModeNotifier extends Notifier<bool> {
  @override
  bool build() => _box.get('fastMode') ?? false;
  void set(bool v) {
    state = v;
    _box.put('fastMode', v);
  }
}

final fastModeProvider = NotifierProvider<FastModeNotifier, bool>(FastModeNotifier.new);

const dailyFastGoal = 10;

// ───────────────────────── Finding the official site and a real inbox ─────────────────────────

const _ua = {'User-Agent': 'ProofPitch/1.0 (student job app)'};

/// Company name → its website, via Clearbit's free autocomplete. Only trusts a real name match.
Future<String?> lookupDomain(String company, http.Client c) async {
  try {
    final r = await c
        .get(Uri.parse('https://autocomplete.clearbit.com/v1/companies/suggest?query=${Uri.encodeQueryComponent(company)}'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    return domainFromSuggest(company, jsonDecode(utf8.decode(r.bodyBytes)) as List);
  } catch (_) {
    return null;
  }
}

/// Tries likely domains ("zethic.com", "kukbitsl.in"…) and keeps one whose page title names the company.
/// Small Indian startups are rarely in any directory, but most own their-name.com or .in.
/// [extra] (Clearbit's answer) goes last: directories often return a same-named company abroad.
Future<String?> guessDomain(String company, http.Client c, {String? extra}) async {
  final all = {...domainCandidates(company), ?extra}.toList();
  // .com/.in first (most small Indian companies); the long tail only if neither is clearly theirs.
  final first = all.where((d) => d.endsWith('.com') || (d.endsWith('.in') && !d.endsWith('.co.in')) || d == extra).toList();
  String? best;
  var bestScore = 0;
  for (final tier in [first, all.where((d) => !first.contains(d)).toList()]) {
    final scored = await Future.wait([
      for (final d in tier)
        c
            .get(Uri.parse('https://$d'), headers: _ua)
            .timeout(const Duration(seconds: 8))
            .then((r) => r.statusCode == 200 ? siteScore(company, r.body) : 0)
            .catchError((Object _) => 0),
    ]);
    for (var i = 0; i < tier.length; i++) {
      if (scored[i] > bestScore) (best, bestScore) = (tier[i], scored[i]); // ties keep the earlier, likelier candidate
    }
    if (bestScore == 2) break;
  }
  return best;
}

/// The company's own website: from the post, else the best verified guess (Clearbit's answer included). Remembered per company.
Future<String?> resolveDomain(JobListing j, http.Client c) async {
  final fromPost = companyDomain(j);
  if (fromPost != null) return fromPost;
  final name = cleanCompany(j.company);
  final cache = Map<String, dynamic>.from(_box.get('domains') ?? const {});
  if (cache.containsKey(name)) return (cache[name] as String).isEmpty ? null : cache[name];
  final cb = await lookupDomain(name, c);
  // "flexcoders.co.uk" for an Indian listing is someone else.
  final foreign = cb != null && RegExp(r'\.(?!in$|io$|ai$|co$)[a-z]{2}$').hasMatch(cb);
  final d = await guessDomain(name, c, extra: foreign ? null : cb);
  _box.put('domains', {...cache, name: d ?? ''});
  return d;
}

class EmailSearch {
  const EmailSearch(this.domain, this.contacts);
  final String? domain;

  /// Best first: the person who'd hire you, then founders/tech leads, then general inboxes.
  final List<SiteContact> contacts;
  List<String> get emails => [for (final c in contacts) c.email];
}

Map<String, dynamic> _contactJson(SiteContact c) => {'e': c.email, 'r': c.role.name, 'n': c.name, 'g': c.guessed};
SiteContact _contactFrom(Map j) => SiteContact(j['e'], ContactRole.values.byName(j['r']), name: j['n'] ?? '', guessed: j['g'] == true);

/// Companies already checked → what we found (also powers the "Email" filter on HUNT).
Map<String, List<SiteContact>> checkedCompanies() => {
      for (final e in Map<String, dynamic>.from(_box.get('siteContacts') ?? const {}).entries)
        e.key: [for (final c in e.value as List) _contactFrom(c as Map)],
    };

/// Finds the official site, then reads its homepage and contact/careers/about pages for listed emails.
/// A handful of public pages, only when the student opens the Apply page, and it honours robots.txt.
Future<EmailSearch> findCompanyEmails(JobListing j, {http.Client? client}) async {
  final c = client ?? http.Client();
  final name = cleanCompany(j.company);
  try {
    final domain = await resolveDomain(j, c);
    if (domain == null) {
      _remember(name, const []);
      return const EmailSearch(null, []);
    }
    String robots = '';
    try {
      final r = await c.get(Uri.parse('https://$domain/robots.txt')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) robots = r.body;
    } catch (_) {}
    // Team/leadership pages name the founders and HR; contact pages list the inboxes.
    const paths = ['/', '/contact', '/contact-us', '/careers', '/about', '/about-us', '/team', '/our-team', '/jobs'];
    final pages = await Future.wait([
      for (final path in paths)
        if (robotsAllows(robots, path))
          c
              .get(Uri.parse('https://$domain$path'), headers: _ua)
              .timeout(const Duration(seconds: 12))
              .then((r) => r.statusCode == 200 ? r.body : '')
              .catchError((Object _) => ''),
    ]);
    final tech = const {Interest.mobile, Interest.web, Interest.backend, Interest.data, Interest.devops, Interest.game}.any(interestsOf(j).contains);
    final contacts = contactsInHtml(pages.join('\n'), domain: domain, techRole: tech);
    _remember(name, contacts);
    return EmailSearch(domain, contacts);
  } finally {
    if (client == null) c.close();
  }
}

void _remember(String company, List<SiteContact> contacts) =>
    _box.put('siteContacts', {...Map<String, dynamic>.from(_box.get('siteContacts') ?? const {}), company: [for (final c in contacts) _contactJson(c)]});

// ───────────────────────── Website check (cold pitch "holes") ─────────────────────────

class SiteCheck {
  const SiteCheck(this.domain, this.description, this.holes);
  final String domain;
  final String description;
  final List<Hole> holes;
}

/// Looks at a company's homepage the way any visitor would: how long it takes, whether http:// moves to
/// https://, and whether up to 8 of its own links work. Nothing beyond public pages; robots.txt honoured.
Future<SiteCheck> checkSite(String domain, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final sw = Stopwatch()..start();
    final home = await c.get(Uri.parse('https://$domain'), headers: _ua).timeout(const Duration(seconds: 20));
    final loadMs = sw.elapsedMilliseconds;
    final html = home.statusCode == 200 ? home.body : '';

    bool? httpsOk;
    try {
      final req = http.Request('GET', Uri.parse('http://$domain'))
        ..followRedirects = false
        ..headers.addAll(_ua);
      final r = await c.send(req).timeout(const Duration(seconds: 10));
      httpsOk = r.isRedirect || (r.statusCode >= 300 && r.statusCode < 400 && (r.headers['location'] ?? '').startsWith('https'));
      if (r.statusCode == 200) httpsOk = false; // served the page over plain http
    } catch (_) {}

    var robots = '';
    try {
      final r = await c.get(Uri.parse('https://$domain/robots.txt')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) robots = r.body;
    } catch (_) {}
    final paths = <String>{
      for (final m in RegExp('href=["\'](?:https?://(?:www[.])?${RegExp.escape(domain)})?(/[^"\'#?]*)["\']').allMatches(html))
        if (!RegExp(r'\.(css|js|png|jpe?g|svg|webp|gif|ico|pdf|xml|json)$', caseSensitive: false).hasMatch(m.group(1)!) && m.group(1) != '/')
          m.group(1)!,
    }.where((p) => robotsAllows(robots, p)).take(8).toList();
    final statuses = await Future.wait([
      for (final p in paths)
        c.get(Uri.parse('https://$domain$p'), headers: _ua).timeout(const Duration(seconds: 10)).then((r) => r.statusCode).catchError((Object _) => 0),
    ]);
    final broken = [for (var i = 0; i < paths.length; i++) if (statuses[i] >= 400) paths[i]];
    return SiteCheck(domain, siteDescription(html), auditPage(html, loadMs: loadMs, httpsOk: httpsOk, brokenLinks: broken));
  } finally {
    if (client == null) c.close();
  }
}

/// 🔥 Jobs / ❄️ Cold pitch toggle on HUNT. Remembered across launches.
class ColdModeNotifier extends Notifier<bool> {
  @override
  bool build() => _box.get('coldMode') ?? false;
  void set(bool v) {
    state = v;
    _box.put('coldMode', v);
  }
}

final coldModeProvider = NotifierProvider<ColdModeNotifier, bool>(ColdModeNotifier.new);

/// Companies the student added by hand on the cold-pitch screen.
class ColdManualNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => List<String>.from(_box.get('coldManual') ?? const []);
  void add(String company) {
    if (state.contains(company)) return;
    state = [...state, company];
    _box.put('coldManual', state);
  }
}

final coldManualProvider = NotifierProvider<ColdManualNotifier, List<String>>(ColdManualNotifier.new);

/// The company's website if we've looked it up before (Apply page, cold pitch, Email filter). No network.
String? knownDomain(String company) {
  final d = Map<String, dynamic>.from(_box.get('domains') ?? const {})[cleanCompany(company)] as String?;
  return d == null || d.isEmpty ? null : d;
}

// ───────────────────────── Cold targets from the open web ─────────────────────────

const _ycKeys = ['name', 'slug', 'website', 'one_liner', 'tags', 'industries', 'regions', 'all_locations', 'batch', 'status', 'team_size', 'isHiring'];

/// Y Combinator startups in India (or remote and hiring), from the public yc-oss dataset on GitHub Pages.
/// The file is ~10 MB, so it's fetched at most weekly and only the few hundred that matter are kept.
Future<List<ColdTarget>> fetchYcTargets() async {
  final cached = _box.get('ycCompanies') as Map?;
  final fresh = cached != null && DateTime.now().difference(DateTime.parse(cached['at'])).inDays < 7;
  List<Map> companies;
  if (fresh) {
    companies = (cached['list'] as List).cast<Map>();
  } else {
    final r = await http.get(Uri.parse('https://yc-oss.github.io/api/companies/all.json')).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw Exception('yc-oss → HTTP ${r.statusCode}');
    final body = utf8.decode(r.bodyBytes);
    // Decoding 10 MB on the UI thread would freeze the screen.
    companies = await Isolate.run(() => [
          for (final c in jsonDecode(body) as List)
            if ('${c['regions']} ${c['all_locations']}'.contains('India') || '${c['regions']}'.contains('Fully Remote'))
              {for (final k in _ycKeys) k: c[k]},
        ]);
    _box.put('ycCompanies', {'at': DateTime.now().toIso8601String(), 'list': companies});
  }
  return ycTargets(companies);
}

final ycTargetsProvider = FutureProvider<List<ColdTarget>>((ref) => fetchYcTargets());

/// Companies in India on GitHub whose name says they work in [field] (game studios, app shops…).
/// One search per term; GitHub allows 10 a minute without a login, so results are kept for a day.
Future<List<ColdTarget>> searchGithubOrgs(Interest field) async {
  final cache = Map<String, dynamic>.from(_box.get('ghOrgs') ?? const {});
  final hit = cache[field.name] as Map?;
  if (hit != null && DateTime.now().difference(DateTime.parse(hit['at'])).inHours < 24) {
    return githubTargets(field, (hit['items'] as List).cast<Map>());
  }
  final items = <Map>[];
  for (final term in githubTerms[field] ?? const <String>[]) {
    final q = Uri.encodeQueryComponent('$term type:org location:india repos:>2');
    final r = await http
        .get(Uri.parse('https://api.github.com/search/users?q=$q&per_page=40&sort=repositories'), headers: _ua)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) break; // rate-limited: show what we have
    items.addAll([for (final o in jsonDecode(r.body)['items'] as List) {'login': o['login']}]);
  }
  if (items.isNotEmpty) _box.put('ghOrgs', {...cache, field.name: {'at': DateTime.now().toIso8601String(), 'items': items}});
  return githubTargets(field, items);
}

final githubTargetsProvider = FutureProvider.family<List<ColdTarget>, Interest>((ref, field) => searchGithubOrgs(field));

/// A GitHub org's own profile: name, website, public email. Null for clubs or when GitHub says no.
Future<({String name, String website, String email, String about})?> fetchGithubOrg(String login) async {
  final r = await http.get(Uri.parse('https://api.github.com/orgs/$login'), headers: _ua).timeout(const Duration(seconds: 15));
  return r.statusCode == 200 ? githubOrgInfo(jsonDecode(r.body) as Map) : null;
}
