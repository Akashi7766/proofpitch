import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'engines.dart';
import 'models.dart';

// ───────────────────────── Resume import ─────────────────────────

/// PDF → text, one line per visual line. Clickable links hidden behind words like "[View GitHub]"
/// are appended to the line they sit on, so the parser sees the real URL.
String pdfToText(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final lines = PdfTextExtractor(doc).extractTextLines();
    final out = [for (final l in lines) _spacedLine(l)];
    for (var p = 0; p < doc.pages.count; p++) {
      final ann = doc.pages[p].annotations;
      for (var i = 0; i < ann.count; i++) {
        final a = ann[i];
        final url = a is PdfUriAnnotation ? a.uri : (a is PdfTextWebLink ? a.url : '');
        if (url.isEmpty) continue;
        final mid = a.bounds.top + a.bounds.height / 2;
        final at = lines.indexWhere((l) => l.pageIndex == p && mid >= l.bounds.top - 2 && mid <= l.bounds.bottom + 2);
        if (at >= 0 && !out[at].contains(url)) out[at] = '${out[at]} $url';
      }
    }
    return out.join('\n');
  } finally {
    doc.dispose();
  }
}

/// LaTeX (and some other) resumes place words by position instead of writing space characters, so the
/// extractor returns "StudyNotesHandler—Flutter,Firebase". Put a space back wherever two letters sit
/// clearly apart (more than a fifth of the font size); inside a word the gap is ~0.
String _spacedLine(TextLine l) {
  if (l.wordCollection.isEmpty) return l.text;
  // Word/Google Docs exports can come back as one "word" per letter; joining those would give
  // "M O H A M M A D". The line's own text already has the right spaces there.
  final words = l.wordCollection.where((w) => w.text.trim().isNotEmpty).toList();
  if (words.length > 3 && words.where((w) => w.text.length == 1).length * 2 > words.length) return l.text;
  final minGap = (l.fontSize > 0 ? l.fontSize : l.bounds.height) * 0.2; // some PDFs report size 0
  return l.wordCollection.map((w) {
    final g = w.glyphs;
    if (g.length < 2 || g.map((x) => x.text).join() != w.text) return w.text; // ligatures etc.: trust the word
    final b = StringBuffer(g.first.text);
    for (var i = 1; i < g.length; i++) {
      final gap = g[i].bounds.left - g[i - 1].bounds.right;
      if (gap > minGap && g[i].text.trim().isNotEmpty && g[i - 1].text.trim().isNotEmpty) b.write(' ');
      b.write(g[i].text);
    }
    return b.toString();
  }).join(' ');
}

class ResumeData {
  const ResumeData({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.college = '',
    this.degree = '',
    this.cgpa,
    this.graduationYear,
    this.github = '',
    this.linkedin = '',
    this.portfolio = '',
    this.city = '',
    this.country = '',
    this.skills = const [],
    this.projects = const [],
    this.warnings = const [],
    this.experience = const [],
    this.extras = const [],
    this.sections = const [],
  });

  final String name, email, phone, college, degree, github, linkedin, portfolio, city, country;
  final double? cgpa;
  final int? graduationYear;
  final List<String> skills;
  final List<Project> projects;

  /// Raw lines from the experience and achievements/certifications sections (for the tailored resume).
  final List<String> experience;
  final List<String> extras;

  /// Every section as written (heading + raw lines), for the tailored PDF and the in-app editor.
  final List<ResumeSection> sections;

  /// Things worth fixing in the resume itself (dead links, Google-wrapped URLs…).
  final List<String> warnings;

  /// Fill only what the resume found; keep what the user already typed elsewhere.
  StudentProfile mergeInto(StudentProfile p) {
    final known = {for (final x in p.projects) x.name.toLowerCase()};
    String? v(String s) => s.isEmpty ? null : s;
    return p.copyWith(
      name: v(name),
      email: v(email),
      phone: v(phone),
      college: v(college),
      degree: v(degree),
      cgpa: cgpa,
      graduationYear: graduationYear,
      github: v(github),
      linkedin: v(linkedin),
      portfolio: v(portfolio),
      city: p.city.isEmpty ? v(city) : null,
      country: p.country.isEmpty ? v(country) : null,
      skills: {...p.skills, ...skills}.toList(),
      // Known projects keep the user's edits but pick up bullet points they didn't have yet.
      projects: [
        for (final old in p.projects)
          switch (projects.where((x) => x.name.toLowerCase() == old.name.toLowerCase() && old.bullets.isEmpty).firstOrNull) {
            null => old,
            final fresh => Project(id: old.id, name: old.name, url: old.url, kind: old.kind, tags: old.tags, oneLiner: old.oneLiner, bullets: fresh.bullets),
          },
        ...projects.where((x) => !known.contains(x.name.toLowerCase())),
      ],
      experience: experience.isEmpty ? null : experience,
      extras: extras.isEmpty ? null : extras,
      resumeSections: sections.isEmpty ? null : sections,
    );
  }
}

final _urlRe = RegExp(
    r'(?:https?://)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|io|dev|app|me|in|co|ai|org|net|xyz|site|tech|gg|page)(?:/[^\s,;|)\]]*)?',
    caseSensitive: false);
final _bulletRe = RegExp(r'^[•●▪◦\-*–>➢✓]\s*');

/// Section a heading line opens, or null if the line isn't a heading.
/// Handles "PROJECTS", "Featured Software Projects", "TECHNICAL SKILLS (IMMEDIATE EXECUTION)", "Education:".
String? _section(String line) {
  if (_bulletRe.hasMatch(line) || line.length > 60 || line.contains('|') || line.contains('@')) return null;
  final core = line.replaceAll(RegExp(r'\(.*?\)'), '').replaceAll(RegExp(r'[:\s]+$'), '').trim();
  // "CGPA: 8.42/10" or "Languages: Python, C#" are content, not headings.
  if (RegExp(r'\d').hasMatch(core) || core.contains(':') || core.contains(',')) return null;
  final letters = core.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length < 4) return null;
  final shouty = letters == letters.toUpperCase();
  final words = core.split(RegExp(r'\s+')).length;
  final l = core.toLowerCase();
  final kind = switch (l) {
    _ when l.contains('project') => 'projects',
    _ when l.contains('skill') || l.contains('tech stack') || l.contains('technologies') => 'skills',
    _ when l.contains('education') || l.contains('academic') || l.contains('qualification') => 'education',
    _ when l.contains('experience') || l.contains('internship') || l.contains('employment') => 'experience',
    _ when l.contains('summary') || l.contains('objective') || l.contains('profile') || l.contains('about') => 'summary',
    _ when RegExp(r'achievement|award|certific|honou?r|activit|leadership|responsibilit|interest|language|publication|hackathon|volunteer|coursework|extra')
        .hasMatch(l) =>
      'other',
    _ => null,
  };
  if (kind != null && (shouty || words <= 4 || line.trimRight().endsWith(':'))) return kind;
  return shouty && words <= 5 ? 'other' : null;
}

ProjectKind kindForUrl(String url) {
  final u = url.toLowerCase();
  if (u.contains('play.google')) return ProjectKind.playStore;
  if (u.contains('figma.com')) return ProjectKind.figma;
  if (u.contains('github.com') || u.contains('gitlab.com')) return ProjectKind.repo;
  return ProjectKind.web;
}

String _https(String url) => url.startsWith('http') ? url : 'https://$url';

/// google.com/search?q=https://real.link → https://real.link (some resume builders wrap links like this).
String _unwrap(String url) {
  final m = RegExp(r'google\.[a-z.]+/(?:search|url)\?(?:q|url)=([^&\s]+)').firstMatch(url);
  return m == null ? url : Uri.decodeComponent(m.group(1)!).replaceFirst('mailto:', '');
}

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

const _cities = {
  'mumbai': 'India', 'navi mumbai': 'India', 'thane': 'India', 'pune': 'India', 'bengaluru': 'India', 'bangalore': 'India',
  'hyderabad': 'India', 'chennai': 'India', 'delhi': 'India', 'new delhi': 'India', 'noida': 'India', 'gurugram': 'India',
  'gurgaon': 'India', 'kolkata': 'India', 'ahmedabad': 'India', 'jaipur': 'India', 'kochi': 'India', 'indore': 'India',
  'chandigarh': 'India', 'lucknow': 'India', 'nagpur': 'India', 'bhopal': 'India', 'coimbatore': 'India',
};

// ponytail: heuristics tuned for common student resumes (one-column, ATS-style). Two-column templates
// can scramble text order; the review screen lets the user fix anything before it's saved.
ResumeData parseResume(String raw) {
  final warnings = <String>[];
  var lines = [for (final l in raw.split('\n')) if (l.trim().isNotEmpty) l.trim().replaceAll(RegExp(r'\s{2,}'), ' ')];

  // Unwrap Google-search-wrapped links in place, and remember to tell the user.
  if (lines.any((l) => l.contains('google.com/search?q=') || l.contains('google.com/url?'))) {
    warnings.add('Some links in your PDF point to a Google search instead of the real page — re-export with plain links.');
    lines = [for (final l in lines) l.replaceAllMapped(RegExp(r'https?://(?:www\.)?google\.[a-z.]+/(?:search|url)\?\S+'), (m) => _unwrap(m[0]!))];
  }
  final text = lines.join('\n');
  final lower = text.toLowerCase();

  // Split into sections.
  final sections = <String, List<String>>{};
  final headed = <(String, String, List<String>)>[]; // (heading as written, kind, lines)
  var current = 'header';
  for (final (i, l) in lines.indexed) {
    final s = i == 0 ? null : _section(l);
    if (s != null) {
      current = s;
      sections.putIfAbsent(s, () => []);
      headed.add((l.replaceAll(RegExp(r'[:\s]+$'), ''), s, []));
    } else {
      (sections[current] ??= []).add(l);
      if (headed.isNotEmpty) headed.last.$3.add(l);
    }
  }

  // Name: first line that looks like a name, Title Cased if shouted.
  final nameLine = lines.take(5).firstWhere(
        (l) => RegExp(r"^[A-Za-z][A-Za-z.'\- ]{2,40}$").hasMatch(l) && l.split(' ').length >= 2 && _section(l) == null,
        orElse: () => lines.isEmpty ? '' : lines.first,
      );
  final name = RegExp(r"^[A-Za-z][A-Za-z.'\- ]{2,40}$").hasMatch(nameLine)
      ? (nameLine == nameLine.toUpperCase() ? _titleCase(nameLine) : nameLine)
      : '';

  final email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').firstMatch(text)?.group(0) ?? '';
  final phone = RegExp(r'(\+?\d[\d\s-]{8,}\d)').firstMatch(text)?.group(1)?.trim() ?? '';

  final urls = [
    for (final m in _urlRe.allMatches(text))
      if (!email.contains(m.group(0)!)) m.group(0)!.replaceAll(RegExp(r'[.)\]]+$'), ''),
  ];
  final github = urls.firstWhere((u) => RegExp(r'github\.com/[^/\s]+/?$').hasMatch(u), orElse: () => '');
  final linkedin = urls.firstWhere((u) => u.contains('linkedin.com/in/'), orElse: () => '');
  final portfolio = urls.firstWhere(
    (u) => !RegExp(r'github\.com|linkedin\.com|google\.|figma\.com|play\.google|apple\.com').hasMatch(u),
    orElse: () => '',
  );

  // Education.
  final edu = (sections['education'] ?? lines).join('\n');
  final eduLower = edu.toLowerCase();
  double? cgpa;
  final cg = RegExp(r'(?:c\.?g\.?p\.?a|\bgpa|\bcpi)[^0-9\n]{0,15}(\d{1,2}\.\d{1,2})').firstMatch(eduLower) ??
      RegExp(r'(\d\.\d{1,2})\s*/\s*10').firstMatch(eduLower);
  if (cg != null) cgpa = double.tryParse(cg.group(1)!);

  final collegeLine = (sections['education'] ?? lines).firstWhere(
    (l) => RegExp(r'university|institute|college|\biit\b|\bnit\b|\bbits\b|school of|vidyalaya|academy', caseSensitive: false).hasMatch(l),
    orElse: () => '',
  );
  var college = collegeLine.split(RegExp(r'\s[|–—]\s|\s\|\s?|,\s*(?=\d)|\s\d{4}')).first.replaceAll(RegExp(r'[,\s|]+$'), '').trim();
  // "Bachelor of Science in Computer Science (SYBSc CS) Mithibai College": the degree came first; keep the institution.
  if (RegExp(r'\b(bachelor|master|diploma|b\.?\s?(sc|tech|e|com|ca|ba)|m\.?\s?(sc|tech|ca|ba))\b', caseSensitive: false).hasMatch(college)) {
    final inst = RegExp(r"(?:[A-Z][\w.'’&-]*\s+){0,4}(?:College|University|Institute|Academy|Vidyalaya)\b(?:\s+of(?:\s+[A-Z][\w&]*){1,4})?")
        .allMatches(college)
        .lastOrNull;
    if (inst != null) college = inst[0]!.trim();
  }

  final degree = switch (eduLower) {
    _ when RegExp(r'b\.?\s?tech|bachelor of technology|b\.?e\.?\b|bachelor of engineering').hasMatch(eduLower) => 'B.Tech',
    _ when RegExp(r'm\.?\s?tech|master of technology').hasMatch(eduLower) => 'M.Tech',
    _ when RegExp(r'\bmca\b|master of computer applications').hasMatch(eduLower) => 'MCA',
    _ when RegExp(r'\bbca\b|bachelor of computer applications').hasMatch(eduLower) => 'BCA',
    _ when RegExp(r'm\.?\s?sc|master of science').hasMatch(eduLower) => 'M.Sc',
    _ when RegExp(r'b\.?\s?sc|bachelor of science').hasMatch(eduLower) => 'B.Sc',
    _ when RegExp(r'\bmba\b').hasMatch(eduLower) => 'MBA',
    _ when RegExp(r'\bbba\b|\bbms\b').hasMatch(eduLower) => 'BBA',
    _ when RegExp(r'b\.?\s?com|bachelor of commerce').hasMatch(eduLower) => 'B.Com',
    _ when RegExp(r'\bb\.?a\.?\b|bachelor of arts').hasMatch(eduLower) => 'BA',
    _ => '',
  };

  int? year;
  final now = DateTime.now().year;
  final eduLines = sections['education'] ?? lines;
  for (var i = 0; i < eduLines.length; i++) {
    final l = eduLines[i];
    if (sections['education'] == null &&
        !RegExp(r'b\.?\s?tech|b\.?\s?sc|bachelor|master|university|college|institute|expected|graduat|class of', caseSensitive: false).hasMatch(l)) {
      continue;
    }
    // Dates often sit on the line after the degree.
    for (final m in RegExp(r'\b(20\d\d)\b').allMatches('$l ${i + 1 < eduLines.length ? eduLines[i + 1] : ''}')) {
      final y = int.parse(m.group(1)!);
      if (y <= now + 5 && (year == null || y > year)) year = y;
    }
  }

  // Skills: read the skills section token by token (catches C#, Unity, C…), then add anything known mentioned elsewhere.
  final skills = <String>{};
  for (final l in sections['skills'] ?? const <String>[]) {
    final body = l.replaceFirst(_bulletRe, '').replaceFirst(RegExp(r'^[^:]{1,40}:\s*'), '');
    skills.addAll(splitSkills(body));
  }
  skills.addAll(scanSkills(lower));
  skills.removeWhere(isToolNotSkill);

  var city = '', country = '';
  for (final l in lines.take(8)) {
    final c = _cities.keys.firstWhere((k) => RegExp('\\b$k\\b', caseSensitive: false).hasMatch(l), orElse: () => '');
    if (c.isNotEmpty) {
      city = _titleCase(c);
      country = _cities[c]!;
      break;
    }
  }
  if (country.isEmpty && phone.startsWith('+91')) country = 'India';

  final projects = _projects(sections['projects'] ?? const [], github.isEmpty ? '' : _https(github), warnings);
  if (year == null && degree.isNotEmpty) {
    warnings.add('No graduation year found. Add it below: batch rules and "Fresher" internships depend on it.');
  }

  return ResumeData(
    name: name,
    email: email,
    phone: phone,
    college: college,
    degree: degree,
    cgpa: (cgpa != null && cgpa <= 10) ? cgpa : null,
    graduationYear: year,
    github: github.isEmpty ? '' : _https(github),
    linkedin: linkedin.isEmpty ? '' : _https(linkedin),
    portfolio: portfolio.isEmpty ? '' : _https(portfolio),
    city: city,
    country: country,
    skills: skills.toList(),
    projects: projects,
    warnings: warnings,
    experience: _plainLines(sections['experience']).take(12).toList(),
    extras: _plainLines(sections['other']).take(8).toList(),
    sections: [for (final (t, k, ls) in headed) if (ls.isNotEmpty) ResumeSection(t, k, ls)],
  );
}

/// Section lines without bullet glyphs or bare URLs.
Iterable<String> _plainLines(List<String>? lines) => [
      for (final l in lines ?? const <String>[])
        if (l.replaceFirst(_bulletRe, '').replaceAll(_urlRe, '').trim() case final t when t.length > 2) t,
    ];

final _linkLabelRe = RegExp(r'^(play\s?store|app store|github|repo|repository|live|demo|link|website|url|source|code)\s*[:\-–]', caseSensitive: false);

List<Project> _projects(List<String> body, String fallbackUrl, List<String> warnings) {
  if (body.isEmpty) return const [];
  // "Name | Tech | Link" layouts: a title is any non-bullet line with a pipe.
  final pipeMode = body.any((l) => l.contains('|') && !_bulletRe.hasMatch(l));

  final blocks = <List<String>>[]; // [title, ...details]
  var prevBullet = false;
  for (final l in body) {
    final bullet = _bulletRe.hasMatch(l);
    final attach = _linkLabelRe.hasMatch(l) || RegExp(r'^\S+\.\S+/\S*$').hasMatch(l);
    final startsLower = RegExp(r'^[a-z(]').hasMatch(l);
    final titleish = l.length < 70 && !startsLower && !l.endsWith('.') && !l.endsWith(',');
    final isTitle = !bullet &&
        !attach &&
        (l.contains('|') ||
            (!pipeMode && titleish) ||
            // Mixed layouts: "Habitly - Flutter, Firebase" right after the previous project's bullets.
            (pipeMode && prevBullet && titleish && (RegExp(r'\s[–—-]\s').hasMatch(l) || l.split(' ').length <= 6)));
    prevBullet = bullet || (prevBullet && !isTitle && !attach);
    if (isTitle || blocks.isEmpty) {
      blocks.add([l]);
    } else if (bullet || attach || blocks.last.length == 1) {
      blocks.last.add(l.replaceFirst(_bulletRe, ''));
    } else {
      blocks.last[blocks.last.length - 1] += ' $l'; // wrapped continuation of the previous bullet
    }
  }

  final out = <Project>[];
  for (final (i, b) in blocks.indexed) {
    var segs = b.first.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (segs.length == 1) segs = segs.first.split(RegExp(r'\s[–—-]\s')).map((e) => e.trim()).toList();
    var title = segs.isEmpty ? b.first : segs.first;
    var oneLiner = '';
    final paren = RegExp(r'^(.*?)\s*\((.+)\)\s*$').firstMatch(title);
    if (paren != null) {
      title = paren.group(1)!.trim();
      oneLiner = paren.group(2)!.trim();
    }
    title = title.split(RegExp(r'\s[–—-]\s')).first.trim();
    if (title.isEmpty || title.length > 60) continue;

    final blockText = b.join(' ');
    final url = _urlRe.allMatches(blockText).map((m) => m.group(0)!).firstWhere(
          (u) => !RegExp(r'github\.com/[^/\s]+/?$').hasMatch(u),
          orElse: () => '',
        );
    final link = url.replaceAll(RegExp(r'[.)\]]+$'), '');
    if (link.isEmpty && RegExp(r'view|github|repo|link|demo', caseSensitive: false).hasMatch(b.first)) {
      warnings.add('"$title" mentions a link but the PDF has no URL behind it — add the real link.');
    }

    final tags = <String>{
      for (final seg in segs.skip(1))
        if (!RegExp(r'view|link|repo|demo|live|\[|http', caseSensitive: false).hasMatch(seg)) ...splitSkills(seg),
      ...scanSkills(blockText),
    };

    if (oneLiner.isEmpty && b.length > 1) {
      final first = b.skip(1).firstWhere((x) => !_linkLabelRe.hasMatch(x) && !x.startsWith('http'), orElse: () => '');
      // Drop "Zero-Ramp Deployment:" style labels; long bullets are resume filler, not a one-liner.
      final bullet = first.replaceFirst(RegExp(r'^[^:]{3,40}:\s*'), '');
      if (bullet.length <= 60) oneLiner = bullet;
    }
    if (oneLiner.isEmpty && kindForUrl(link) == ProjectKind.playStore && link.isNotEmpty) oneLiner = 'Live on Google Play';

    out.add(Project(
      id: 'resume-$i-${title.hashCode}',
      name: title,
      url: link.isEmpty ? fallbackUrl : _https(cleanUrl(link)),
      kind: link.isEmpty ? ProjectKind.repo : kindForUrl(link),
      tags: tags.toList(),
      oneLiner: _clip(oneLiner, 80),
      bullets: [
        for (final x in b.skip(1))
          if (!_linkLabelRe.hasMatch(x) && !x.startsWith('http'))
            if (x.replaceAll(_urlRe, '').trim() case final t when t.length > 15) t,
      ].take(4).toList(),
    ));
    if (out.length == 6) break;
  }
  return out;
}

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1).trimRight()}…';

// ───────────────────────── Matching ─────────────────────────

/// % of the job's skills your resume can back up. Null when the post lists none we recognise.
/// Posts naming fewer than 3 skills are scored out of 3, so one lucky keyword isn't a "100% match".
int? matchScore(Set<String> mine, JobListing j) {
  final tech = techSkills(j.rules.skills);
  if (tech.isEmpty) return null;
  final hit = tech.where(mine.contains).length;
  return (hit * 100 / (tech.length < 3 ? 3 : tech.length)).round();
}

enum Role {
  engineering('⚙️', 'Engineering'),
  data('🧪', 'Data & AI'),
  mobile('📱', 'Mobile'),
  design('🎨', 'Design'),
  product('🧭', 'Product'),
  other('✳️', 'Other');

  const Role(this.emoji, this.label);
  final String emoji, label;
}

Role roleOf(String title) {
  final t = title.toLowerCase();
  if (RegExp(r'android|ios|mobile|flutter').hasMatch(t)) return Role.mobile;
  if (RegExp(r'data|machine learning|\bml\b|\bai\b|research|scien|analyt').hasMatch(t)) return Role.data;
  if (RegExp(r'design|ux|ui\b|brand').hasMatch(t)) return Role.design;
  if (RegExp(r'product manag|\bpm\b|product intern|program manag').hasMatch(t)) return Role.product;
  if (RegExp(r'engineer|developer|software|swe|backend|frontend|full.?stack|infra|security|devops|sre').hasMatch(t)) {
    return Role.engineering;
  }
  return Role.other;
}

// ───────────────────────── Age ─────────────────────────

String ageLabel(DateTime? posted, [DateTime? now]) {
  if (posted == null) return '';
  final d = (now ?? DateTime.now()).difference(posted);
  if (d.inHours < 24) return 'today';
  if (d.inDays < 7) return '${d.inDays}d ago';
  if (d.inDays < 30) return '${d.inDays ~/ 7}w ago';
  if (d.inDays < 365) return '${d.inDays ~/ 30}mo ago';
  return '1y+ ago';
}

bool isFresh(DateTime? posted) => posted != null && DateTime.now().difference(posted).inDays <= 3;

// ───────────────────────── Pay ─────────────────────────

final _money = RegExp(
  r'(?:[$₹€£]|\busd\b|\binr\b|\brs\.?)\s?\d[\d,]*(?:\.\d+)?\s?k?(?:\s?(?:-|–|—|to)\s?(?:[$₹€£]|usd|inr|rs\.?)?\s?\d[\d,]*(?:\.\d+)?\s?k?)?'
  r'(?!\s?(?:m\b|mn\b|bn?\b|million|billion|crore|cr\b|lakh users|\+? users))'
  r'(?:\s?(?:/|per|a)\s?(?:hour|hr|month|mo|week|wk|year|yr|annum))?',
  caseSensitive: false,
);

/// Stipend/pay as written in the post, "Unpaid" when it says so, null when it doesn't say.
String? payFromText(String text) {
  if (RegExp(r'\bunpaid\b|no stipend|without stipend', caseSensitive: false).hasMatch(text)) return 'Unpaid';
  for (final m in _money.allMatches(text)) {
    var v = m.group(0)!.trim();
    // A bare "$5" or "₹1" is never a stipend; need a real number.
    if (!RegExp(r'\d{2,}|\dk', caseSensitive: false).hasMatch(v)) continue;
    // "$46 — $46" → "$46"
    final range = RegExp(r'^(\S+?)\s?(?:-|–|—|to)\s?(\S+)(.*)$').firstMatch(v);
    if (range != null && range.group(1) == range.group(2)) v = '${range.group(1)}${range.group(3)}';
    return v;
  }
  final st = RegExp(r'stipend[^.\n]{0,30}?(\d[\d,]{2,}\s?k?|\d{1,3}\s?k)(?:\s?(?:/|per)\s?(month|week))?', caseSensitive: false)
      .firstMatch(text);
  if (st != null) return '₹${st.group(1)}${st.group(2) == null ? '' : '/${st.group(2)}'}';
  return null;
}

// ───────────────────────── Summary ─────────────────────────

class JobSummary {
  const JobSummary({this.tldr = '', this.doing = const [], this.wants = const [], this.pay, this.duration, this.workplace = ''});
  final String tldr;
  final List<String> doing;
  final List<String> wants;
  final String? pay;
  final String? duration;
  final String workplace;
}

final _doHeader = RegExp(r"what you('|’)?ll do|what you will do|responsibilit|the role|your impact|in this role|day.to.day|you will:|you'll:",
    caseSensitive: false);
final _wantHeader = RegExp(
    r"requirement|qualification|what we('|’)?re looking for|you have|who you are|about you|what you bring|must.have|you might be|you should|ideal candidate",
    caseSensitive: false);

JobSummary summarize(JobListing j) {
  final lines = [for (final l in j.description.split('\n')) if (l.trim().isNotEmpty) l.trim()];
  final doing = <String>[], wants = <String>[];
  List<String>? bucket;
  for (final l in lines) {
    final headerish = l.length < 70 && !_bulletRe.hasMatch(l);
    if (headerish && _doHeader.hasMatch(l)) {
      bucket = doing;
    } else if (headerish && _wantHeader.hasMatch(l)) {
      bucket = wants;
    } else if (headerish && (l.endsWith(':') || (l == l.toUpperCase() && l.length > 3))) {
      bucket = null; // some other section
    } else if (bucket != null && bucket.length < 4 && l.length > 12) {
      bucket.add(_clip(l.replaceFirst(_bulletRe, ''), 140));
    }
  }

  final lower = j.description.toLowerCase();
  final pay = j.stipend.isNotEmpty ? j.stipend : payFromText(j.description);
  final dur = RegExp(r'\b(\d{1,2}(?:\s?[-–to]+\s?\d{1,2})?)[\s-]*(weeks?|months?)\b').firstMatch(lower);

  final known = workplaceOf(j);
  final wp = known.isNotEmpty
      ? known
      : lower.contains('remote')
          ? 'remote'
          : lower.contains('hybrid')
              ? 'hybrid'
              : '';

  // TL;DR: first meaty sentence that talks about the role or "you", not company boilerplate.
  final sentences = j.description
      .replaceAll('\n', ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .where((s) => s.length > 50 && s.length < 260)
      .toList();
  final tldr = sentences.firstWhere(
        (s) => RegExp(r'\byou\b|\bintern|\bjoin\b|\brole\b', caseSensitive: false).hasMatch(s),
        orElse: () => sentences.isEmpty ? '' : sentences.first,
      );

  return JobSummary(
    tldr: tldr,
    doing: doing,
    wants: wants,
    pay: pay,
    duration: dur == null ? null : '${dur.group(1)} ${dur.group(2)}',
    workplace: wp,
  );
}
