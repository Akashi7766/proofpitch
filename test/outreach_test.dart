import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/models.dart';
import 'package:proof_pitch/outreach.dart';

JobListing _job({String id = '1', String company = 'Acme', String title = 'Software Intern', String target = 'https://jobs.lever.co/acme/1', String desc = ''}) =>
    JobListing(id: id, company: company, title: title, applyTarget: target, description: desc);

void main() {
  test('guessPersona reads the post, not the student; defaults to a general recruiter', () {
    final startup = guessPersona(_job(desc: 'We are a seed-funded startup, small team, you will ship fast.'));
    expect(startup.persona, Persona.founder);
    expect(startup.companyType, 'Early-stage startup');
    expect(startup.reasons, contains('"startup"'));

    final big = guessPersona(_job(company: 'Databricks', desc: 'Work on distributed systems at scale.'));
    expect(big.persona, Persona.recruiter);
    expect(big.reasons.first, 'large, well-known company');

    final eng = guessPersona(_job(desc: 'Our tech stack is Go and Postgres. You will do code review and system design.'));
    expect(eng.persona, Persona.engineer);

    final design = guessPersona(_job(title: 'Product Design Intern', desc: 'Prototype in Figma.'));
    expect(design.persona, Persona.designLead);

    final plain = guessPersona(_job(title: 'Intern', desc: 'Help the team.'));
    expect(plain.persona, Persona.recruiter);
    expect(plain.companyType, 'General hiring team');
  });

  test('contactRoutes: real email from the post beats guesses, junk inboxes skipped', () {
    final routes = contactRoutes(
      _job(desc: 'Need help? accommodations@acme.dev. Send your work to careers@acme.dev or visit https://acme.dev/team.'),
      Persona.founder,
    );
    expect(routes.first.kind, RouteKind.email);
    expect(routes.first.target, 'careers@acme.dev');
    expect(routes.any((r) => r.target.startsWith('accommodations')), isFalse);
    expect(routes.any((r) => r.kind == RouteKind.guessedEmail), isFalse, reason: 'no guessing when a real inbox exists');
    expect(routes.map((r) => r.kind), containsAll([RouteKind.applyPage, RouteKind.linkedin, RouteKind.x, RouteKind.website]));
  });

  test('contactRoutes: no email → apply page, LinkedIn, guessed inbox (labelled), website', () {
    final routes = contactRoutes(_job(target: 'https://careers.acme.co.in/jobs/42'), Persona.recruiter);
    expect(routes.first.kind, RouteKind.applyPage);
    final guess = routes.firstWhere((r) => r.kind == RouteKind.guessedEmail);
    expect(guess.target, 'careers@acme.co.in');
    expect(guess.verified, isFalse);
    expect(routes.firstWhere((r) => r.kind == RouteKind.linkedin).target, contains('HR%20recruiter'));
    expect(routes.any((r) => r.kind == RouteKind.x), isFalse, reason: 'X DMs only for startup founders');
  });

  test('contactRoutes: unknown domain falls back to a search', () {
    final routes = contactRoutes(_job(target: 'https://unstop.com/internships/x-1'), Persona.founder);
    expect(routes.last.kind, RouteKind.search);
    expect(routes.any((r) => r.kind == RouteKind.guessedEmail), isFalse);
  });

  test('contactRoutes: emails found on their website are real routes, not guesses', () {
    final routes = contactRoutes(_job(target: 'https://unstop.com/internships/x-1'), Persona.recruiter, siteContacts: [
      const SiteContact('hr@tiny.io', ContactRole.hiring),
      const SiteContact('kartik@tiny.io', ContactRole.founder, name: 'Kartik Rao', guessed: true),
    ]);
    expect(routes.first.target, 'hr@tiny.io');
    expect(routes.first.detail, 'Hiring / HR — on their website');
    expect(routes.first.verified, isTrue);
    expect(routes[1].kind, RouteKind.guessedEmail);
    expect(routes[1].detail, contains('Founder · Kartik Rao'));
    expect(routes[1].verified, isFalse, reason: 'pattern guesses stay labelled GUESS');
  });

  test('site contacts: the person who hires first, labelled by the words around them', () {
    const html = '''<footer>Write to us: info@tiny.io | Support: support@tiny.io</footer>
      <section><h3>Kartik Rao</h3><p>Co-founder &amp; CEO</p><a href="mailto:kartik@tiny.io">Email</a></section>
      <section><h3>Meera Iyer</h3><p>Co-founder, CTO</p></section>
      <p>For internships and careers, reach our HR team at <a href="mailto:roshan@tiny.io">roshan@tiny.io</a></p>''';
    final c = contactsInHtml(html, domain: 'tiny.io', techRole: true);
    expect(c.first.email, 'roshan@tiny.io');
    expect(c.first.role, ContactRole.hiring);
    final founder = c.firstWhere((x) => x.email == 'kartik@tiny.io');
    expect(founder.role, ContactRole.founder);
    final cto = c.firstWhere((x) => x.name == 'Meera Iyer');
    expect(cto.email, 'meera@tiny.io', reason: 'follows the site\'s first-name pattern');
    expect(cto.role, ContactRole.techLead);
    expect(cto.guessed, isTrue);
    expect(c.indexOf(cto), lessThan(c.indexWhere((x) => x.email == 'info@tiny.io').clamp(0, 99)), reason: 'tech lead beats a general inbox for a tech role');
  });

  test('direct-email jobs lead with that inbox', () {
    final routes = contactRoutes(_job(target: 'founder@tinyco.io'), Persona.founder);
    expect(routes.first.target, 'founder@tinyco.io');
  });

  test('shortNote fits a LinkedIn connection note', () {
    const me = StudentProfile(name: 'Kashif Mukaddam', degree: 'B.Sc', graduationYear: 2027, college: "SVKM's Mithibai College");
    const p = Project(id: 'p', name: 'Study Notes Handler', url: 'https://play.google.com/store/apps/details?id=x', kind: ProjectKind.playStore, oneLiner: 'live on Play Store');
    final note = shortNote(me, _job(title: 'Flutter Developer Intern'), [p], Persona.founder);
    expect(note.length, lessThanOrEqualTo(linkedInNoteLimit));
    expect(note, contains('Study Notes Handler'));
    expect(note, startsWith("Hi! I'm Kashif"));
  });

  test('site contacts: addresses hidden in links count; one person never gets a second guessed address', () {
    const html = '''<p>Roshan Kapar, HR Manager</p><a href="https://mail.google.com/mail/?view=cm&amp;to=roshan.hr@a.org">Mail</a>
      <p>Noman Ali, President</p><a href="https://mail.google.com/mail/?view=cm&amp;to=noman@a.org">Mail</a>''';
    final c = contactsInHtml(html, domain: 'a.org');
    expect(c.map((x) => x.email), ['roshan.hr@a.org', 'noman@a.org']);
    expect(c.any((x) => x.email == 'roshan@a.org'), isFalse);
    expect(c.every((x) => !x.name.contains('President')), isTrue);
    expect(contactsInHtml('<p>Write to careers@zethic.com</p><p>Transportation System Crypto, HR</p>').single.name, '',
        reason: 'generic inboxes are never given a name');
  });

  test('emails on a company site: real inboxes, hiring ones first, no junk', () {
    const html = '<img src="logo@2x.png"> <a href="mailto:info@tiny.io">mail</a> support@tiny.io '
        'careers&#64;tiny.io you@example.com <p>HR: hr@tiny.io</p>';
    expect(emailsInHtml(html), ['careers@tiny.io', 'hr@tiny.io', 'info@tiny.io'], reason: 'best three only');
    expect(emailsInHtml('kartik@a.org noman@a.org roshan.hr@a.org support@a.org'), ['roshan.hr@a.org', 'kartik@a.org', 'noman@a.org'],
        reason: 'a hiring word inside the address counts; support@ is kept on small sites but ranked last');
    expect(emailsInHtml('support@a.org'), ['support@a.org']);
    expect(emailsInHtml('<p>No contact here</p>'), isEmpty);
  });

  test('robots.txt is respected (longest rule wins, only the * group counts)', () {
    const robots = 'User-agent: Googlebot\nDisallow: /\n\nUser-agent: *\nDisallow: /careers\nAllow: /careers/open\n';
    expect(robotsAllows(robots, '/'), isTrue);
    expect(robotsAllows(robots, '/careers'), isFalse);
    expect(robotsAllows(robots, '/careers/open'), isTrue);
    expect(robotsAllows('', '/contact'), isTrue);
    expect(robotsAllows('User-agent: *\nDisallow: /', '/contact'), isFalse);
  });

  test('official site: likely domains from the name, confirmed by the page title', () {
    expect(domainCandidates('Zethic Technologies LLP').first, 'zethic.com');
    expect(domainCandidates('Kukbit SL'), contains('kukbitsl.in'));
    expect(domainCandidates('Hoogway.ai'), ['hoogway.ai'], reason: 'the name already is a domain');
    expect(domainCandidates('Lyftr AI'), contains('lyftr.ai'));
    expect(siteScore('Zethic Technologies LLP', '<title>Zethic | App Development Company</title>'), 2);
    expect(siteScore('Shanks Code Private Limited', '<title>Shanks Spices</title>'), 1, reason: 'main word only: weaker');
    expect(siteScore('Paathshala Pandit', '<title>Domain for sale</title>'), 0);
  });

  test('shared LinkedIn/Reddit post → lead', () {
    final l = leadFromText('We are hiring! 🚀 Flutter Developer Intern at Kukbit (remote). '
        'Send your resume to careers@kukbit.in or apply https://forms.gle/abc123. '
        'https://www.linkedin.com/posts/someone_hiring-activity-123');
    expect(l.target, 'careers@kukbit.in');
    expect(l.company, 'Kukbit');
    expect(l.title, 'Flutter Developer Intern');
    expect(l.location, 'Remote');
    expect(leadFromText('Flutter Developer Intern at Kukbit. Mail careers@kukbitsl.in').company, 'Kukbit',
        reason: 'the post says Kukbit; the domain kukbitsl agrees');
    expect(leadFromText('Intern at Bangalore office. Mail hr@zethic.com').company, 'Zethic', reason: 'domain wins when they disagree');

    final noEmail = leadFromText('Join Acme Robotics as a Data Analyst Intern. Apply: https://jobs.lever.co/acme/1 https://lnkd.in/x');
    expect(noEmail.target, 'https://jobs.lever.co/acme/1', reason: 'apply link beats the LinkedIn self-link');
    expect(noEmail.company, 'Acme Robotics');
    expect(noEmail.title, 'Data Analyst Intern');
  });

  test('company → domain only on a real name match', () {
    expect(
        domainFromSuggest('Groww', [
          {'name': 'Grow Weed Easy', 'domain': 'growweedeasy.com'},
          {'name': 'Groww', 'domain': 'groww.in'},
        ]),
        'groww.in');
    expect(domainFromSuggest('Learntricks Edutech', [{'name': 'Learntricks Edutech', 'domain': 'learntricksedutech.com'}]), 'learntricksedutech.com');
    expect(domainFromSuggest('Acme', [{'name': 'Acme Rockets Global', 'domain': 'x.com'}]), isNull);
  });
}
