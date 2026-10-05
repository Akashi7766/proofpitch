import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/cold.dart';
import 'package:proof_pitch/feed.dart';
import 'package:proof_pitch/followup.dart';
import 'package:proof_pitch/models.dart';
import 'package:proof_pitch/outreach.dart';

const _me = StudentProfile(
  name: 'Asha Rao',
  degree: 'B.Sc',
  college: 'VJTI',
  graduationYear: 2027,
  email: 'asha@example.com',
  github: 'https://github.com/asha',
  interests: ['mobile'],
  skills: ['flutter'],
  projects: [Project(id: 'p', name: 'Habitly', url: 'https://play.google.com/store/apps/details?id=x', kind: ProjectKind.playStore, tags: ['flutter', 'firebase'], oneLiner: 'a habit tracker')],
);

void main() {
  test('website holes: only what a visitor sees, most useful first', () {
    const sloppy = '<html><head><title>React App</title></head><body>'
        '<img src="a.png"><img src="b.png"><img src="c.png"><footer>© 2022 Tiny Labs</footer></body></html>';
    final holes = auditPage(sloppy, loadMs: 5200, httpsOk: false, brokenLinks: ['/blog'], year: 2026);
    expect(holes.map((h) => h.title), [
      '1 broken link on the homepage (/blog)',
      'Slow homepage: 5.2s to load',
      'Not set up for phones (no viewport tag)',
      'No HTTPS redirect',
      'Browser tab says "React App"',
      '3 images without alt text',
      'No link preview image',
      'No search description',
      'Footer says © 2022',
    ]);
    const tidy = '<html><head><title>Tiny Labs | Habit apps</title><meta name="viewport" content="width=device-width">'
        '<meta name="description" content="We build habit apps."><meta property="og:image" content="x.png"></head>'
        '<body><img src="a.png" alt="logo"><footer>© 2026</footer></body></html>';
    expect(auditPage(tidy, loadMs: 900, httpsOk: true, year: 2026), isEmpty);
    expect(siteDescription(tidy), 'We build habit apps.');
  });

  test('cold email: names the person, offers to fix what was noticed, asks for a short call', () {
    final p = buildColdPitch(
      _me,
      const ColdBrief(
        company: 'Tiny Labs',
        domain: 'tinylabs.in',
        contact: SiteContact('kartik@tinylabs.in', ContactRole.founder, name: 'Kartik Rao'),
        holes: [Hole('Slow', 'your homepage took about 5.2s to load on my phone'), Hole('Footer', 'the footer still says © 2022')],
        field: Interest.mobile,
      ),
      _me.projects,
      resumeAttached: true,
    );
    expect(p.subject, 'Mobile apps internship enquiry - Asha Rao');
    expect(p.body, startsWith('Hi Kartik,'));
    expect(p.body, contains('I came across Tiny Labs (tinylabs.in) and wanted to ask whether you\'d take on an intern, ideally on mobile apps.'));
    expect(p.body, contains('your homepage took about 5.2s to load on my phone and the footer still says © 2022'));
    expect(p.body, contains("I'd be happy to fix them as a first task"));
    expect(p.body, contains('Habitly'));
    expect(p.body, contains("I've attached my resume. Would you be open to a 10-minute call this week?"));

    final own = buildColdPitch(_me, const ColdBrief(company: 'Tiny Labs', ownNote: 'the signup OTP takes a minute to arrive.'), _me.projects);
    expect(own.body, startsWith('Hi Tiny Labs team,'));
    expect(own.body, contains('While using your product I noticed the signup OTP takes a minute to arrive.'));
    expect(own.body, isNot(contains('attached')));
  });

  test('cold targets: small companies in your fields first, big brands left out', () {
    JobListing j(String id, String company, String title) => JobListing(id: id, company: company, title: title, applyTarget: 'x');
    final t = coldTargets([
      j('us-1', 'Google India Pvt Ltd', 'Flutter Intern'),
      j('us-2', 'Tiny Labs', 'Marketing Intern'),
      j('us-3', 'Appsmiths', 'Flutter Developer Intern'),
      j('tg-x-1-0', 'Appsmiths', 'Android Intern'),
    ], _me);
    expect(t.map((x) => x.company), ['Appsmiths', 'Tiny Labs']);
    expect(t.first.roles, ['Flutter Developer Intern', 'Android Intern']);
    expect(t.first.sources, {'🟣 Unstop', '✈️ Telegram @x'});
    expect(isFamous('Google India Pvt Ltd'), isTrue);
    expect(isFamous('Glancey Labs'), isFalse);
  });

  test('targets from the web: YC startups in India or remote, GitHub studios minus college clubs, filtered by field', () {
    final yc = ycTargets([
      {'name': 'Tiny Games, Inc.', 'slug': 'tiny', 'website': 'https://tiny.gg', 'one_liner': 'Mobile games for Bharat', 'tags': ['Gaming'], 'industries': ['Consumer'],
        'regions': ['India'], 'all_locations': 'Pune, MH, India', 'batch': 'Winter 2024', 'status': 'Active', 'team_size': 8},
      {'name': 'Big Remote', 'slug': 'br', 'website': 'https://br.io', 'one_liner': 'AI for accountants', 'regions': ['Fully Remote'], 'status': 'Active', 'team_size': 400, 'isHiring': true},
      {'name': 'Dead Co', 'slug': 'd', 'website': 'https://d.in', 'regions': ['India'], 'status': 'Inactive', 'team_size': 3},
      {'name': 'Remote AI', 'slug': 'ra', 'website': 'https://ra.dev', 'one_liner': 'AI agents for clinics', 'regions': ['Fully Remote'], 'status': 'Active', 'team_size': 5, 'isHiring': true},
    ]);
    expect(yc.map((t) => t.company), ['Tiny Games', 'Remote AI']);
    expect(yc.first.sources, {'🟠 Y Combinator · Winter 2024'});
    expect(yc.first.fields, contains(Interest.game));
    expect(yc.first.sample.applyTarget, 'https://tiny.gg');
    expect(yc.last.fields, contains(Interest.data));

    final gh = githubTargets(Interest.game, [{'login': 'Lumimoth'}, {'login': 'GameDevUtopia'}, {'login': 'Game-Developers-Kerala'}, {'login': 'Game-Geeks-Org'}, {'login': 'InfiniteUnity'}]);
    expect(gh.map((t) => t.company), ['Lumimoth', 'GameDevUtopia', 'InfiniteUnity'], reason: '"nit" inside Infinite/Unity is not NIT');
    expect(githubOrgInfo({'login': 'studiocentauri', 'name': 'Studio Centauri, IIT Kanpur', 'description': 'Game Development Club'}), isNull);
    final info = githubOrgInfo({'login': 'Lumimoth', 'name': 'Lumimoth', 'blog': 'https://www.lumimoth.com/', 'email': 'game@lumimoth.com', 'description': 'A small game studio'})!;
    expect((info.website, info.email), ('https://www.lumimoth.com/', 'game@lumimoth.com'));

    final merged = mergeTargets([yc, gh, ycTargets([{'name': 'Tiny Games', 'slug': 't2', 'website': 'x', 'regions': ['India'], 'status': 'Active', 'one_liner': 'games'}])], field: Interest.game);
    expect(merged.map((t) => t.company), ['Tiny Games', 'Lumimoth', 'GameDevUtopia', 'InfiniteUnity'], reason: 'one card per company, only game companies');
    expect(mergeTargets([yc, gh]).length, 5);
  });

  test('after applying: next step by status and days, prep from the job, replies ready', () {
    final job = JobListing(id: 'us-9', company: 'Tiny Labs Pvt Ltd', title: 'Flutter Intern', applyTarget: 'hr@tinylabs.in',
        rules: const ParsedRules(skills: ['flutter', 'firebase', 'kotlin']));
    final sent = Application(job: job, status: AppStatus.sent, updatedAt: DateTime(2026, 10, 1), to: 'hr@tinylabs.in', subject: 'Flutter Intern application - Asha Rao');
    final early = followUpKit(sent, _me, now: DateTime(2026, 10, 3));
    expect(early.nextStep, contains('Give them 3 more days'));
    expect(followUpKit(sent, _me, now: DateTime(2026, 10, 8)).nextStep, contains("It's been 7 days"));
    expect(early.prep.first, startsWith('Walk through Habitly'));
    expect(early.prep, contains(contains('Brush up on Flutter and Firebase')));
    expect(early.prep, contains(contains("They also want Kotlin. Don't bluff")));
    expect(early.askThem, contains(contains('offer letter and a completion certificate')));
    expect(early.askThem, contains(contains("What's the stipend")), reason: 'the post lists no stipend');
    final nudge = early.replies.firstWhere((r) => r.when.startsWith('No reply'));
    expect(nudge.subject, 'Re: Flutter Intern application - Asha Rao');
    expect(nudge.body, contains('Hi Tiny Labs team,'));
    expect(nudge.body, contains('my note from 1/10 about the Flutter Intern role'));
    expect(followUpKit(sent.copyWith(status: AppStatus.replied), _me).nextStep, startsWith('They replied!'));
  });
}
