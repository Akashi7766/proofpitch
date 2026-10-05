import 'engines.dart';
import 'insights.dart' show roleOf, Role;
import 'models.dart';

// ───────────────────────── Who's reading? ─────────────────────────

class PersonaGuess {
  const PersonaGuess(this.persona, this.companyType, this.reasons);
  final Persona persona;
  final String companyType;
  final List<String> reasons;
}

const _startupSignals = [
  'startup', 'start-up', 'early-stage', 'early stage', 'pre-seed', 'seed round', 'seed-funded', 'series a', 'founding',
  'small team', 'fast-paced', 'wear many hats', 'scrappy', 'y combinator', 'bootstrapped', 'zero to one', '0 to 1',
  'ship fast', 'move fast', 'ownership from day one', 'founder',
];
const _hrSignals = [
  'fortune 500', 'global offices', 'equal opportunity', 'equal employment', 'talent acquisition', 'benefits include',
  'hr team', 'human resources', 'recruitment process', 'selection process', 'interview rounds', 'nasdaq', 'nyse',
];
const _techSignals = [
  'code review', 'system design', 'architecture', 'distributed systems', 'open source', 'github', 'tech stack',
  'our stack', 'data structures', 'algorithms', 'unit tests', 'ci/cd', 'scalab', 'apis',
];
const _designSignals = [
  'figma', 'user experience', 'design system', 'prototyp', 'pixel', 'craft', 'product sense', 'user research',
  'interaction design', 'visual design', 'delightful',
];
const _bigCompanies = [
  'google', 'microsoft', 'amazon', 'meta', 'apple', 'netflix', 'databricks', 'stripe', 'uber', 'airbnb', 'coinbase',
  'robinhood', 'cloudflare', 'rubrik', 'palantir', 'openai', 'anthropic', 'spotify', 'reddit', 'discord', 'duolingo',
  'paytm', 'razorpay', 'phonepe', 'flipkart', 'zomato', 'swiggy', 'meesho', 'groww', 'cred', 'druva', 'freshworks',
  'adobe', 'oracle', 'salesforce', 'ibm', 'intel', 'nvidia', 'samsung', 'infosys', 'tcs', 'wipro', 'accenture',
  'deloitte', 'kpmg', 'capgemini', 'cognizant', 'hcl', 'tech mahindra', 'reliance', 'jio', 'tata',
];

/// Reads the post and company to decide whose inbox this lands in. Defaults to a general recruiter.
PersonaGuess guessPersona(JobListing j) {
  final t = '${j.title}\n${j.description}'.toLowerCase();
  final co = j.company.toLowerCase();
  final score = {for (final p in Persona.values) p: 0};
  final why = {for (final p in Persona.values) p: <String>[]};
  void add(Persona p, int pts, String reason) {
    score[p] = score[p]! + pts;
    why[p]!.add(reason);
  }

  final big = _bigCompanies.any((b) => RegExp(r'\b' + b + r'\b').hasMatch(co));
  if (big) add(Persona.recruiter, 3, 'large, well-known company');
  if (detectChannel(j.applyTarget) == Channel.enterpriseAts) add(Persona.recruiter, 2, 'corporate hiring portal');
  if (j.id.startsWith('us-')) add(Persona.recruiter, 1, 'applications go through Unstop');
  for (final s in _hrSignals) {
    if (t.contains(s)) add(Persona.recruiter, 1, '"$s"');
  }

  for (final s in _startupSignals) {
    if (t.contains(s)) add(Persona.founder, 1, '"$s"');
  }
  if (detectChannel(j.applyTarget) == Channel.directEmail) add(Persona.founder, 2, 'applies straight to an inbox');
  if (j.id.startsWith('us-') && !big) add(Persona.founder, 1, 'smaller company');

  final role = roleOf(j.title);
  if (role == Role.engineering || role == Role.mobile || role == Role.data) add(Persona.engineer, 1, '${role.label.toLowerCase()} role');
  for (final s in _techSignals) {
    if (t.contains(s)) add(Persona.engineer, 1, '"$s"');
  }

  if (role == Role.design || role == Role.product) add(Persona.designLead, 4, '${role.label.toLowerCase()} role');
  for (final s in _designSignals) {
    if (t.contains(s)) add(Persona.designLead, 1, '"$s"');
  }

  // Ties go to the earlier (more general) reader: recruiter first.
  final best = Persona.values.reduce((a, b) => score[b]! > score[a]! ? b : a);
  if (score[best] == 0) {
    return const PersonaGuess(Persona.recruiter, 'General hiring team', ['no clear signals, so writing for anyone']);
  }
  return PersonaGuess(
    best,
    switch (best) {
      Persona.recruiter => 'Hiring team / HR',
      Persona.founder => 'Early-stage startup',
      Persona.engineer => 'Engineering-led team',
      Persona.designLead => 'Design / product-led team',
    },
    why[best]!.take(3).toList(),
  );
}

// ───────────────────────── Emails on a company's own site ─────────────────────────

const _junkEmail = [
  'example', 'sentry', 'wixpress', 'domain.com', 'email.com', 'company.com', 'yourname', 'yourcompany', 'test@', 'user@',
  'name@', 'john', 'jane', 'xyz.com', 'abc.com',
];

/// On a small company's own site, support@/sales@ often reach the founder, so they're kept (ranked last).
const _notOnSite = [
  'privacy', 'accommodation', 'accessibility', 'legal', 'security', 'noreply', 'no-reply', 'eeo', 'press', 'media',
  'abuse', 'gdpr', 'dpo', 'compliance', 'billing', 'grievance', 'nodal', 'unsubscribe',
];

/// Who an inbox reaches. Lower = closer to the person who decides on an intern.
enum ContactRole {
  hiring('Hiring / HR'),
  founder('Founder'),
  techLead('Tech lead'),
  person('Team member'),
  general('General inbox'),
  support('Support');

  const ContactRole(this.label);
  final String label;
}

class SiteContact {
  const SiteContact(this.email, this.role, {this.name = '', this.guessed = false});
  final String email;
  final ContactRole role;
  final String name;

  /// Built from the site's address pattern (kartik@ → founder's first name), not seen on the page.
  final bool guessed;

  String get label => '${role.label}${name.isEmpty ? '' : ' · $name'}';
}

final _emailRe = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}');
final _hiringCtx = RegExp(r'\b(hr|human resources?|recruit\w*|talent|hiring|careers?|jobs|internships?|people (team|ops))\b', caseSensitive: false);
final _founderCtx = RegExp(r'\b(co-?founder|founder|ceo|chief executive|managing director|owner|proprietor)\b', caseSensitive: false);
final _techCtx = RegExp(r'\b(cto|chief technology|head of (engineering|technology|tech)|engineering manager|tech lead|vp,? engineering)\b', caseSensitive: false);
final _generalLocal = RegExp(r'^(info|contact|hello|hi|team|admin|office|enquir|inquir|connect|mail|business|partner)');
final _supportLocal = RegExp(r'^(support|sales|help|care|service|order)');
final _hiringLocal = RegExp(r'^(careers?|jobs|hr|hiring|talent|recruit\w*|interns?|internships?|people|apply)$');

/// A page as plain text, keeping mailto addresses visible so nearby words ("HR:", "Founder") can label them.
String _pageText(String html) => html
    .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), ' ')
    .replaceAll('&#64;', '@')
    .replaceAll('%40', '@')
    // Addresses often live only in attributes (mailto:, Gmail "compose" links): keep them as text.
    .replaceAllMapped(RegExp(r'<[^>]+>'), (m) => ' ${_emailRe.allMatches(m[0]!).map((e) => e[0]).join(' ')} ')
    .replaceAll('&#46;', '.')
    .replaceAll('&amp;', '&')
    .replaceAll('&nbsp;', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

ContactRole _roleOf(String local, String before, String after) {
  final parts = local.split(RegExp(r'[._+-]'));
  if (parts.any(_hiringLocal.hasMatch)) return ContactRole.hiring; // careers@, roshan.hr@
  if (_supportLocal.hasMatch(local)) return ContactRole.support;
  if (_generalLocal.hasMatch(local)) return _hiringCtx.hasMatch(before) ? ContactRole.hiring : ContactRole.general;
  // A personal address: the words just before it say who it is ("Founder & CEO — kartik@…").
  if (_hiringCtx.hasMatch(before) || _hiringCtx.hasMatch(after)) return ContactRole.hiring;
  if (_techCtx.hasMatch(before)) return ContactRole.techLead;
  if (_founderCtx.hasMatch(before) || _founderCtx.hasMatch(after)) return ContactRole.founder;
  return ContactRole.person;
}

final _nameRe = RegExp(r"\b([A-Z][a-z]{1,15}(?:\s[A-Z][a-z]{1,15}){1,3})\b");

const _notNameStart = {
  'email', 'mail', 'call', 'contact', 'meet', 'our', 'the', 'about', 'team', 'write', 'reach', 'linkedin', 'twitter',
  'read', 'view', 'more', 'join', 'hello', 'dear', 'head', 'chief', 'founder', 'co', 'ceo', 'cto', 'hr', 'and',
};
const _notNameEnd = {
  'co', 'founder', 'cofounder', 'ceo', 'cto', 'head', 'chief', 'hr', 'director', 'managing', 'vp', 'the', 'email', 'and', 'president',
  'secretary', 'manager', 'lead', 'officer', 'member', 'intern', 'vice', 'partner', 'advisor', 'mentor', 'coordinator', 'executive',
};

/// "Email Meera Iyer Co" (link label + name + start of "Co-founder") → "Meera Iyer". Null unless 2+ name words remain.
String? _cleanName(String raw) {
  final w = raw.split(' ');
  while (w.isNotEmpty && _notNameStart.contains(w.first.toLowerCase())) {
    w.removeAt(0);
  }
  while (w.isNotEmpty && _notNameEnd.contains(w.last.toLowerCase())) {
    w.removeLast();
  }
  return w.length >= 2 && w.length <= 3 ? w.join(' ') : null;
}
final _titleRe = RegExp(
    r'(co-?founder|founder|ceo|cto|chief (?:executive|technology) officer|head of (?:hr|people|talent|engineering|technology)|hr manager|talent acquisition|hr|human resources|managing director)',
    caseSensitive: false);

/// "Kartik Sharma, Co-founder & CEO" and "CEO: Kartik Sharma" on team/about pages.
List<(String, ContactRole)> _peopleIn(String text) {
  // "Co-founder, CTO": the more specific title wins (HR, then tech, then founder).
  ContactRole roleFor(String t) {
    if (RegExp(r'\b(hr|human resources?|talent|people)\b', caseSensitive: false).hasMatch(t)) return ContactRole.hiring;
    if (RegExp(r'\b(cto|chief technology|engineering|technology)\b', caseSensitive: false).hasMatch(t)) return ContactRole.techLead;
    return ContactRole.founder;
  }


  // Names are case-sensitive (capitalised words); titles aren't ("CEO", "Co-Founder", "co-founder").
  final titleAfter = RegExp(r'^\s*[,|\-–—:(]?\s*(?:and\s+|&\s+)?' + _titleRe.pattern, caseSensitive: false);
  final titleBefore = RegExp(_titleRe.pattern + r'\s*[,|\-–—:]?\s*$', caseSensitive: false);
  final out = <(String, ContactRole)>[];
  for (final m in _nameRe.allMatches(text)) {
    // "Meera Iyer Co-founder": the name stops before the title starts.
    final name = _cleanName(m.group(1)!);
    if (name == null) continue;
    final end = m.start + m.group(1)!.indexOf(name) + name.length;
    final after = text.substring(end, (end + 45).clamp(0, text.length));
    final before = text.substring((m.start - 35).clamp(0, text.length), m.start);
    final a = titleAfter.firstMatch(after);
    final window = a != null ? after.substring(0, (a.end + 15).clamp(0, after.length)) : titleBefore.firstMatch(before)?.group(0);
    if (window != null && !out.any((p) => p.$1 == name)) out.add((name, roleFor(window)));
  }
  return out;
}

/// Inboxes on a company's own site, each labelled with who reads it, the person who'd hire you first.
/// When the site shows how personal addresses look (kartik@, kartik.s@), the founder's/HR's is guessed and flagged.
List<SiteContact> contactsInHtml(String html, {String domain = '', bool techRole = false}) {
  final text = _pageText(html);
  final masked = text.replaceAllMapped(_emailRe, (m) => ' ' * m[0]!.length); // same length: indices line up
  final found = <String, SiteContact>{};
  for (final m in _emailRe.allMatches(text)) {
    final e = m.group(0)!.toLowerCase();
    final local = e.split('@').first;
    if (RegExp(r'\.(png|jpe?g|gif|webp|svg|css|js)$').hasMatch(e) || RegExp(r'@\d+x\.').hasMatch(e)) continue;
    if (_junkEmail.any(e.contains) || _notOnSite.any(local.contains) || found.containsKey(e)) continue;
    // Neighbouring addresses ("roshan.hr@…") must not label this one.
    final before = masked.substring((m.start - 80).clamp(0, text.length), m.start);
    final after = masked.substring(m.end, (m.end + 25).clamp(0, text.length));
    final name = [for (final n in _nameRe.allMatches(before)) ?_cleanName(n.group(1)!)].lastOrNull ?? '';
    final role = _roleOf(local, before, after);
    final personal = role == ContactRole.founder || role == ContactRole.techLead || role == ContactRole.person;
    found[e] = SiteContact(e, role, name: personal && local.contains(name.split(' ').first.toLowerCase()) ? name : '');
  }

  // Guess the decision-makers' addresses from the site's own pattern.
  if (domain.isNotEmpty) {
    final mine = found.values.where((c) => c.email.endsWith('@$domain') && c.role.index >= ContactRole.founder.index && c.role != ContactRole.general && c.role != ContactRole.support);
    final dotted = mine.where((c) => RegExp(r'^[a-z]+\.[a-z]+$').hasMatch(c.email.split('@').first)).length;
    final plain = mine.where((c) => RegExp(r'^[a-z]{3,12}$').hasMatch(c.email.split('@').first)).length;
    if (dotted + plain > 0) {
      for (final (name, role) in _peopleIn(text)) {
        final w = name.toLowerCase().split(' ');
        final email = '${dotted > plain ? '${w.first}.${w.last}' : w.first}@$domain';
        // Already reachable (roshan.hr@ is Roshan): don't add a second, guessed address for the same person.
        if (found.values.any((c) => c.email == email || c.name == name || c.email.split('@').first.split(RegExp(r'[._+-]')).first == w.first)) continue;
        found[email] = SiteContact(email, role, name: name, guessed: true);
      }
    }
    // No pattern to copy: generic inboxes (careers@) stay unnamed rather than borrow a stranger's name.
  }

  int rank(SiteContact c) {
    final r = switch (c.role) {
      ContactRole.hiring => 0,
      ContactRole.techLead => techRole ? 1 : 2,
      ContactRole.founder => 1,
      ContactRole.person => 3,
      ContactRole.general => 4,
      ContactRole.support => 5,
    };
    return r * 2 + (c.guessed ? 1 : 0); // seen-on-page beats guessed within a role
  }

  final order = found.values.toList();
  return (order.indexed.toList()..sort((a, b) => rank(a.$2) != rank(b.$2) ? rank(a.$2).compareTo(rank(b.$2)) : a.$1.compareTo(b.$1)))
      .map((e) => e.$2)
      .take(4)
      .toList();
}

/// Just the addresses, best first.
List<String> emailsInHtml(String html) => contactsInHtml(html).take(3).map((c) => c.email).toList();

/// robots.txt check for `User-agent: *` (longest matching rule wins, like Google's).
bool robotsAllows(String robots, String path) {
  var inStar = false, lastWasAgent = false;
  final rules = <(bool, String)>[];
  for (final raw in robots.split('\n')) {
    final line = raw.split('#').first.trim();
    final i = line.indexOf(':');
    if (i < 0) continue;
    final key = line.substring(0, i).trim().toLowerCase(), val = line.substring(i + 1).trim();
    if (key == 'user-agent') {
      inStar = (lastWasAgent && inStar) || val == '*';
      lastWasAgent = true;
      continue;
    }
    lastWasAgent = false;
    if (inStar && (key == 'allow' || key == 'disallow') && val.isNotEmpty) rules.add((key == 'allow', val.replaceAll('*', '')));
  }
  (bool, String)? best;
  for (final r in rules) {
    if (path.startsWith(r.$2) && (best == null || r.$2.length > best.$2.length)) best = r;
  }
  return best?.$1 ?? true;
}

// ───────────────────────── Finding the official website ─────────────────────────

final _legalAndFiller = RegExp(
  r'\b(private|limited|pvt|ltd|llp|inc|llc|opc|corp|co|technologies|technology|tech|solutions|services|foundation|labs?|'
  r'india|software|consultancy|consulting|global|ventures|group|systems|innovations?|enterprises?|the)\b',
  caseSensitive: false,
);

/// The words that actually name the company: "Shanks Code Private Limited" → [shanks, code].
List<String> coreWords(String company) {
  final core = _words(company.replaceAll(_legalAndFiller, ' '));
  return core.isNotEmpty ? core : _words(company);
}

/// Likely homepages for a company, most likely first: full name, then core name, then first word.
List<String> domainCandidates(String company) {
  // "Hoogway.ai" already is a domain.
  final named = RegExp(r'\b([a-z0-9-]+\.(?:com|in|co\.in|io|ai|co|app|org|dev|tech))\b', caseSensitive: false).firstMatch(company)?.group(1);
  if (named != null) return [named.toLowerCase()];
  final all = _words(company.replaceAll(RegExp(r"[.,'’]"), ''));
  final core = coreWords(company);
  if (core.isEmpty) return const []; // "Pvt Ltd", emoji-only names: nothing to guess from
  final bases = <String>{
    core.join(),
    all.join(),
    if (core.length > 1) core.join('-'),
    if (core.first.length >= 5) core.first,
  }.where((b) => b.length >= 4);
  const tlds = ['.com', '.in', '.co.in', '.io', '.ai', '.co', '.org'];
  return [for (final b in bases) for (final t in tlds) '$b$t'];
}

/// How sure we are a fetched page is this company's site: 2 = title names it fully, 1 = by its main word, 0 = no.
int siteScore(String company, String html) {
  final title = (RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html)?.group(1) ?? '').toLowerCase();
  final og = (RegExp(r'''og:(?:site_name|title)["']\s+content=["']([^"']+)''', caseSensitive: false).firstMatch(html)?.group(1) ?? '').toLowerCase();
  final where = '$title $og'.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final core = coreWords(company);
  if (core.isEmpty) return 0;
  if (core.every(where.contains)) return 2;
  return core.first.length >= 5 && where.contains(core.first) ? 1 : 0;
}

List<String> _words(String s) => RegExp(r'[a-z0-9]+').allMatches(s.toLowerCase()).map((m) => m[0]!).toList();

/// Picks the domain from Clearbit suggestions only when the name really matches (not "Grow Weed Easy" for "Groww").
/// Exact name first; otherwise one name must be the other plus whole extra words ("Acme" ↔ "Acme Labs").
String? domainFromSuggest(String company, List suggestions) {
  final want = _words(company);
  if (want.isEmpty) return null;
  final named = [
    for (final s in suggestions)
      if (s is Map && s['domain'] is String) (_words(s['name'] ?? ''), s['domain'] as String),
  ];
  bool prefix(List<String> a, List<String> b) => a.length < b.length && a.join(' ') == b.take(a.length).join(' ');
  for (final (got, domain) in named) {
    if (got.join(' ') == want.join(' ')) return domain;
  }
  for (final (got, domain) in named) {
    // Single short words ("Acme") are too ambiguous to extend.
    if (got.isNotEmpty && (prefix(got, want) || (want.join().length >= 5 && prefix(want, got)))) return domain;
  }
  return null;
}

// ───────────────────────── How to reach them ─────────────────────────

enum RouteKind { email, guessedEmail, applyPage, linkedin, x, website, search }

class ContactRoute {
  const ContactRoute(this.kind, this.emoji, this.label, this.detail, this.target, {this.verified = true});
  final RouteKind kind;
  final String emoji;
  final String label;
  final String detail;

  /// Email address for email kinds, URL otherwise.
  final String target;
  final bool verified;

  bool get isEmail => kind == RouteKind.email || kind == RouteKind.guessedEmail;

  /// Opening a website/search is research, not an application.
  bool get countsAsApplication => kind != RouteKind.website && kind != RouteKind.search;
}

const _notForApplicants = [
  'privacy', 'accommodation', 'accommodations', 'accessibility', 'legal', 'security', 'noreply', 'no-reply', 'support',
  'eeo', 'benefits', 'press', 'media', 'abuse', 'gdpr', 'dpo', 'compliance', 'billing', 'sales',
];
const _hiringInbox = ['careers', 'jobs', 'hr', 'hiring', 'talent', 'recruit', 'intern', 'people', 'apply', 'founder', 'ceo', 'hello'];

const _notCompanyHosts = [
  'greenhouse.io', 'lever.co', 'ashbyhq.com', 'smartrecruiters.com', 'myworkdayjobs.com', 'taleo.net', 'icims.com',
  'successfactors.com', 'linkedin.com', 'twitter.com', 'x.com', 'facebook.com', 'instagram.com', 'youtube.com',
  'glassdoor.com', 'google.com', 'goo.gl', 'bit.ly', 'unstop.com', 'cloudfront.net', 'w3.org', 'github.com',
  'medium.com', 'notion.site', 'forms.gle', 'wellfound.com', 'angel.co', 'crunchbase.com', 'eeoc.gov', 'dol.gov',
  // Job aggregators and link shorteners that Telegram channels route through: never the company's own site.
  'offcampusjobs4u.com', 'acciojob.com', 'tinyurl.com', 'lnkd.in', 'shorturl.at', 'cutt.ly', 'rb.gy', 'docs.google.com',
  'oraclecloud.com', 'naukri.com', 'internshala.com', 'indeed.com', 'foundit.in', 'freshersworld.com', 'cuvette.tech',
  'whatsapp.com', 't.me', 'telegram.me',
];

String _root(String host) {
  final parts = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '').split('.');
  if (parts.length <= 2) return parts.join('.');
  // careers.acme.co.in → acme.co.in ; jobs.acme.com → acme.com
  final secondLevel = {'co', 'com', 'org', 'net', 'ac', 'gov', 'edu'}.contains(parts[parts.length - 2]);
  return parts.sublist(parts.length - (secondLevel ? 3 : 2)).join('.');
}

bool _isCompanyHost(String host) => host.isNotEmpty && !_notCompanyHosts.any((h) => host == h || host.endsWith('.$h'));

/// The company's own domain, if the post or apply link gives it away.
String? companyDomain(JobListing j) {
  final emails = RegExp(r'[\w.+-]+@([\w-]+(?:\.[\w-]+)+)').allMatches('${j.applyTarget} ${j.description}');
  for (final m in emails) {
    final h = m.group(1)!.toLowerCase();
    if (_isCompanyHost(h) && !RegExp(r'gmail|yahoo|outlook|hotmail|proton|icloud').hasMatch(h)) return _root(h);
  }
  for (final raw in [j.applyTarget, ...RegExp(r'https?://[^\s)"<>]+').allMatches(j.description).map((m) => m.group(0)!)]) {
    final host = Uri.tryParse(raw.startsWith('http') ? raw : 'https://$raw')?.host ?? '';
    if (host.contains('.') && _isCompanyHost(host)) return _root(host);
  }
  return null;
}

String _enc(String s) => Uri.encodeComponent(s);

/// Every sensible way to reach a human, best first. Real emails beat guesses; guesses are labelled.
/// [siteContacts] come from the company's own website, already ranked: the person who hires first.
List<ContactRoute> contactRoutes(JobListing j, Persona p, {List<SiteContact> siteContacts = const [], String? siteDomain}) {
  final routes = <ContactRoute>[];
  final seen = <String>{};

  void email(String e, String why) {
    final addr = e.toLowerCase().replaceFirst('mailto:', '');
    final local = addr.split('@').first;
    if (!seen.add(addr) || _notForApplicants.any((n) => local.contains(n))) return;
    routes.add(ContactRoute(RouteKind.email, '📧', addr, why, addr));
  }

  if (detectChannel(j.applyTarget) == Channel.directEmail) email(emailOf(j.applyTarget), 'Their listed application inbox');
  final found = [for (final m in RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+').allMatches(j.description)) m.group(0)!];
  // Hiring-looking inboxes first.
  found.sort((a, b) => (_hiringInbox.any(b.startsWith) ? 1 : 0).compareTo(_hiringInbox.any(a.startsWith) ? 1 : 0));
  for (final e in found) {
    email(e.replaceAll(RegExp(r'[.,;]+$'), ''), 'Mentioned in the job post');
  }

  for (final c in siteContacts) {
    if (!seen.add(c.email)) continue;
    routes.add(c.guessed
        ? ContactRoute(RouteKind.guessedEmail, '🎯', c.email, '${c.label} — guessed from their email pattern', c.email, verified: false)
        : ContactRoute(RouteKind.email, c.role.index <= ContactRole.techLead.index ? '🎯' : '📧', c.email, '${c.label} — on their website', c.email));
  }

  if (detectChannel(j.applyTarget) != Channel.directEmail && j.applyTarget.isNotEmpty) {
    final host = Uri.tryParse(j.applyTarget)?.host ?? '';
    routes.add(ContactRoute(RouteKind.applyPage, '📝', 'Official apply page', host.isEmpty ? 'Paste your pitch as the cover note' : '$host · paste your pitch as the cover note', j.applyTarget));
  }

  final who = switch (p) {
    Persona.recruiter => 'HR recruiter',
    Persona.founder => 'founder',
    Persona.engineer => 'engineering manager',
    Persona.designLead => 'design lead',
  };
  routes.add(ContactRoute(
    RouteKind.linkedin,
    '💼',
    'LinkedIn: ${cleanCompany(j.company)} $who',
    'Find the person, send a ≤300-char connection note',
    'https://www.linkedin.com/search/results/people/?keywords=${_enc('${cleanCompany(j.company)} $who')}',
  ));
  if (p == Persona.founder) {
    routes.add(ContactRoute(RouteKind.x, '𝕏', 'X / Twitter: ${cleanCompany(j.company)} founder', 'Founders often reply to short DMs',
        'https://x.com/search?q=${_enc('${cleanCompany(j.company)} founder')}&f=user'));
  }

  final domain = companyDomain(j) ?? siteDomain;
  if (domain != null) {
    if (!routes.any((r) => r.isEmail)) {
      routes.add(ContactRoute(RouteKind.guessedEmail, '❓', 'careers@$domain', 'Common hiring inbox — a guess, may bounce',
          'careers@$domain', verified: false));
    }
    routes.add(ContactRoute(RouteKind.website, '🌐', domain, 'Their official website — team, contact and careers pages', 'https://$domain'));
  } else {
    routes.add(ContactRoute(RouteKind.search, '🔎', 'Find ${cleanCompany(j.company)}\'s website', 'Search for their site and contact page',
        'https://www.google.com/search?q=${_enc('${cleanCompany(j.company)} official website careers contact')}'));
  }
  return routes;
}

// ───────────────────────── Short notes for DMs ─────────────────────────

const linkedInNoteLimit = 300;

/// Connection notes on LinkedIn are capped at 300 characters, so this is a different pitch, not a trimmed one.
String shortNote(StudentProfile s, JobListing j, List<Project> projects, Persona p) {
  final first = s.firstName;
  final top = projects.isEmpty ? null : orderForPersona(projects, p).first;
  final yr = s.graduationYear == null ? '' : " '${s.graduationYear! % 100}";
  final me = [if (s.degree.isNotEmpty) '${s.degree}$yr', if (s.college.isNotEmpty) s.college].join(', ');
  final proof = top == null ? '' : ' I built ${top.name}${top.oneLiner.isEmpty ? '' : ' (${top.oneLiner})'}: ${top.url}.';
  final ask = switch (p) {
    Persona.recruiter => ' Could I send you my resume?',
    Persona.founder => ' Happy to do a small trial task.',
    Persona.engineer => ' Would value 10 minutes of your time.',
    Persona.designLead => ' Would love to show you a quick walkthrough.',
  };
  var note = 'Hi! I\'m $first${me.isEmpty ? '' : ', $me'}. Applying for ${j.title} at ${cleanCompany(j.company)}.$proof$ask';
  if (note.length > linkedInNoteLimit && top != null) {
    note = 'Hi! I\'m $first. Applying for ${j.title} at ${cleanCompany(j.company)}. I built ${top.name}: ${top.url}.$ask';
  }
  return note.length <= linkedInNoteLimit ? note : '${note.substring(0, linkedInNoteLimit - 1)}…';
}

// ───────────────────────── Shared posts (LinkedIn, Reddit, WhatsApp…) ─────────────────────────

class SharedLead {
  const SharedLead({this.company = '', this.title = '', this.target = '', this.location = '', this.description = ''});
  final String company;
  final String title;
  final String target; // email or apply link
  final String location;
  final String description;
}

const _socialHosts = ['linkedin.com', 'lnkd.in', 'reddit.com', 'redd.it', 'x.com', 'twitter.com', 't.co', 'instagram.com', 'facebook.com', 'whatsapp.com', 'youtube.com'];
const _freeMail = ['gmail', 'yahoo', 'outlook', 'hotmail', 'proton', 'icloud', 'rediff'];

String _titleCaseWord(String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);

/// Best guess at a lead from a shared post. The student confirms it in the lead sheet, so guesses are fine.
SharedLead leadFromText(String text) {
  final emails = [for (final m in RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[a-z]{2,}', caseSensitive: false).allMatches(text)) m.group(0)!.toLowerCase()]
      .where((e) => !_notForApplicants.any(e.split('@').first.contains))
      .toList()
    ..sort((a, b) => (_hiringInbox.any(b.startsWith) ? 1 : 0).compareTo(_hiringInbox.any(a.startsWith) ? 1 : 0));
  final urls = [for (final m in RegExp(r'https?://[^\s<>"）)]+').allMatches(text)) m.group(0)!.replaceAll(RegExp(r'[.,;!]+$'), '')];
  bool social(String u) {
    final h = Uri.tryParse(u)?.host ?? '';
    return _socialHosts.any((s) => h == s || h.endsWith('.$s'));
  }

  final apply = urls.where((u) => !social(u)).firstOrNull;
  final target = emails.firstOrNull ?? apply ?? urls.firstOrNull ?? '';

  // Company: a work email's domain, then "at/join/@ Company", then the apply link's host.
  // The post's own wording ("at Kukbit") reads better than a domain ("kukbitsl.in"), so it wins when the two agree.
  final work = emails.where((e) => !_freeMail.any(e.split('@').last.startsWith)).firstOrNull;
  final fromEmail = work == null ? '' : _titleCaseWord(work.split('@').last.split('.').first);
  final m = RegExp(r'''(?:\b[Aa]t|\b[Jj]oin|\b[Ww]ith|@)\s+([A-Z][\w&'’-]*(?:\.[a-z]\w*)?(?:\s+[A-Z][\w&'’-]*){0,3})''').firstMatch(text);
  final fromText = m?.group(1)?.replaceAll(RegExp(r'[.,]$'), '') ?? '';
  final agrees = fromText.isNotEmpty && fromEmail.toLowerCase().contains(_words(fromText).first);
  var company = fromEmail.isEmpty || agrees ? fromText : fromEmail;
  if (company.isEmpty && apply != null) {
    final host = Uri.tryParse(apply)?.host ?? '';
    if (_isCompanyHost(host)) company = _titleCaseWord(_root(host).split('.').first);
  }

  final role = RegExp(r'''([A-Z][\w+#/.&-]*(?:\s+[A-Z][\w+#/.&-]*){0,4}\s+(?:Intern(?:ship)?s?|Trainee|Developer|Engineer|Designer|Analyst))\b''')
      .firstMatch(text)
      ?.group(1);
  final remote = RegExp(r'\b(remote|work from home|wfh)\b', caseSensitive: false).hasMatch(text);
  return SharedLead(
    company: company,
    title: role ?? 'Internship',
    target: target,
    location: remote ? 'Remote' : '',
    description: text.trim(),
  );
}
