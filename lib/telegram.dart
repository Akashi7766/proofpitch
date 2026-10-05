import 'engines.dart';
import 'insights.dart' show payFromText;
import 'models.dart';
import 'outreach.dart' show leadFromText;

// ───────────────────────── Public Telegram channels ─────────────────────────
// Reads a channel's public web preview (t.me/s/<channel>: the page Telegram serves to anyone, no login;
// t.me has no robots.txt). Only channels the student chose, two pages (~40 posts) per refresh.
// Indian job channels post in a few house styles; each becomes a JobListing tagged with its channel.

class TelegramPage {
  const TelegramPage(this.jobs, this.oldestId);
  final List<JobListing> jobs;
  final int? oldestId; // for the next (older) page: ?before=<id>
}

/// "@goyalarsh", "t.me/goyalarsh", "https://t.me/s/goyalarsh/123" → "goyalarsh". Null if it isn't a channel name.
String? telegramName(String input) {
  final m = RegExp(r'^(?:https?://)?(?:t\.me/|telegram\.me/)?(?:s/)?@?([A-Za-z][A-Za-z0-9_]{3,31})(?:/\d+)?/?$').firstMatch(input.trim());
  return m?.group(1)?.toLowerCase();
}

// Links that are the channel promoting itself, not the job.
const _noiseHosts = [
  'whatsapp.com', 't.me', 'telegram.me', 'telegram.dog', 'instagram.com', 'youtube.com', 'youtu.be', 'facebook.com',
  'x.com', 'twitter.com',
];
final _urlRe = RegExp(r'https?://[^\s<>"）)\]]+');
final _emailRe = RegExp(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)*\.[a-z]{2,}', caseSensitive: false);

bool _isNoise(String url) {
  final u = Uri.tryParse(url);
  final h = (u?.host ?? '').toLowerCase().replaceFirst('www.', '');
  if (_noiseHosts.any((n) => h == n || h.endsWith('.$n'))) return true;
  // A LinkedIn *post* is someone talking about a job; linkedin.com/jobs/view is the job itself.
  return h.endsWith('linkedin.com') && !(u?.path.startsWith('/jobs') ?? false);
}

/// Channels love "𝗗𝗲𝗹𝗼𝗶𝘁𝘁𝗲" (Unicode maths letters) for bold; turn them back into plain letters.
String plainLetters(String s) => String.fromCharCodes(s.runes.map((r) {
      if (r >= 0x1D400 && r <= 0x1D6A3) {
        final off = (r - 0x1D400) % 52;
        return off < 26 ? 0x41 + off : 0x61 + off - 26;
      }
      if (r >= 0x1D7CE && r <= 0x1D7FF) return 0x30 + (r - 0x1D7CE) % 10;
      return r;
    }));

const _entities = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', '#39': "'", 'nbsp': ' ', '#036': r'$'};

String _postText(String html) {
  var t = html.replaceAllMapped(RegExp(r'<a\s[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>', caseSensitive: false), (m) {
    final label = m[2]!.replaceAll(RegExp(r'<[^>]+>'), '');
    return label.contains('http') ? label : '$label ${m[1]}';
  });
  t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n').replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAllMapped(RegExp(r'&(#?\w+);'), (m) {
    final e = m[1]!;
    if (_entities.containsKey(e)) return _entities[e]!;
    if (e.startsWith('#x')) return String.fromCharCode(int.tryParse(e.substring(2), radix: 16) ?? 32);
    if (e.startsWith('#')) return String.fromCharCode(int.tryParse(e.substring(1)) ?? 32);
    return m[0]!;
  });
  return plainLetters(t);
}

// The channel's own promo lines ("Join our WhatsApp", "Do share with your friends").
final _promoLine = RegExp(r'^\W*(join|do share|share with|follow us|subscribe|land your|for more (jobs|updates|opportunities))', caseSensitive: false);

/// One post can list several jobs ("📌 FarEye is hiring… 📌 VIR Softech is hiring…").
List<String> _blocks(String text) {
  final lines = [for (final l in text.split('\n')) if (!_promoLine.hasMatch(l) && !_urlRe.allMatches(l).any((u) => _isNoise(u[0]!) && l.trim().length - u[0]!.length < 40)) l];
  final starts = [
    for (final (i, l) in lines.indexed)
      if (l.trimLeft().startsWith('📌') || RegExp(r'\bis hiring\b', caseSensitive: false).hasMatch(l)) i,
  ];
  if (starts.length < 2) return [lines.join('\n').trim()];
  return [
    if (starts.first > 0 && lines.take(starts.first).join().trim().isNotEmpty) lines.take(starts.first).join('\n').trim(),
    for (final (k, s) in starts.indexed) lines.sublist(s, k + 1 < starts.length ? starts[k + 1] : lines.length).join('\n').trim(),
  ];
}

/// "Company Name : Rubrik" / "💼 Roles: Tech" / "Apply Link- https://…": value for the first matching key.
String? _label(String block, List<String> keys) {
  for (final l in block.split('\n')) {
    final m = RegExp(r'^[^A-Za-z0-9]*([A-Za-z0-9 ]{2,25}?)\s*(?::-|[:\-–])\s*(.+)$').firstMatch(l.trim());
    if (m != null && keys.contains(m.group(1)!.trim().toLowerCase())) return m.group(2)!.trim();
  }
  return null;
}

const _companyKeys = ['company', 'company name', 'organization', 'organisation', 'employer'];
const _roleKeys = ['role', 'roles', 'position', 'positions', 'designation', 'job role', 'job title', 'post', 'profile', 'opening'];
const _locationKeys = ['location', 'locations', 'job location', 'work location'];
const _payKeys = ['salary', 'stipend', 'ctc', 'package', 'compensation', 'pay'];
const _linkKeys = ['apply link', 'apply', 'apply here', 'apply now', 'link', 'link 1', 'registration link', 'job link'];

final _jobWords = RegExp(r'\b(hiring|intern|internship|recruitment|role|apply|opening|vacanc\w*|job|drive|trainee|position|batch)', caseSensitive: false);
// Courses, workshops and anything asking the student for money: never a job lead.
final _promo = RegExp(
  r'\b(workshop|webinar|masterclass|bootcamp|course|certification program|enrol+|free class|free report|download|waitlist|ai interview|prove your skills|registration fee|application fee|security deposit|pay (?:a |the )?fee|fees? (?:of|rs|₹|inr))',
  caseSensitive: false,
);

// Words that start a job title ("Software Engineering Intern"), so what's before them is the company.
final _roleStart = RegExp(
    r'^(software|senior|junior|jr|sr|data|frontend|front-end|backend|back-end|full|fullstack|sde|ai|ml|machine|graduate|associate|business|product|ui|ux|web|mobile|android|ios|flutter|react|python|java|devops|cloud|cyber|security|qa|test|marketing|sales|hr|content|graphic|research|summer|winter|intern|trainee|engineer|developer|analyst|designer)$',
    caseSensitive: false);
// A real role mentions a job; "MHk" or "Workday Developer Portal Waitlist" don't.
final _roleWord = RegExp(
    r'\b(intern\w*|trainee|engineer\w*|developer|dev|analyst|designer|manager|associate|sde\d*|executive|consultant|specialist|scientist|lead|architect|tester|qa|support|marketing|sales|hr|writer|editor|operations|apprentice\w*|fellow\w*|ambassador|programmer|technician|tech|non-tech|fde|roles?)\b',
    caseSensitive: false);
// Headline words that aren't a company ("FRESHERS HIRING | SOFTWARE DEVELOPER").
final _notACompany = RegExp(r'^(freshers?|urgent(ly)?|hot|new|latest|top|mega|off\s*campus|we are|we.re|now|bulk|massive|direct)\b', caseSensitive: false);

/// The part of "Bangalore | 2025-26 Grads" that's a place.
String _placeIn(Iterable<String> parts) => parts.firstWhere(
      (p) => p.isNotEmpty && !RegExp(r'\d|grads?\b|batch|freshers?|years?|lpa|month|₹|stipend|salary|apply', caseSensitive: false).hasMatch(p),
      orElse: () => '',
    );

/// Parses one t.me/s/CHANNEL page. Pure: easy to test against saved pages.
TelegramPage parseTelegramPage(String channel, String html) {
  final jobs = <JobListing>[];
  final seen = <String>{};
  int? oldest;
  final posts = RegExp(r'data-post="[^"/]+/(\d+)"').allMatches(html).toList();
  for (final (i, p) in posts.indexed) {
    final id = int.parse(p.group(1)!);
    oldest = oldest == null || id < oldest ? id : oldest;
    final chunk = html.substring(p.start, i + 1 < posts.length ? posts[i + 1].start : html.length);
    final textHtml = RegExp(r'<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)</div>').firstMatch(chunk)?.group(1);
    if (textHtml == null) continue;
    final posted = DateTime.tryParse(RegExp(r'<time datetime="([^"]+)"').firstMatch(chunk)?.group(1) ?? '');
    final text = _postText(textHtml);
    if (RegExp(r'pinned «|channel photo|changed the channel', caseSensitive: false).hasMatch(text)) continue;

    for (final (b, block) in _blocks(text).indexed) {
      if (!_jobWords.hasMatch(block) || _promo.hasMatch(block)) continue;
      final job = _jobFrom(channel, id, b, block, posted);
      if (job != null && seen.add(job.applyTarget.toLowerCase())) jobs.add(job);
    }
  }
  return TelegramPage(jobs, oldest);
}

JobListing? _jobFrom(String channel, int postId, int blockIndex, String block, DateTime? posted) {
  final firstLine = block.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
  var company = _label(block, _companyKeys) ?? '';
  var role = _label(block, _roleKeys) ?? '';
  var location = _label(block, _locationKeys) ?? '';

  // "📌 FarEye is hiring for Associate Solutions Engineer"
  final hiring = RegExp(r'^[^A-Za-z0-9]*(.+?)\s+is\s+hiring\s+(?:for\s+)?(?:an?\s+)?(.+)$', caseSensitive: false).firstMatch(firstLine);
  // "Smytten Recruitment 2026 – Software Development Engineer Intern | Bangalore"
  // "Reliance Jio Off Campus Drive 2026: Graduate Engineer Trainee | Mumbai"
  final titled = RegExp(r'^[^A-Za-z0-9]*(.+?)\s+(?:recruitment|off\s*campus|hiring|careers|drive)\b[^–—|:-]*[–—|:-]\s*(.+)$', caseSensitive: false)
      .firstMatch(firstLine);
  // "Oculon Software Engineering Intern 2026 – Remote | ₹10,000/Month"
  final named = RegExp(r'^[^A-Za-z0-9]*(.+?\b(?:intern(?:ship)?|trainee|engineer|developer|analyst|designer|apprentice))\b[^–—|:]*(?:[–—|:]\s*(.+))?$', caseSensitive: false)
      .firstMatch(firstLine);
  if (hiring != null) {
    if (company.isEmpty) company = hiring.group(1)!;
    if (role.isEmpty) role = hiring.group(2)!;
  } else if (titled != null) {
    if (company.isEmpty) company = titled.group(1)!;
    final parts = titled.group(2)!.split('|').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    if (role.isEmpty && parts.isNotEmpty && !RegExp(r'^apply', caseSensitive: false).hasMatch(parts.first)) role = parts.first;
    if (location.isEmpty) location = _placeIn(parts.skip(1));
  } else if (named != null && role.isEmpty) {
    // The company is whatever comes before the role words ("Oculon" + "Software Engineering Intern").
    final words = named.group(1)!.split(RegExp(r'\s+'));
    final at = words.indexWhere((w) => _roleStart.hasMatch(w));
    if (at > 0 && company.isEmpty) company = words.take(at).join(' ');
    role = words.skip(at < 0 ? 0 : at).join(' ');
    if (location.isEmpty) location = _placeIn((named.group(2) ?? '').split('|').map((x) => x.trim()));
  }
  if (_notACompany.hasMatch(company)) company = '';
  if (company.isEmpty || role.isEmpty) {
    final lead = leadFromText(block);
    if (company.isEmpty && !_notACompany.hasMatch(lead.company)) company = lead.company;
    if (role.isEmpty && lead.title != 'Internship') role = lead.title;
  }
  // A sentence ("So if you have an idea worth building… get an internship") isn't a job title.
  if (role.isNotEmpty && (!_roleWord.hasMatch(role) || role.split(RegExp(r'\s+')).length > 10)) role = '';

  // Where to apply: an email beats a link; the labelled "Apply link" beats any other link.
  final email = _emailRe.allMatches(block).map((m) => m[0]!).where((e) => !RegExp('privacy|noreply|no-reply').hasMatch(e)).firstOrNull;
  final labelled = _urlRe.firstMatch(_label(block, _linkKeys) ?? '')?.group(0);
  final link = (labelled != null && !_isNoise(labelled)) ? labelled : _urlRe.allMatches(block).map((m) => m[0]!).where((u) => !_isNoise(u)).firstOrNull;
  final target = email ?? (link == null ? null : cleanUrl(link.replaceAll(RegExp(r'[.,;!]+$'), '')));
  // Needs a real role: "Company not named · Opening" posts are almost always ads or reports.
  if (target == null || role.isEmpty) return null;

  company = company.replaceAll(RegExp(r'[|*_]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  role = role.replaceAll(RegExp(r'[*_]+'), '').trim();
  if (RegExp(r'^pan[\s-]*india$', caseSensitive: false).hasMatch(location)) location = 'India';
  return JobListing(
    id: 'tg-$channel-$postId-$blockIndex',
    company: company.isEmpty ? 'Company not named' : company,
    title: role.isEmpty ? 'Opening' : role,
    applyTarget: target,
    location: location,
    description: block,
    rules: parseRules('$role\n$block', company: company),
    postedAt: posted,
    stipend: _label(block, _payKeys) ?? payFromText(block) ?? '',
    source: 'Telegram · @$channel',
    sourceUrl: 'https://t.me/$channel/$postId',
  );
}
