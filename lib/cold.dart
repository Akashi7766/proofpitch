import 'engines.dart';
import 'feed.dart';
import 'models.dart';
import 'outreach.dart' show SiteContact, ContactRole;

// ───────────────────────── Cold pitches ─────────────────────────
// Writing to a company that isn't advertising: small teams, a real person's inbox, and a reason to talk.
// The "reason" can be a hole on their public website: things any visitor can see (slow page, broken
// links, not mobile-ready…). Never security probing: that's illegal without permission and kills the pitch.

/// A company worth a cold email, from what's already in the feed.
class ColdTarget {
  const ColdTarget(this.company, this.roles, this.sources, this.fields, this.sample, {this.about = '', this.githubOrg = ''});
  final String company;
  final List<String> roles; // what they've posted, so you know what they work on
  final Set<String> sources; // where we saw them ("🟣 Unstop", "✈️ Telegram @x", "🟠 Y Combinator")
  final Set<Interest> fields;
  final JobListing sample; // a post of theirs (or their website): domain hints, description
  final String about; // one line on what they do, when the source says
  final String githubOrg; // GitHub login: website and email are read from it when opened
}

Set<Interest> _fieldsIn(String text) => {for (final i in Interest.values) if (i.re.hasMatch(text)) i};

/// Y Combinator startups (the public yc-oss dataset) worth a cold email from an Indian student:
/// active, small, and either in India or fully remote and hiring.
List<ColdTarget> ycTargets(List<Map> companies) => [
      for (final c in companies)
        if (c['status'] == 'Active' && ((c['team_size'] as num?) ?? 0) <= 100)
          if (_inIndia(c) || ('${c['regions']}'.contains('Fully Remote') && c['isHiring'] == true))
            if ((c['website'] as String? ?? '').isNotEmpty)
              ColdTarget(
                (c['name'] as String).replaceAll(RegExp(r',? Inc\.?$'), ''),
                const [],
                {_inIndia(c) ? '🟠 Y Combinator · ${c['batch']}' : '🟠 Y Combinator · Remote'},
                // One-liner, tags and industries only: long descriptions mention everything.
                _fieldsIn([c['one_liner'], ...?(c['tags'] as List?), ...?(c['industries'] as List?)].whereType<String>().join(' · ')),
                JobListing(id: 'yc-${c['slug']}', company: c['name'], title: '', applyTarget: c['website'], location: c['all_locations'] ?? ''),
                about: c['one_liner'] ?? '',
              ),
    ];

bool _inIndia(Map c) => '${c['regions']} ${c['all_locations']}'.contains('India');

// College clubs and communities share names with studios ("GameDevJiit", "Game-Developers-Kerala").
// Word-bounded where short: "nit" is inside "Infinite" and "Unity".
final _clubRe = RegExp(r'club|college|universit|student|society|community|association|gdsc|geeks|hackathon|bootcamp|developers?-|-org$|\b(iit|nit|jiit|dsc|iiit)\b',
    caseSensitive: false);

/// GitHub search results for companies in a field → targets. Details (website, email) load when opened.
List<ColdTarget> githubTargets(Interest field, List<Map> items) => [
      for (final o in items)
        if (!_clubRe.hasMatch(o['login'] as String))
          ColdTarget(
            o['login'],
            const [],
            const {'🐙 GitHub'},
            {field},
            JobListing(id: 'gh-org-${o['login']}', company: o['login'], title: '', applyTarget: ''),
            githubOrg: o['login'],
          ),
    ];

/// GitHub org details → (display name, website, public email, description). Clubs come back null.
({String name, String website, String email, String about})? githubOrgInfo(Map o) {
  final about = (o['description'] as String? ?? '').trim();
  final name = (o['name'] as String? ?? '').trim();
  if (_clubRe.hasMatch('$name $about')) return null;
  return (
    name: name.isEmpty ? o['login'] as String : name,
    website: (o['blog'] as String? ?? '').trim(),
    email: (o['email'] as String? ?? '').trim(),
    about: about,
  );
}

/// What to search GitHub for, per field. Companies name themselves after what they make.
const githubTerms = {
  Interest.game: ['game', 'games', 'studio'],
  Interest.mobile: ['apps', 'mobile'],
  Interest.web: ['web', 'digital'],
  Interest.backend: ['technologies', 'software'],
  Interest.data: ['ai', 'analytics'],
  Interest.design: ['design', 'creative'],
  Interest.devops: ['cloud', 'infra'],
  Interest.security: ['security', 'cyber'],
  Interest.qa: ['testing', 'qa'],
  Interest.product: ['labs'],
  Interest.marketing: ['media', 'digital'],
  Interest.business: ['solutions'],
};

const _famous = [
  'google', 'microsoft', 'amazon', 'meta', 'apple', 'netflix', 'adobe', 'oracle', 'ibm', 'intel', 'nvidia', 'cisco',
  'samsung', 'infosys', 'tcs', 'wipro', 'accenture', 'deloitte', 'capgemini', 'cognizant', 'hcl', 'tech mahindra',
  'flipkart', 'swiggy', 'zomato', 'paytm', 'razorpay', 'cred', 'groww', 'meesho', 'phonepe', 'reliance', 'jio',
  'tata', 'qualcomm', 'salesforce', 'uber', 'stripe', 'databricks', 'openai', 'anthropic', 'freshworks', 'rubrik',
  'american express', 'electronic arts', 'red hat', 'redhat', 'siemens', 'ntt data', 'virtusa', 'kpmg', 'ey', 'pwc',
];

/// Big brands don't read cold emails from students; their inboxes are queues.
bool isFamous(String company) {
  final c = cleanCompany(company).toLowerCase();
  return _famous.any((f) => RegExp('\\b${RegExp.escape(f)}\\b').hasMatch(c));
}

/// Small companies from the feed, the ones closest to what the student wants first.
List<ColdTarget> coldTargets(List<JobListing> jobs, StudentProfile s) {
  final byCompany = <String, List<JobListing>>{};
  for (final j in jobs) {
    final c = cleanCompany(j.company);
    if (c.isEmpty || c == 'Company not named' || isFamous(c)) continue;
    (byCompany[c] ??= []).add(j);
  }
  final mine = {for (final n in s.interests) ?interestByName(n)};
  final targets = [
    for (final e in byCompany.entries)
      ColdTarget(
        e.key,
        {for (final j in e.value) j.title}.take(3).toList(),
        {for (final j in e.value) sourceLabel(j)},
        {for (final j in e.value) ...interestsOf(j)},
        e.value.first,
      ),
  ];
  int score(ColdTarget t) => t.fields.where(mine.contains).length * 3 + t.roles.length;
  return targets..sort((a, b) => score(b).compareTo(score(a)));
}

/// Feed companies first (they're hiring right now), then startups and GitHub finds; one card per company.
/// [field] null = everything.
List<ColdTarget> mergeTargets(List<List<ColdTarget>> lists, {Interest? field}) {
  final seen = <String>{};
  return [
    for (final t in lists.expand((l) => l))
      if ((field == null || t.fields.contains(field)) && seen.add(cleanCompany(t.company).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''))) t,
  ];
}

// ───────────────────────── Holes on a public website ─────────────────────────

/// Something a visitor can see on their site, phrased for the app ([title]) and for the email ([pitch]).
class Hole {
  const Hole(this.title, this.pitch);
  final String title;
  final String pitch;
}

const _genericTitles = {'', 'home', 'react app', 'vite + react', 'vite + react + ts', 'document', 'untitled', 'my app', 'next.js', 'index'};

/// A meta tag's content, whichever order its attributes come in. Null if the tag isn't there.
String? _meta(String html, String key) {
  final m = RegExp(
    '<meta[^>]+(?:name|property)=["\']$key["\'][^>]*content=["\']([^"\']*)["\']|<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:name|property)=["\']$key["\']',
    caseSensitive: false,
  ).firstMatch(html);
  return m == null ? null : (m.group(1) ?? m.group(2) ?? '').trim();
}

/// What they say they do (meta description), for the student to read before writing. Never quoted in the email.
String siteDescription(String html) {
  final d = _meta(html, 'description') ?? _meta(html, 'og:description') ?? '';
  return d.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"').trim();
}

/// The visible problems on one homepage, most useful first. [httpsOk] null = couldn't tell.
List<Hole> auditPage(String html, {int? loadMs, bool? httpsOk, List<String> brokenLinks = const [], int? year}) {
  final holes = <Hole>[];
  if (brokenLinks.isNotEmpty) {
    final n = brokenLinks.length;
    holes.add(Hole('$n broken link${n == 1 ? '' : 's'} on the homepage (${brokenLinks.first})',
        '${n == 1 ? 'a link' : '$n links'} on your homepage lead to an error page (${brokenLinks.first})'));
  }
  if (loadMs != null && loadMs > 3000) {
    final secs = (loadMs / 1000).toStringAsFixed(1);
    holes.add(Hole('Slow homepage: ${secs}s to load', 'your homepage took about ${secs}s to load on my phone'));
  }
  if (html.isNotEmpty && !RegExp(r'<meta[^>]+name=["' "'" r']viewport', caseSensitive: false).hasMatch(html)) {
    holes.add(const Hole('Not set up for phones (no viewport tag)', "the site isn't set up for phones, so it shows zoomed out on mobile"));
  }
  if (httpsOk == false) {
    holes.add(const Hole('No HTTPS redirect', 'the site still opens over plain http:// instead of redirecting to https'));
  }
  final title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1)?.trim();
  if (html.isNotEmpty && (title == null || _genericTitles.contains(title.toLowerCase()))) {
    holes.add(title == null || title.isEmpty
        ? const Hole('Page has no title', 'the homepage has no title, so the browser tab and Google results are blank')
        : Hole('Browser tab says "$title"', 'the browser tab still says "$title"'));
  }
  final noAlt = RegExp(r'<img\b(?![^>]*\balt=)[^>]*>', caseSensitive: false).allMatches(html).length;
  if (noAlt >= 3) holes.add(Hole('$noAlt images without alt text', '$noAlt images have no alt text, so screen readers and Google skip them'));
  if (html.isNotEmpty && _meta(html, 'og:image') == null) {
    holes.add(const Hole('No link preview image', 'links to your site shared on WhatsApp or LinkedIn show no preview image'));
  }
  if (html.isNotEmpty && (_meta(html, 'description') ?? '').isEmpty) {
    holes.add(const Hole('No search description', 'the homepage has no meta description, so Google shows a random snippet'));
  }
  final y = year ?? DateTime.now().year;
  final c = RegExp(r'(?:©|&copy;|copyright)\s*(?:(?:19|20)\d{2}\s*[-–]\s*)?((?:19|20)\d{2})', caseSensitive: false).firstMatch(html);
  final cy = int.tryParse(c?.group(1) ?? '');
  if (cy != null && cy < y - 1) holes.add(Hole('Footer says © $cy', 'the footer still says © $cy'));
  return holes;
}

// ───────────────────────── The cold email ─────────────────────────

/// Everything the student picked on the target screen.
class ColdBrief {
  const ColdBrief({
    required this.company,
    this.domain,
    this.contact,
    this.holes = const [],
    this.ownNote = '',
    this.field,
  });
  final String company;
  final String? domain;
  final SiteContact? contact;
  final List<Hole> holes; // the ones they ticked
  final String ownNote; // something they noticed themselves (beats any automated check)
  final Interest? field;
}

Pitch buildColdPitch(StudentProfile s, ColdBrief b, List<Project> projects, {bool resumeAttached = false}) {
  final first = s.name.split(' ').first;
  final person = b.contact?.name.split(' ').first ?? '';
  final greet = person.isNotEmpty && b.contact!.role != ContactRole.general ? 'Hi $person,' : 'Hi ${b.company} team,';
  final field = b.field == null ? '' : ', ideally on ${b.field!.label.toLowerCase()}';
  final top = projects.firstOrNull;
  final where = b.domain == null ? '' : ' (${shortUrl(b.domain!)})';

  final noticed = b.ownNote.trim().isNotEmpty
      ? "While using your product I noticed ${b.ownNote.trim().replaceAll(RegExp(r'[.\s]+$'), '')}. I'd love to help fix things like that."
      : b.holes.isEmpty
          ? ''
          : 'While going through your site I noticed ${andList(b.holes.take(2).map((h) => h.pitch).toList())}. '
              "Small things, but I'd be happy to fix them as a first task, no strings attached.";

  final contact = [s.phone, s.email].where((e) => e.isNotEmpty).join(' · ');
  final links = [s.linkedin, s.github.isNotEmpty ? s.github : s.portfolio]
      .where((e) => e.isNotEmpty && (top == null || shortUrl(e) != shortUrl(top.url)))
      .map(shortUrl)
      .join(' · ');
  final oneLiner = top == null || top.oneLiner.length > 60 ? '' : top.oneLiner;

  final body = [
    greet,
    "I'm $first, ${studentLine(s)}. I came across ${b.company}$where and wanted to ask whether you'd take on an intern$field.",
    noticed,
    if (top != null) "The project I'm proudest of is ${top.name}${oneLiner.isEmpty ? '' : ', $oneLiner'}. ${whereToSee(Project(id: top.id, name: top.name, url: cleanUrl(top.url), kind: top.kind))}",
    [if (resumeAttached) "I've attached my resume.", 'Would you be open to a 10-minute call this week?'].join(' '),
    ['Thanks for your time,', s.name, if (contact.isNotEmpty) contact, if (links.isNotEmpty) links].join('\n'),
  ].where((p) => p.trim().isNotEmpty).join('\n\n');
  final subject = '${b.field == null ? 'Internship' : '${b.field!.label} internship'} enquiry - ${s.name}';
  return Pitch(subject, body);
}
