import 'models.dart';

// ───────────────────────── Channel & ATS detection ─────────────────────────

const _modernAts = ['greenhouse.io', 'lever.co', 'ashbyhq.com', 'smartrecruiters.com'];
const _enterpriseAts = ['myworkdayjobs.com', 'taleo.net', 'icims.com', 'successfactors.com'];
final _emailRe = RegExp(r'^[^\s@/]+@[^\s@/]+\.[a-z]{2,}$', caseSensitive: false);

Channel detectChannel(String target) {
  final t = target.trim().toLowerCase();
  if (t.startsWith('mailto:') || _emailRe.hasMatch(t)) return Channel.directEmail;
  final host = Uri.tryParse(t.contains('://') ? t : 'https://$t')?.host ?? '';
  bool on(List<String> domains) => domains.any((d) => host == d || host.endsWith('.$d'));
  if (on(_modernAts)) return Channel.modernAts;
  if (on(_enterpriseAts)) return Channel.enterpriseAts;
  return Channel.customPortal;
}

/// What a student needs to know about where they're applying, in plain words.
String channelLabel(JobListing j) {
  final ch = detectChannel(j.applyTarget);
  if (ch != Channel.customPortal) return ch.label;
  final host = (Uri.tryParse(j.applyTarget)?.host ?? '').replaceFirst('www.', '');
  return host.isEmpty ? ch.label : 'Apply on $host';
}

String emailOf(String target) => target.trim().replaceFirst(RegExp('^mailto:', caseSensitive: false), '');

// ───────────────────────── Skill vocabulary ─────────────────────────
// One canonical name per skill, used by the resume reader, job parser, matcher and pre-flight alike,
// so "Unity Engine" on a resume and "Unity" in a job post are the same thing everywhere.

const skillKeywords = [
  'flutter', 'dart', 'kotlin', 'swift', 'swiftui', 'jetpack compose', 'android', 'ios', 'react native', 'react',
  'next.js', 'vue', 'angular', 'svelte', 'typescript', 'javascript', 'node.js', 'express', 'nestjs', 'python',
  'django', 'fastapi', 'flask', 'golang', 'rust', 'java', 'spring', 'c++', 'c#', '.net', 'php', 'laravel', 'ruby',
  'rails', 'scala', 'sql', 'mysql', 'postgres', 'mongodb', 'redis', 'firebase', 'supabase', 'aws', 'gcp', 'azure',
  'docker', 'kubernetes', 'terraform', 'ci/cd', 'graphql', 'rest api', 'json', 'xml', 'machine learning',
  'deep learning', 'nlp', 'computer vision', 'llm', 'pytorch', 'tensorflow', 'scikit-learn', 'pandas', 'numpy',
  'spark', 'tableau', 'power bi', 'excel', 'figma', 'ui/ux', 'tailwind', 'html', 'css', 'git', 'linux',
  'data structures', 'oop', 'unity', 'unreal engine', 'godot', 'blender', 'game development', 'ar/vr', 'jsp',
  'servlets', 'jdbc', 'selenium', 'solidity', 'blockchain', 'embedded', 'arduino', 'matlab',
];

const _alias = {
  'unity engine': 'unity', 'unity3d': 'unity', 'unity 3d': 'unity', 'c sharp': 'c#', 'csharp': 'c#',
  'reactjs': 'react', 'react.js': 'react', 'react js': 'react', 'nodejs': 'node.js', 'node js': 'node.js',
  'nextjs': 'next.js', 'vue.js': 'vue', 'vuejs': 'vue', 'angularjs': 'angular', 'js': 'javascript', 'ts': 'typescript',
  'go': 'golang', 'postgresql': 'postgres', 'mongo': 'mongodb', 'k8s': 'kubernetes', 'ml': 'machine learning',
  'dl': 'deep learning', 'ai/ml': 'machine learning', 'google cloud': 'gcp', 'amazon web services': 'aws',
  'rest apis': 'rest api', 'restful apis': 'rest api', 'restful api': 'rest api', 'rest': 'rest api',
  'object-oriented programming': 'oop', 'object oriented programming': 'oop',
  'data structures & algorithms': 'data structures', 'data structures and algorithms': 'data structures',
  'dsa': 'data structures', 'algorithms': 'data structures', 'java servlets': 'servlets', 'github': 'git',
  'ui/ux design': 'ui/ux', 'ux': 'ui/ux', 'ui design': 'ui/ux', 'ux design': 'ui/ux', 'sklearn': 'scikit-learn',
  'tailwindcss': 'tailwind', 'tailwind css': 'tailwind', 'unreal': 'unreal engine', 'jetpack': 'jetpack compose',
  'dotnet': '.net', 'asp.net': '.net', 'springboot': 'spring', 'spring boot': 'spring', 'ms excel': 'excel',
  'microsoft excel': 'excel', 'powerbi': 'power bi', 'html5': 'html', 'css3': 'css', 'game dev': 'game development',
  'java script': 'javascript', 'api development': 'rest api', 'api integration': 'rest api', 'user interface design': 'ui/ux',
  'object oriented programming concepts': 'oop', 'oops': 'oop', 'version control': 'git', 'mysql database': 'mysql',
};

String canonSkill(String raw) {
  var s = raw.toLowerCase().replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_alias.containsKey(s)) return _alias[s]!;
  // "Flutter Framework", "Git Version Control", "Python Programming" → the skill itself.
  final bare = s.replaceFirst(RegExp(r' (framework|version control|programming|language|engine|library|sdk)$'), '');
  if (bare != s && (skillKeywords.contains(bare) || _alias.containsKey(bare))) return _alias[bare] ?? bare;
  return s;
}

/// "HTML/CSS" → [html, css]; "Unity Engine" → [unity]; drops sentence-like junk.
List<String> splitSkills(String raw) {
  final out = <String>[];
  for (var part in raw.split(RegExp(r'[,;|•●▪]|\sand\s'))) {
    part = part.trim();
    if (part.isEmpty) continue;
    final lower = part.toLowerCase();
    final isPair = RegExp(r'^[\w.+#]{1,12}/[\w.+#]{1,12}$').hasMatch(part) &&
        !_alias.containsKey(lower) &&
        !skillKeywords.contains(lower);
    for (final p in isPair ? part.split('/') : [part]) {
      final c = canonSkill(p);
      if (c.isNotEmpty && c.length <= 30 && c.split(' ').length <= 4 && !c.contains(':')) out.add(c);
    }
  }
  return out;
}

bool _hasWord(String text, String kw) =>
    RegExp('(?<![a-z0-9+#.])${RegExp.escape(kw)}(?![a-z0-9+#])').hasMatch(text);

/// Known skills mentioned anywhere in free text, canonicalised.
List<String> scanSkills(String text) {
  // Tool names and link labels aren't skills: "Android Studio" ≠ android dev, "[View GitHub Repository]" ≠ git.
  final t = text
      .toLowerCase()
      .replaceAll('java script', 'javascript') // "Java Script" is not Java
      .replaceAll(RegExp(r'android studio|\[[^\]]*\]|https?://\S+'), ' ');
  final found = <String>{
    for (final k in skillKeywords)
      if (_hasWord(t, k)) k,
    // Aliases that are safe in prose (skip tiny ones like "go", "js", "rest", "ml" — too many false hits).
    for (final e in _alias.entries)
      if (e.key.length > 3 && _hasWord(t, e.key)) e.value,
  };
  return [for (final k in skillKeywords) if (found.contains(k)) k];
}

/// Only real technical skills count toward match % and the hard gate. Posts also list things like
/// "cross-functional collaboration" — a student can't prove those with a tag, so they never block.
List<String> techSkills(List<String> skills) => [for (final s in skills) if (skillKeywords.contains(s)) s];

const _tools = {
  'vs code', 'visual studio code', 'android studio', 'intellij', 'eclipse', 'postman', 'jira', 'agile', 'agile workflows',
  'scrum', 'ms office', 'microsoft office', 'windows', 'macos', 'canva', 'notion', 'slack', 'trello', 'xcode',
};
bool isToolNotSkill(String s) => _tools.contains(s);

/// "Resolute AI Software Private Limited" → "Resolute AI Software". Nobody greets a legal entity.
String cleanCompany(String name) => name
    .replaceAll(RegExp(r'[\s,]+(private limited|pvt\.? ?ltd\.?|limited|ltd\.?|llp|inc\.?|llc|corp\.?|gmbh|opc)\s*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'[\s,]+(private|pvt\.?)\s*$', caseSensitive: false), '')
    .trim();

/// Drops tracking junk (?pcampaignid=, utm_*, ref…) so links in a pitch look intentional.
String cleanUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasQuery) return url;
  final keep = {
    for (final e in u.queryParameters.entries)
      if (!RegExp(r'^(utm_|pcampaignid|ref|si|fbclid|gclid|igshid|source)').hasMatch(e.key)) e.key: e.value,
  };
  // replace(queryParameters: null) would keep the old query, so rebuild it explicitly.
  return u.replace(query: keep.isEmpty ? '' : Uri(queryParameters: keep).query).toString().replaceAll(RegExp(r'\?$'), '');
}

// ───────────────────────── Rules parser ─────────────────────────

/// "Experience: 2+ years", "3-5 yrs", "minimum 2 years of experience" → the lower bound. "0-1 years"/"freshers" → 0.
int minYearsIn(String text) {
  final t = text.toLowerCase();
  for (final re in [
    RegExp(r'experience\s*(?:required)?\s*[:\-–]+\s*(\d{1,2})\s*\+?\s*(?:[-–to]+\s*\d{1,2}\s*)?(?:years?|yrs?)'),
    RegExp(r'(?:minimum|min\.?|at least)\s*(\d{1,2})\s*\+?\s*(?:years?|yrs?)'),
    RegExp(r'(\d{1,2})\s*\+?\s*(?:[-–to]+\s*\d{1,2}\s*)?(?:years?|yrs?)\s*(?:of\s*)?(?:relevant\s*|work\s*|professional\s*|industry\s*)?experience'),
    RegExp(r'(\d{1,2})\s*\+\s*(?:years?|yrs?)\b'), // "Engineer in Bangalore | 1+ Year"
  ]) {
    final m = re.firstMatch(t);
    if (m != null) return int.parse(m.group(1)!);
  }
  return 0;
}

// ponytail: naive regex over free text; misses odd phrasings. The job screen lets the user fix rules by hand.
ParsedRules parseRules(String description, {String company = ''}) {
  final text = description.toLowerCase();

  double? minCgpa;
  for (final re in [
    RegExp(r'(\d{1,2}(?:\.\d{1,2})?)\s*\+?\s*(?:/\s*10\s*)?(?:c?gpa|cpi)'),
    RegExp(r'(?:c?gpa|cpi)[^0-9\n]{0,30}(\d{1,2}(?:\.\d{1,2})?)'),
  ]) {
    final v = double.tryParse(re.firstMatch(text)?.group(1) ?? '');
    if (v != null && v > 0 && v <= 10) {
      minCgpa = v;
      break;
    }
  }

  final batches = <int>{};
  for (final sentence in text.split(RegExp(r'[.\n;]'))) {
    if (!RegExp(r'batch|graduat|class of|passing out|pass-out|degree in').hasMatch(sentence)) continue;
    for (final r in RegExp(r'\b(20[2-4]\d)\s*[-–to]+\s*(20[2-4]\d)\b').allMatches(sentence)) {
      final a = int.parse(r.group(1)!), b = int.parse(r.group(2)!);
      for (var y = a; y <= b && b - a < 6; y++) {
        batches.add(y);
      }
    }
    for (final y in RegExp(r'\b(20[2-4]\d)\b').allMatches(sentence)) {
      batches.add(int.parse(y.group(1)!));
    }
  }

  // Titles like "Data Science Intern (2027)" name the batch directly.
  for (final m in RegExp(r'\((20[2-4]\d)\)').allMatches(text.split('\n').first)) {
    batches.add(int.parse(m.group(1)!));
  }

  // "Figma is hiring…" must not make every Figma job require the figma skill.
  final skillText = company.isEmpty ? text : text.replaceAll(company.toLowerCase(), ' ');

  return ParsedRules(minCgpa: minCgpa, allowedBatches: batches.toList()..sort(), skills: scanSkills(skillText), minYears: minYearsIn(text));
}

// ───────────────────────── Location ─────────────────────────

const _places = {
  'India': ['india', 'bengaluru', 'bangalore', 'mumbai', 'thane', 'pune', 'hyderabad', 'chennai', 'delhi', 'gurgaon',
    'gurugram', 'noida', 'kolkata', 'ahmedabad', 'jaipur', 'kochi', 'indore', 'chandigarh', 'coimbatore', 'salem',
    'madurai', 'lucknow', 'bhopal', 'nagpur', 'surat', 'vadodara', 'mysore', 'mysuru', 'trivandrum', 'bhubaneswar'],
  'United States': ['united states', 'usa', 'u.s.', ', ca', ', ny', ', wa', ', tx', ', ma', ', il', ', co', ', ga',
    ', va', ', or', ', nj', ', pa', ', fl', ', nc', ', ut', ', az', 'san francisco', 'new york', 'seattle', 'austin',
    'boston', 'chicago', 'los angeles', 'mountain view', 'menlo park', 'palo alto', 'sunnyvale', 'san jose', 'denver',
    'atlanta', 'washington, dc', '(us)', '- us', 'remote us', 'us remote', 'us-remote', 'remote, us'],
  'United Kingdom': ['united kingdom', 'london', ', uk', '(uk)', '- uk', 'manchester', 'edinburgh'],
  'Canada': ['canada', 'toronto', 'vancouver', 'montreal', 'waterloo'],
  'Singapore': ['singapore'],
  'Germany': ['germany', 'berlin', 'munich'],
  'Ireland': ['ireland', 'dublin'],
  'Netherlands': ['netherlands', 'amsterdam'],
  'France': ['france', 'paris'],
  'Spain': ['spain', 'madrid', 'barcelona'],
  'Poland': ['poland', 'warsaw'],
  'Serbia': ['serbia', 'belgrade'],
  'Australia': ['australia', 'sydney', 'melbourne'],
  'Japan': ['japan', 'tokyo'],
  'UAE': ['uae', 'dubai', 'abu dhabi'],
  'Brazil': ['brazil', 'são paulo', 'sao paulo'],
};

const _cityAlias = {'bangalore': 'bengaluru', 'gurgaon': 'gurugram', 'mysore': 'mysuru', 'bombay': 'mumbai', 'new delhi': 'delhi'};
String _city(String c) => _cityAlias[c.toLowerCase().trim()] ?? c.toLowerCase().trim();

Set<String> countriesOf(String location) {
  final l = ' ${location.toLowerCase()} ';
  bool hit(String p) => RegExp(r'^[a-z.]+$').hasMatch(p) ? _hasWord(l, p) : l.contains(p);
  return {for (final e in _places.entries) if (e.value.any(hit)) e.key};
}

/// remote / hybrid / on-site, or '' when nothing says.
String workplaceOf(JobListing j) {
  final w = j.workplace.toLowerCase();
  if (w.contains('remote') || w == 'wfh') return 'remote';
  if (w.contains('hybrid')) return 'hybrid';
  if (w.contains('site') || w.contains('office')) return 'on-site';
  final l = j.location.toLowerCase();
  if (l.contains('remote') || l.contains('work from home')) return 'remote';
  if (l.contains('hybrid')) return 'hybrid';
  if (l.isNotEmpty) return 'on-site';
  // No location given (pasted leads): read the post itself.
  final d = j.description.toLowerCase();
  if (RegExp(r'\bhybrid\b').hasMatch(d)) return 'hybrid';
  if (RegExp(r'in[- ]office|on[- ]?site|work from office|\bwfo\b').hasMatch(d)) return 'on-site';
  if (RegExp(r'fully remote|\bremote\b|work from home|\bwfh\b').hasMatch(d)) return 'remote';
  return '';
}

/// 3 = your city (or remote within your country), 2 = your country, 1 = remote anywhere, 0 = far away/unknown.
int nearness(StudentProfile s, JobListing j) {
  final wp = workplaceOf(j);
  final cs = countriesOf(j.location);
  final parts = j.location.toLowerCase().split(RegExp(r'[,/|·;•]'));
  if (s.city.isNotEmpty && parts.any((p) => _city(p) == _city(s.city))) return 3;
  if (s.country.isNotEmpty && cs.contains(s.country)) return wp == 'remote' ? 3 : 2;
  if (wp == 'remote' && cs.isEmpty) return 1;
  return 0;
}

final _authRe = RegExp(
  r"authori[sz]ed to work in (the )?(united states|us|u\.s\.|uk|united kingdom|canada|eu)|(not|unable to|cannot|can't|won't|will not|do not|don't) (currently )?(provide |offer )?(visa )?sponsor|no (visa )?sponsorship|must (be|reside) (located |based )?in (the )?(us|united states|uk|canada)",
  caseSensitive: false,
);

// ───────────────────────── Eligibility & pre-flight ─────────────────────────

class Check {
  const Check(this.label, this.ok, {this.hard = false, this.detail = ''});
  final String label;
  final bool ok;
  final bool hard;
  final String detail;
}

/// Unstop-style applicant groups a student belongs to, derived from their degree.
Set<String> studentGroups(StudentProfile s) {
  final d = s.degree.toLowerCase().replaceAll('.', '').replaceAll(' ', '');
  if (d.isEmpty) return {};
  final g = <String>{RegExp(r'^m|master|mca|mba').hasMatch(d) ? 'postgraduate' : 'undergraduate'};
  if (RegExp(r'btech|^be$|mtech|engineer').hasMatch(d)) g.add('engineering');
  if (RegExp(r'bsc|bca|bcom|^ba$|msc|science|arts|commerce|mca').hasMatch(d)) g.add('sciences');
  if (RegExp(r'bba|mba|bms|management').hasMatch(d)) g.add('management');
  // Final-year students count as freshers in Indian hiring (Unstop's "Fresher" is ticked on 350+ internships).
  if (s.graduationYear != null && s.graduationYear! <= DateTime.now().year + 1) g.add('fresher');
  return g;
}

String _groupKey(String name) {
  final n = name.toLowerCase();
  if (n.contains('engineer')) return 'engineering';
  if (n.contains('postgrad')) return 'postgraduate';
  if (n.contains('undergrad')) return 'undergraduate';
  if (n.contains('management') || n.contains('mba')) return 'management';
  if (n.contains('fresher')) return 'fresher';
  if (n.contains('science') || n.contains('arts') || n.contains('commerce')) return 'sciences';
  return n;
}

/// The hard gates. A failed hard check means you can't apply — the app won't let you.
List<Check> eligibility(StudentProfile s, JobListing job) {
  final r = job.rules;
  final checks = <Check>[];

  if (r.minCgpa != null) {
    if (s.cgpa == null) {
      checks.add(Check('CGPA ${r.minCgpa}+', false, detail: 'Add your CGPA to your profile.'));
    } else {
      // Job on a 4-point scale, student on 10-point: convert so we don't compare apples to oranges.
      final yours = (r.minCgpa! <= 4 && s.cgpa! > 4) ? s.cgpa! / 10 * 4 : s.cgpa!;
      final ok = yours >= r.minCgpa!;
      checks.add(Check('CGPA ${r.minCgpa}+', ok, hard: !ok, detail: ok ? 'You: ${s.cgpa}' : 'You: ${s.cgpa} — below the cutoff.'));
    }
  }

  if (r.allowedBatches.isNotEmpty) {
    final y = s.graduationYear;
    final ok = y != null && r.allowedBatches.contains(y);
    checks.add(Check('Batch ${r.allowedBatches.join(' / ')}', ok,
        hard: y != null && !ok, detail: y == null ? 'Add your graduation year.' : 'You: $y'));
  }

  if (job.eligibleGroups.isNotEmpty) {
    final mine = studentGroups(s);
    final theirs = {for (final g in job.eligibleGroups) _groupKey(g)};
    final label = 'Open to: ${job.eligibleGroups.join(', ')}';
    if (mine.isEmpty) {
      checks.add(Check(label, false, detail: 'Add your degree to check this.'));
    } else {
      final ok = theirs.contains('all') || mine.any(theirs.contains);
      checks.add(Check(label, ok, hard: !ok, detail: ok ? 'Your ${s.degree} qualifies.' : "Your ${s.degree} isn't on the list."));
    }
  }

  final cs = countriesOf(job.location);
  if (s.country.isNotEmpty && cs.isNotEmpty) {
    final wp = workplaceOf(job);
    final where = cs.join(' / ');
    if (cs.contains(s.country)) {
      checks.add(Check('Location', true,
          detail: wp == 'remote' ? 'Remote within ${s.country}.' : '${job.location} — same country as you.'));
    } else {
      final auth = _authRe.hasMatch(job.description);
      checks.add(Check('Location', false,
          hard: true,
          detail: wp == 'remote'
              ? 'Remote, but only for people in $where.'
              : "${wp == 'hybrid' ? 'Hybrid' : 'On-site'} in $where — you're in ${s.country}${auth ? ', and it needs local work authorization' : ''}."));
    }
  } else if (s.country.isEmpty && cs.isNotEmpty) {
    checks.add(const Check('Location', false, detail: 'Set your city on the ME tab to check location rules.'));
  }

  // Students and freshers have no work years; "2+ years" roles are out of reach however good the match.
  if (r.minYears >= 1) {
    checks.add(Check('${r.minYears}+ years of experience', false,
        hard: true, detail: 'This role wants ${r.minYears}+ years of work experience. It isn\'t an internship or fresher role.'));
  }

  final tech = techSkills(r.skills);
  if (tech.length >= 2) {
    final mine = s.allSkills;
    final hit = tech.where(mine.contains).length;
    // Posts list everything they'd like; a Flutter dev missing git and REST APIs can still apply to a Flutter
    // internship. Only none of their skills blocks; under a third is a warning.
    final ok = hit * 3 >= tech.length;
    final missing = tech.where((k) => !mine.contains(k)).join(', ');
    checks.add(Check('Tech skills $hit/${tech.length}', ok,
        hard: hit == 0,
        detail: hit == tech.length
            ? 'You have every technical skill they list.'
            : hit == 0
                ? "You show none of the technical skills they need: $missing"
                : 'Missing: $missing'));
  }
  return checks;
}

bool isEligible(StudentProfile s, JobListing j) => !eligibility(s, j).any((c) => c.hard && !c.ok);

class PreflightReport {
  const PreflightReport({required this.checks, required this.matchedSkills, required this.missingSkills, this.swap});
  final List<Check> checks;
  final List<String> matchedSkills;
  final List<String> missingSkills;
  final String? swap;
  bool get cleared => !checks.any((c) => c.hard && !c.ok);
  List<Check> get blockers => [for (final c in checks) if (c.hard && !c.ok) c];
}

int _overlap(Project p, List<String> skills) => p.tags.where(skills.contains).length;

PreflightReport runPreflight(StudentProfile s, JobListing job, List<Project> selected) {
  final r = job.rules;
  final checks = eligibility(s, job);
  final mine = s.allSkills;
  final tech = techSkills(r.skills);
  final matched = tech.where(mine.contains).toList();
  final missing = tech.where((k) => !mine.contains(k)).toList();

  if (selected.isEmpty) {
    checks.add(const Check('Attach at least one project', false, hard: true, detail: 'Proof of work is the whole point.'));
  } else if (matched.isNotEmpty) {
    final proven = {for (final p in selected) ...p.tags};
    final unproven = matched.where((k) => !proven.contains(k)).toList();
    checks.add(Check('Attached proof', unproven.length < matched.length,
        detail: unproven.isEmpty
            ? 'Your attached projects prove every skill you match on.'
            : 'On your resume, but no attached project shows it: ${unproven.join(', ')}'));
  }

  String? swap;
  if (r.skills.isNotEmpty && s.projects.isNotEmpty) {
    final best = s.projects.reduce((a, b) => _overlap(b, r.skills) > _overlap(a, r.skills) ? b : a);
    final bestScore = _overlap(best, r.skills);
    final current = selected.isEmpty ? 0 : selected.map((p) => _overlap(p, r.skills)).reduce((a, b) => a > b ? a : b);
    if (!selected.any((p) => p.id == best.id) && bestScore > current) {
      swap = bestScore >= current * 2
          ? 'Swap attached project to ${best.name} to double skill relevance ($current → $bestScore matches).'
          : 'Swap attached project to ${best.name} for more skill matches ($current → $bestScore).';
    }
  }

  return PreflightReport(checks: checks, matchedSkills: matched, missingSkills: missing, swap: swap);
}

// ───────────────────────── Pitch builder ─────────────────────────

const _kindPriority = {
  Persona.recruiter: [ProjectKind.playStore, ProjectKind.web, ProjectKind.repo, ProjectKind.figma],
  Persona.founder: [ProjectKind.playStore, ProjectKind.web, ProjectKind.repo, ProjectKind.figma],
  Persona.engineer: [ProjectKind.repo, ProjectKind.web, ProjectKind.playStore, ProjectKind.figma],
  Persona.designLead: [ProjectKind.figma, ProjectKind.web, ProjectKind.playStore, ProjectKind.repo],
};

/// Things people can open and use go first for most readers; engineers get the code first.
List<Project> orderForPersona(List<Project> projects, Persona persona) {
  final order = _kindPriority[persona]!;
  return [...projects]..sort((a, b) => order.indexOf(a.kind).compareTo(order.indexOf(b.kind)));
}

/// Resume one-liners are often filler ("Bypassed typical junior developer training cycles…"). Only short, complete ones go in a pitch.
String _pitchable(String oneLiner) => oneLiner.length <= 60 && !oneLiner.endsWith('…') ? oneLiner : '';

/// Where to see it, said the way a person would.
String whereToSee(Project p) => switch (p.kind) {
      ProjectKind.playStore => "It's live on Google Play: ${p.url}",
      ProjectKind.web => "It's live here: ${p.url}",
      ProjectKind.repo => 'The code is here: ${p.url}',
      ProjectKind.figma => "Here's the design: ${p.url}",
    };

const _skillDisplay = {
  'javascript': 'JavaScript', 'typescript': 'TypeScript', 'node.js': 'Node.js', 'next.js': 'Next.js', 'nestjs': 'NestJS',
  'fastapi': 'FastAPI', 'mysql': 'MySQL', 'postgres': 'PostgreSQL', 'mongodb': 'MongoDB', 'graphql': 'GraphQL',
  'rest api': 'REST APIs', 'ui/ux': 'UI/UX', 'ios': 'iOS', 'swiftui': 'SwiftUI', 'ci/cd': 'CI/CD', 'ar/vr': 'AR/VR',
  'pytorch': 'PyTorch', 'tensorflow': 'TensorFlow', 'scikit-learn': 'scikit-learn', 'numpy': 'NumPy', 'power bi': 'Power BI',
  'oop': 'OOP', 'nlp': 'NLP', 'llm': 'LLMs', 'jsp': 'JSP', 'jdbc': 'JDBC', 'php': 'PHP', '.net': '.NET', 'html': 'HTML',
  'css': 'CSS', 'sql': 'SQL', 'aws': 'AWS', 'gcp': 'GCP', 'json': 'JSON', 'xml': 'XML', 'matlab': 'MATLAB',
  'embedded': 'embedded systems', 'data structures': 'data structures', 'machine learning': 'machine learning',
  'deep learning': 'deep learning', 'computer vision': 'computer vision', 'game development': 'game development',
};

/// "flutter" → "Flutter", "node.js" → "Node.js": skills as a person would write them in an email.
String displaySkill(String s) =>
    _skillDisplay[s] ?? s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// "Flutter Developer Intern (2027)" → "Flutter Developer", so "join you as a Flutter Developer intern" reads right.
String roleNoun(String title) => title
    .replaceAll(RegExp(r'\(.*?\)'), '')
    .replaceAll(RegExp(r'\b(intern|interns|internship|trainee)\b', caseSensitive: false), '')
    .replaceAll(RegExp(r'[\s\-–—:|,]+$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// "a, b and c"
String andList(List<String> xs) => xs.length <= 1 ? xs.join() : '${xs.sublist(0, xs.length - 1).join(', ')} and ${xs.last}';

String shortUrl(String url) => url.replaceFirst(RegExp(r'^https?://(www\.)?'), '').replaceAll(RegExp(r'/$'), '');

/// "a B.Sc student at Mithibai College, graduating in 2027"
String studentLine(StudentProfile s, {bool formal = false}) {
  final y = s.graduationYear;
  final done = y != null && y < DateTime.now().year;
  final deg = s.degree.isEmpty ? '' : '${s.degree} ';
  final at = s.college.isEmpty ? '' : (done ? ' from ${s.college}' : ' at ${s.college}');
  if (formal) {
    if (done) return 'I am a $y ${deg}graduate$at';
    final pursuing = s.degree.isEmpty ? 'currently a student$at' : 'currently pursuing a ${s.degree}$at';
    return 'I am $pursuing${y == null ? '' : ', graduating in $y'}';
  }
  if (done) return 'a $y ${deg}graduate$at';
  return 'a ${deg}student$at${y == null ? '' : ', graduating in $y'}';
}

// ───────────────────────── Reading the post for the pitch ─────────────────────────

const _taskVerbs = {
  'build', 'develop', 'design', 'create', 'write', 'implement', 'maintain', 'work', 'collaborate', 'assist', 'help',
  'integrate', 'test', 'debug', 'optimize', 'optimise', 'improve', 'manage', 'research', 'analyze', 'analyse', 'support',
  'deploy', 'ship', 'own', 'contribute', 'prototype', 'automate', 'conduct', 'prepare', 'handle', 'execute', 'run',
  'plan', 'coordinate', 'identify', 'drive', 'engage', 'edit', 'produce',
};
final _askPrefix = RegExp(r'^(experience (with|in)|hands-on experience|knowledge of|familiarity with|proficiency (in|with)|understanding of|strong|good|basic|working knowledge|exposure to|ability to)\b', caseSensitive: false);
final _boilerplate = RegExp(r'\b(we are|we\x27re|about us|equal opportunit|benefits|perks|stipend|salary|ctc|apply|duration|location|who can apply|certificate|letter of recommendation|number of openings|eligib)', caseSensitive: false);

/// One line from the post, matched to the project that proves it.
class JdMatch {
  const JdMatch(this.phrase, this.isTask, this.project, this.shared);
  final String phrase; // the post's own words, lower-cased start, no trailing period
  final bool isTask; // "build and maintain…" (a duty) vs "experience with…" (an ask)
  final Project? project;
  final List<String> shared; // skills the line and the project have in common
}

/// The post line your best project speaks to most directly. Null when the post is too thin to quote.
JdMatch? jdMatch(JobListing job, List<Project> projects) {
  final lines = job.description
      .split(RegExp(r'\n|•|●|▪|;|(?<=\.)\s+'))
      .map((l) => l
          .replaceFirst(RegExp(r'^[\s\-*–>✓\d.)]+'), '')
          .replaceFirst(RegExp(r"^(you will|you'll|you would|the intern will|responsibilities|requirements|key responsibilities|what you'll do|role)\s*:?\s*", caseSensitive: false), '')
          .replaceFirst(RegExp(r'[.!:]+$'), '')
          .trim())
      .where((l) => l.length >= 20 && l.split(' ').length <= 18 && !_boilerplate.hasMatch(l))
      .toList();
  JdMatch? best;
  var bestScore = 0;
  for (final l in lines) {
    final first = l.split(' ').first.toLowerCase();
    final task = _taskVerbs.contains(first) || _taskVerbs.contains(first.replaceFirst(RegExp(r'(s|ing)$'), ''));
    final ask = _askPrefix.hasMatch(l);
    if (!task && !ask) continue;
    final inLine = scanSkills(l);
    for (final p in projects.isEmpty ? <Project?>[null] : projects) {
      final shared = [for (final s in inLine) if (p?.tags.contains(s) ?? false) s];
      final score = shared.length * 3 + inLine.length + (task ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        final phrase = l[0].toUpperCase() == l[0] && l.length > 1 && l[1].toLowerCase() == l[1] ? l[0].toLowerCase() + l.substring(1) : l;
        best = JdMatch(phrase, task, p, shared);
      }
    }
  }
  return best;
}

/// "3 months" / "6 weeks" when the post says how long.
String? _durationIn(String text) =>
    RegExp(r'\b(\d{1,2}(?:\s*(?:-|–|to)\s*\d{1,2})?)\s*(months?|weeks?)\b', caseSensitive: false).firstMatch(text)?.group(0);

/// "You need someone to build and maintain Flutter apps — that's what I did in Habitly, with Flutter and Firebase."
String _jdSentence(JdMatch m, {bool formal = false}) {
  final p = m.project;
  // Don't repeat "Flutter and Firebase" if the post's own line already names them.
  final named = m.shared.every((s) => m.phrase.toLowerCase().contains(displaySkill(s).toLowerCase()));
  final using = andList(m.shared.take(3).map(displaySkill).toList());
  if (formal) {
    final opener = m.isTask ? 'The role involves the ability to ${m.phrase}' : 'The role calls for ${m.phrase}';
    if (p == null) return '$opener.';
    if (m.shared.isEmpty) return '$opener; my closest work is ${p.name}.';
    if (m.isTask) return named ? '$opener, which I have done in ${p.name}.' : '$opener, which I have done in ${p.name} using $using.';
    return '$opener; I have used ${named ? 'these' : using} in ${p.name}.';
  }
  final opener = m.isTask ? 'You need someone to ${m.phrase}' : "You're looking for ${m.phrase}";
  if (p == null) return '$opener.';
  if (m.shared.isEmpty) return "$opener; ${p.name} is the closest thing I've built.";
  if (m.isTask) return named ? "$opener; that's what I did in ${p.name}." : "$opener; that's what I did in ${p.name}, using $using.";
  return "$opener; I've used ${named ? 'them' : using} in ${p.name}.";
}

class Pitch {
  const Pitch(this.subject, this.body);
  final String subject;
  final String body;
}

/// Everything a template can use, as `{placeholder}` → value.
Map<String, String> templateVars(StudentProfile s, JobListing job, List<Project> projects) {
  final ps = [for (final p in projects) Project(id: p.id, name: p.name, url: cleanUrl(p.url), kind: p.kind, tags: p.tags, oneLiner: _pitchable(p.oneLiner))];
  final top = ps.firstOrNull;
  final proven = {for (final p in ps) ...p.tags};
  var skills = job.rules.skills.where(proven.contains).toList();
  if (skills.isEmpty) skills = job.rules.skills.where(s.allSkills.contains).toList();
  return {
    'company': cleanCompany(job.company),
    'role': job.title,
    'name': s.name,
    'first_name': s.firstName,
    'college': s.college,
    'degree': s.degree,
    'year': s.graduationYear?.toString() ?? '',
    'cgpa': s.cgpa?.toString() ?? '',
    'skills': andList(skills.take(3).map(displaySkill).toList()),
    'project': top?.name ?? '',
    'project_line': top?.oneLiner ?? '',
    'project_link': top?.url ?? '',
    'projects': [for (final p in ps) '- ${p.name}${p.oneLiner.isEmpty ? '' : ': ${p.oneLiner}'} (${p.url})'].join('\n'),
    'github': s.github,
    'linkedin': s.linkedin,
    'portfolio': s.portfolio,
    'phone': s.phone,
    'email': s.email,
    'jd_line': switch (jdMatch(job, projects)) {
      null => '',
      final m => _jdSentence(m),
    },
  };
}

const defaultTemplateSubject = '{role} application - {name}';
const defaultTemplateBody = '''Hi {company} team,

I'm {first_name}, a {degree} student at {college}. I'd love to join you as a {role}.

The project I'm proudest of is {project}: {project_link}

I've attached my resume. Happy to do a short task or a quick call.

Thanks,
{name}
{phone}''';

/// Fills `{placeholders}`; unknown ones stay as typed so the student sees what didn't fill. Tidies empty bits.
String fillTemplate(String tpl, Map<String, String> vars) => tpl
    .replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => vars[m[1]] ?? m[0]!)
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAllMapped(RegExp(r' ([.,:;])'), (m) => m[1]!)
    .replaceAll(RegExp(r'\n ?\n( ?\n)+'), '\n\n')
    .trim();

/// ATS parsers and old portals mangle typographic characters.
String _ascii(String s) => s
    .replaceAll(RegExp('[—–]'), '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('…', '...')
    .replaceAll('·', '|')
    .replaceAll('₹', 'Rs ')
    .replaceAll(RegExp(r'[^\x00-\x7F]'), '');

/// A short, human application. The reader decides which project leads and how it closes;
/// the template decides length and tone. [resumeAttached] only matters for email.
Pitch buildPitch(
  StudentProfile s,
  JobListing job,
  List<Project> projects,
  Channel channel,
  Persona persona, {
  EmailTemplate template = EmailTemplate.standard,
  bool resumeAttached = false,
}) {
  // The project that answers the post's own words leads, whatever the reader type would otherwise prefer.
  final byKind = orderForPersona(projects, persona);
  final jd = jdMatch(job, byKind);
  final lead = jd?.project;
  final ordered = lead == null ? byKind : [lead, ...byKind.where((p) => p.id != lead.id)];
  final v = templateVars(s, job, ordered);

  if (template == EmailTemplate.mine) {
    final subject = fillTemplate(s.templateSubject.isEmpty ? defaultTemplateSubject : s.templateSubject, v);
    final body = fillTemplate(s.templateBody.isEmpty ? defaultTemplateBody : s.templateBody, v);
    return channel == Channel.enterpriseAts ? Pitch(_ascii(subject), _ascii(body)) : Pitch(subject, body);
  }
  // Corporate portals get the plain, formal letter no matter what.
  if (channel == Channel.enterpriseAts) template = EmailTemplate.formal;

  final ps = [
    for (final p in ordered)
      Project(id: p.id, name: p.name, url: cleanUrl(p.url), kind: p.kind, tags: p.tags, oneLiner: _pitchable(p.oneLiner)),
  ];
  final top = ps.firstOrNull;
  final second = ps.skip(1).where((p) => p.url != top?.url).firstOrNull;
  final company = v['company']!, role = job.title, first = v['first_name']!;
  final skills = v['skills']!;
  final email = channel == Channel.directEmail;
  final resumeLine = email ? (resumeAttached ? "I've attached my resume." : '') : 'My resume is attached to this application.';

  // Tailoring from the post: what it asks for, how long, remote, and an honest word on gaps.
  final jdLeads = jd != null && top != null && jd.project?.id == top.id;
  final tech = techSkills(job.rules.skills);
  final missing = tech.where((k) => !s.allSkills.contains(k)).toList();
  final gap = missing.isNotEmpty && missing.length <= 2 && missing.length * 2 < tech.length
      ? "I haven't used ${andList(missing.map(displaySkill).toList())} on a project yet, but I pick up new tools quickly."
      : '';
  final dur = _durationIn(job.description);
  final remote = workplaceOf(job) == 'remote';
  final avail = dur != null
      ? "I'm available for the full $dur${remote ? ' and comfortable working remotely' : ''}."
      : (remote ? "I'm comfortable working remotely." : '');

  final contact = [s.phone, s.email].where((e) => e.isNotEmpty).join(' · ');
  // Never print the same link twice (projects without their own link fall back to the GitHub profile).
  final used = {for (final p in ps) shortUrl(p.url)};
  final links = [s.linkedin, s.github.isNotEmpty ? s.github : s.portfolio]
      .where((e) => e.isNotEmpty)
      .map(shortUrl)
      .where((e) => !used.contains(e))
      .join(' · ');
  String sign(String closing) => [closing, s.name, if (contact.isNotEmpty) contact, if (links.isNotEmpty) links].join('\n');

  final String subject;
  final String body;
  switch (template) {
    case EmailTemplate.short:
      subject = top == null ? '$role - ${s.name}' : '$role - ${s.name} (built ${top.name})';
      body = [
        'Hi $company team,',
        "I'm $first, ${studentLine(s)}, and I'd love to join you as ${roleNoun(role).isEmpty ? 'an intern' : 'a ${roleNoun(role)} intern'}.",
        if (jdLeads && jd.isTask)
          'You need someone to ${jd.phrase}; I did that in ${top.name}: ${top.url}'
        else if (top != null)
          'I built ${top.name}${top.oneLiner.isEmpty ? '' : ' (${top.oneLiner})'}: ${top.url}${second == null ? '' : '. Also ${second.name}: ${second.url}'}',
        '${resumeLine.isEmpty ? '' : '${email ? 'Resume attached.' : resumeLine} '}Happy to do a small task to show you what I can do.',
        [s.name, if (s.phone.isNotEmpty) s.phone else if (s.email.isNotEmpty) s.email].join('\n'),
      ].join('\n\n');
    case EmailTemplate.formal:
      subject = 'Application for the $role position - ${s.name}';
      final cgpa = s.cgpa != null && s.cgpa! >= 7.5 ? ', with a CGPA of ${s.cgpa}' : ''; // only mention it when it helps
      body = [
        'Dear Hiring Manager,',
        'I am writing to apply for the $role position at $company. ${studentLine(s, formal: true)}$cgpa.',
        [
          if (jd != null) _jdSentence(jd, formal: true),
          if (skills.isNotEmpty) 'My relevant skills include $skills.',
          if (ps.isNotEmpty) 'Relevant projects:\n${v['projects']}',
        ].join(' ').replaceFirst('. Relevant', '.\n\nRelevant'),
        '${dur != null ? 'I am available for the full $dur. ' : ''}'
            '${email ? (resumeAttached ? 'Please find my resume attached. ' : '') : '$resumeLine '}'
            'I would welcome the opportunity to discuss how I can contribute to your team.',
        sign('Yours sincerely,'),
      ].where((p) => p.trim().isNotEmpty).join('\n\n');
    case EmailTemplate.standard:
    case EmailTemplate.mine:
      subject = '$role application - ${s.name}';
      final greet = persona == Persona.recruiter ? 'Hello $company hiring team,' : 'Hi $company team,';
      final proudest = persona == Persona.engineer ? 'The best example of my work is' : "The project I'm proudest of is";
      final ask = switch (persona) {
        Persona.recruiter => "I can start soon and I'm happy to share anything else you need.",
        Persona.founder => "If it helps, I'm happy to do a small task so you can see how I work.",
        Persona.engineer => "I'd be glad to walk you through the code on a short call.",
        Persona.designLead => "I'd love to walk you through it on a quick call.",
      };
      body = [
        greet,
        "I'm $first, ${studentLine(s)}. I came across the $role opening at $company and I'd love to be considered.",
        if (jdLeads)
          '${_jdSentence(jd)} ${whereToSee(top)}'
        else
          [
            if (jd != null) _jdSentence(jd),
            if (skills.isNotEmpty) 'I work mostly with $skills, which this role asks for.',
            if (top != null) '$proudest ${top.name}${top.oneLiner.isEmpty ? '' : ', ${top.oneLiner}'}. ${whereToSee(top)}',
          ].join(' '),
        if (second != null) "I've also built ${second.name}: ${second.url}",
        [gap, avail].where((x) => x.isNotEmpty).join(' '),
        [if (resumeLine.isNotEmpty) resumeLine, ask].join(' '),
        sign('Thanks for your time,'),
      ].where((p) => p.trim().isNotEmpty).join('\n\n');
  }
  return channel == Channel.enterpriseAts ? Pitch(_ascii(subject), _ascii(body)) : Pitch(subject, body);
}

// ───────────────────────── mailto: handoff ─────────────────────────

const maxMailtoBody = 1800;

/// Don't use `Uri(queryParameters:)`: it encodes spaces as `+`, which Gmail and Apple Mail show literally.
Uri buildMailto(String to, String subject, String body) {
  final b = body.length > maxMailtoBody ? '${body.substring(0, maxMailtoBody - 1)}…' : body;
  return Uri.parse('mailto:${Uri.encodeComponent(to).replaceAll('%40', '@')}'
      '?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(b)}');
}
