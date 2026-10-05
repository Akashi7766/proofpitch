import 'engines.dart';
import 'insights.dart' show matchScore;
import 'models.dart';

// ───────────────────────── Interests ─────────────────────────
// What the student wants to work on. Drives the Unstop searches, the default feed and the filter chips.

// Every pattern is anchored on word boundaries: "unity" must not match "comm-unity", "ai" not "maintain".
// Stems that should match longer words ("develop" → developer/development) are listed as stems on purpose.
enum Interest {
  mobile('📱', 'Mobile apps', r'\b(android|ios|mobile|flutter|react native|kotlin|swift|app develop\w*)\b', ['flutter', 'android', 'react native']),
  web('🌐', 'Web / Frontend', r'\b(front[- ]?end|web develop\w*|web design\w*|react(js)?|angular|vue(js)?|next\.?js|wordpress|ui developer|html)\b', ['frontend', 'react', 'web development']),
  backend('🧱', 'Backend / Full stack', r'\b(back[- ]?end|full[- ]?stack|api|node(\.?js)?|django|spring|java develop\w*|python develop\w*|php|software (engineer\w*|develop\w*)|sde|swe)\b', ['backend', 'full stack', 'node.js']),
  data('🧪', 'Data & AI', r'\b(data|machine learning|ml|ai|artificial intelligence|analytics|data analyst|data scien\w*|nlp|computer vision|llms?|deep learning|generative ai|gen ai)\b', ['data science', 'machine learning', 'data analyst']),
  design('🎨', 'UI/UX & design', r'(?<!vlsi |chip |circuit |pcb )\b(design|designer|designing|ux|ui|ui/ux|graphic\w*|figma|visual|motion graphics|video edit\w*|illustrat\w*)\b', ['ui ux', 'graphic design']),
  product('🧭', 'Product & business analysis', r'\b(product manag\w*|product intern\w*|product analyst|program manag\w*|business analy\w*|strategy|founder.?s office|project manag\w*)\b', ['product management', 'business analyst']),
  devops('☁️', 'Cloud & DevOps', r'\b(devops|cloud|sre|infrastructure|platform engineer\w*|aws|azure|gcp|kubernetes|network\w* engineer\w*)\b', ['devops', 'cloud computing']),
  security('🔐', 'Cybersecurity', r'\b(cyber\s?security|cyber|security analyst|security engineer\w*|information security|pentest\w*|penetration test\w*|soc analyst|ethical hack\w*)\b', ['cyber security']),
  qa('🔍', 'Testing / QA', r'\b(qa|tester|testing|quality assurance|test engineer\w*|automation test\w*)\b', ['software testing']),
  game('🎮', 'Game dev & XR', r'\b(game|games|gaming|game develop\w*|unity|unity3d|unreal|godot|ar|vr|xr|ar/vr|3d|metaverse)\b', ['game development', 'unity']),
  marketing('📣', 'Marketing & content', r'\b(marketing|content|social media|seo|copywrit\w*|brand\w*|growth|community|ambassador|event\w*|influencer\w*|public relations|pr)\b', ['digital marketing', 'content writing']),
  business('💼', 'Sales, ops & HR', r'\b(sales|business develop\w*|operations|hr|human resources?|recruit\w*|talent acquisition|customer success|customer support|telecall\w*|lead generation|finance|accounting|accounts)\b', ['business development', 'human resources']);

  const Interest(this.emoji, this.label, this.pattern, this.searchTerms);
  final String emoji;
  final String label;
  final String pattern;

  /// What to ask Unstop for when the student picks this.
  final List<String> searchTerms;

  RegExp get re => RegExp(pattern, caseSensitive: false);
}

Interest? interestByName(String name) => Interest.values.where((i) => i.name == name).firstOrNull;

/// Fields a job belongs to, from its title (and team name, which boards often fill in).
/// The title decides; the board's category list is only a fallback because it's noisy
/// (Unstop tags a "Brand Ambassador" role with "AI Engineering").
Set<Interest> interestsOf(JobListing j) {
  Set<Interest> match(String t) => {for (final i in Interest.values) if (i.re.hasMatch(t)) i};
  final byTitle = match(j.title);
  return byTitle.isNotEmpty ? byTitle : match(j.department);
}

/// Search terms for the student's interests first (what they asked for), then their skills.
List<String> searchTermsFor(StudentProfile p) => {
      for (final n in p.interests) ...?interestByName(n)?.searchTerms.take(2),
      ...p.projects.expand((x) => x.tags),
      ...p.skills,
    }.take(8).toList();

// ───────────────────────── Freshness ─────────────────────────

const maxAgeDays = 90;

/// Board jobs older than 3 months (or already closed) are noise: the role is usually filled.
bool isFresh(JobListing j, [DateTime? now]) {
  final n = now ?? DateTime.now();
  if (j.deadline != null && j.deadline!.isBefore(n)) return false;
  if (j.postedAt == null) return j.id.startsWith('manual'); // can't tell how old → don't show
  return n.difference(j.postedAt!).inDays <= maxAgeDays;
}

// ───────────────────────── Stipend ─────────────────────────

/// "₹12k–15k/month" → 12000. Monthly rupees only; null when unpaid, foreign or not listed.
int? monthlyInr(String stipend) {
  final s = stipend.toLowerCase().replaceAll(',', '');
  if (!RegExp(r'₹|rs\.?|inr').hasMatch(s)) return null;
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*(k|l|lakh)?').firstMatch(s.replaceAll(RegExp(r'₹|rs\.?|inr'), ''));
  if (m == null) return null;
  var v = double.parse(m.group(1)!);
  if (m.group(2) == 'k') v *= 1000;
  if (m.group(2) == 'l' || m.group(2) == 'lakh') v *= 100000;
  if (s.contains('/week')) v *= 4;
  if (s.contains('/hour')) v *= 160;
  if (s.contains('/year') || s.contains('lpa') || s.contains('per annum')) v /= 12;
  return v.round();
}

// ───────────────────────── "Need one fast" ─────────────────────────

const _bigNames = [
  'google', 'microsoft', 'amazon', 'meta', 'apple', 'netflix', 'databricks', 'stripe', 'uber', 'airbnb', 'openai',
  'anthropic', 'flipkart', 'razorpay', 'cred', 'groww', 'zomato', 'swiggy', 'adobe', 'nvidia', 'figma',
];

/// How likely a quick application turns into an offer. Not a promise — a ranking of easier doors:
/// small teams, few applicants, fresh posts, remote, and roles nobody else is fighting over.
int easeScore(StudentProfile s, JobListing j, [DateTime? now]) {
  final n = now ?? DateTime.now();
  var score = 0;
  if (j.id.startsWith('us-')) score += 2; // Unstop: one-tap apply, mostly smaller companies
  if (detectChannel(j.applyTarget) == Channel.directEmail) score += 2;
  final a = j.applicants;
  if (a != null) score += a < 100 ? 3 : a < 500 ? 2 : a < 2000 ? 1 : -1;
  final wp = workplaceOf(j);
  if (wp == 'remote') score += 2;
  if (nearness(s, j) >= 2) score += 1;
  if (j.stipend.isEmpty || j.stipend == 'Unpaid') score += 1; // fewer people chase these
  if (j.postedAt != null) {
    final age = n.difference(j.postedAt!).inDays;
    score += age <= 7 ? 2 : age <= 14 ? 1 : 0;
  }
  if ((matchScore(s.allSkills, j) ?? 0) >= 40) score += 1;
  final co = j.company.toLowerCase();
  if (_bigNames.any(co.contains)) score -= 3;
  return score;
}

// ───────────────────────── Filters ─────────────────────────

enum SortBy {
  best('Best for me'),
  newest('Newest'),
  stipend('Highest stipend'),
  closing('Closing soon'),
  fewest('Fewest applicants'),
  easiest('Easiest to land');

  const SortBy(this.label);
  final String label;
}

enum WorkMode { any, remote, hybrid, onSite }

enum Source { all, unstop, companies, telegram }

/// How you'd apply. [email] = an inbox in the post or on their site; [careersPage] = the company's own job board.
enum ApplyVia { any, email, careersPage }

final _postEmailRe = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[a-z]{2,}', caseSensitive: false);

/// The post itself names an inbox (not a privacy/accommodations one).
bool postHasEmail(JobListing j) =>
    detectChannel(j.applyTarget) == Channel.directEmail ||
    _postEmailRe.allMatches(j.description).any((m) => !RegExp('privacy|accommodat|noreply|no-reply|legal|eeo|gdpr').hasMatch(m.group(0)!.toLowerCase()));

/// Unstop is a marketplace; Greenhouse/Lever/Ashby/SmartRecruiters boards are the company's own careers page.
bool onCareersPage(JobListing j) => const ['gh-', 'lv-', 'ab-', 'sr-'].any(j.id.startsWith);

/// Where a job came from, for the tag on every card: "✈️ Telegram @goyalarsh", "🟣 Unstop", "🏢 Careers page · Lever".
String sourceLabel(JobListing j) {
  if (j.source.startsWith('Telegram')) return '✈️ ${j.source.replaceFirst(' · ', ' ')}';
  if (j.id.startsWith('tg-')) return '✈️ Telegram @${j.id.split('-')[1]}'; // channel names can't contain "-"
  if (j.source == 'Cold pitch') return '❄️ Cold pitch';
  if (j.source.isNotEmpty) return j.source == 'Shared post' ? '🔗 Shared post' : '✍️ ${j.source}';
  for (final (prefix, name) in const [('gh-', 'Greenhouse'), ('lv-', 'Lever'), ('ab-', 'Ashby'), ('sr-', 'SmartRecruiters')]) {
    if (j.id.startsWith(prefix)) return '🏢 Careers page · $name';
  }
  if (j.id.startsWith('us-')) return '🟣 Unstop';
  return '✍️ Added by you';
}

class FeedFilter {
  const FeedFilter({
    this.myInterests = true,
    this.eligibleOnly = true,
    this.near = false,
    this.internsOnly = true,
    this.maxAge = maxAgeDays,
    this.mode = WorkMode.any,
    this.minStipend = 0,
    this.paidOnly = false,
    this.fields = const {},
    this.source = Source.all,
    this.sort = SortBy.best,
    this.skills = const {},
    this.applyVia = ApplyVia.any,
  });

  final bool myInterests;
  final bool eligibleOnly;
  final bool near;
  final bool internsOnly;
  final int maxAge; // days
  final WorkMode mode;
  final int minStipend; // ₹/month, 0 = any
  final bool paidOnly;
  final Set<Interest> fields; // explicit picks override "my interests"
  final Source source;
  final SortBy sort;
  final Set<String> skills;
  final ApplyVia applyVia;

  /// What "Need one fast" means: anything you qualify for, newest month, easiest doors first.
  static const fast = FeedFilter(myInterests: false, maxAge: 30, sort: SortBy.easiest);

  /// Count of the sheet's advanced settings that differ from the defaults (the badge on the Filters button).
  int get advancedCount => [
        maxAge != maxAgeDays,
        mode != WorkMode.any,
        minStipend > 0,
        fields.isNotEmpty,
        source != Source.all,
        sort != SortBy.best,
        !internsOnly,
        applyVia != ApplyVia.any,
      ].where((x) => x).length;

  FeedFilter copyWith({
    bool? myInterests,
    bool? eligibleOnly,
    bool? near,
    bool? internsOnly,
    int? maxAge,
    WorkMode? mode,
    int? minStipend,
    bool? paidOnly,
    Set<Interest>? fields,
    Source? source,
    SortBy? sort,
    Set<String>? skills,
    ApplyVia? applyVia,
  }) =>
      FeedFilter(
        myInterests: myInterests ?? this.myInterests,
        eligibleOnly: eligibleOnly ?? this.eligibleOnly,
        near: near ?? this.near,
        internsOnly: internsOnly ?? this.internsOnly,
        maxAge: maxAge ?? this.maxAge,
        mode: mode ?? this.mode,
        minStipend: minStipend ?? this.minStipend,
        paidOnly: paidOnly ?? this.paidOnly,
        fields: fields ?? this.fields,
        source: source ?? this.source,
        sort: sort ?? this.sort,
        skills: skills ?? this.skills,
        applyVia: applyVia ?? this.applyVia,
      );
}

final _internRe = RegExp(r'\b(intern|interns|internship|co-?op|trainee|apprentice)\b', caseSensitive: false);
bool isInternship(JobListing j) => _internRe.hasMatch(j.title) || j.id.startsWith('us-');

typedef Ranked = ({JobListing job, int? score, int near, bool ok, int ease});

/// Applies [f] and sorts. Pure, so the feed's behaviour is testable without widgets.
/// [emailCompanies]: companies whose website lists a real inbox (checked earlier, see `checkedCompanies`).
List<Ranked> rankFeed(List<JobListing> jobs, StudentProfile s, FeedFilter f,
    {String query = '', DateTime? now, Set<String> emailCompanies = const {}}) {
  final n = now ?? DateTime.now();
  final q = query.toLowerCase();
  final mine = s.allSkills;
  final wanted = f.fields.isNotEmpty
      ? f.fields
      : f.myInterests
          ? {for (final x in s.interests) ?interestByName(x)}
          : <Interest>{};
  final out = <Ranked>[];
  for (final j in jobs) {
    final manual = j.id.startsWith('manual');
    if (f.internsOnly && !manual && !isInternship(j)) continue;
    if (!manual && j.postedAt != null && n.difference(j.postedAt!).inDays > f.maxAge) continue;
    if (q.isNotEmpty && !'${j.company} ${j.title} ${j.location} ${j.rules.skills.join(' ')}'.toLowerCase().contains(q)) continue;
    if (f.source == Source.unstop && !j.id.startsWith('us-')) continue;
    if (f.source == Source.companies && !onCareersPage(j)) continue;
    if (f.source == Source.telegram && !j.id.startsWith('tg-')) continue;
    final wp = workplaceOf(j);
    if (f.mode == WorkMode.remote && wp != 'remote') continue;
    if (f.mode == WorkMode.hybrid && wp != 'hybrid') continue;
    if (f.mode == WorkMode.onSite && wp != 'on-site') continue;
    if (f.paidOnly && (j.stipend.isEmpty || j.stipend == 'Unpaid')) continue;
    if (f.minStipend > 0 && (monthlyInr(j.stipend) ?? 0) < f.minStipend) continue;
    final near = nearness(s, j);
    if (f.near && near < 2) continue;
    if (wanted.isNotEmpty && !manual && !interestsOf(j).any(wanted.contains)) continue;
    if (!f.skills.every(j.rules.skills.contains)) continue;
    if (f.applyVia == ApplyVia.careersPage && !onCareersPage(j)) continue;
    if (f.applyVia == ApplyVia.email && !postHasEmail(j) && !emailCompanies.contains(cleanCompany(j.company))) continue;
    final ok = isEligible(s, j);
    if (f.eligibleOnly && !ok) continue;
    out.add((job: j, score: matchScore(mine, j), near: near, ok: ok, ease: easeScore(s, j, n)));
  }

  int newest(Ranked a, Ranked b) => (b.job.postedAt ?? DateTime(2000)).compareTo(a.job.postedAt ?? DateTime(2000));
  out.sort((a, b) {
    if (a.ok != b.ok) return a.ok ? -1 : 1;
    final c = switch (f.sort) {
      SortBy.best => b.near != a.near ? b.near.compareTo(a.near) : (b.score ?? -1).compareTo(a.score ?? -1),
      SortBy.newest => 0,
      SortBy.stipend => (monthlyInr(b.job.stipend) ?? -1).compareTo(monthlyInr(a.job.stipend) ?? -1),
      SortBy.closing => (a.job.deadline ?? DateTime(9999)).compareTo(b.job.deadline ?? DateTime(9999)),
      SortBy.fewest => (a.job.applicants ?? 1 << 30).compareTo(b.job.applicants ?? 1 << 30),
      SortBy.easiest => b.ease.compareTo(a.ease),
    };
    return c != 0 ? c : newest(a, b);
  });
  return out;
}

/// "2.8k applied" — competition at a glance.
String applicantsLabel(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k applied' : '$n applied';
