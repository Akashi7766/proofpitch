import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/engines.dart';
import 'package:proof_pitch/models.dart';

const flutterApp = Project(id: 'a', name: 'Habitly', url: 'https://play.google.com/x', kind: ProjectKind.playStore, tags: ['flutter', 'firebase']);
const pyApi = Project(id: 'b', name: 'FastQ', url: 'https://github.com/me/fastq', kind: ProjectKind.repo, tags: ['python', 'fastapi', 'postgres', 'docker']);
const me = StudentProfile(name: 'Asha', college: 'VJTI', cgpa: 8.1, graduationYear: 2027, github: 'https://github.com/me', projects: [flutterApp, pyApi]);

JobListing job(ParsedRules r) => JobListing(id: '1', company: 'Acme', title: 'Backend Intern', applyTarget: 'jobs@acme.dev', rules: r);

void main() {
  test('channel detection', () {
    expect(detectChannel('founder@acme.dev'), Channel.directEmail);
    expect(detectChannel('mailto:hi@acme.dev'), Channel.directEmail);
    expect(detectChannel('https://boards.greenhouse.io/acme/jobs/1'), Channel.modernAts);
    expect(detectChannel('https://jobs.lever.co/acme/x'), Channel.modernAts);
    expect(detectChannel('https://jobs.ashbyhq.com/acme'), Channel.modernAts);
    expect(detectChannel('https://acme.wd5.myworkdayjobs.com/en-US/x'), Channel.enterpriseAts);
    expect(detectChannel('careers-acme.icims.com/jobs/1'), Channel.enterpriseAts);
    expect(detectChannel('https://acme.com/careers'), Channel.customPortal);
    expect(detectChannel('https://notgreenhouse.io.evil.com'), Channel.customPortal);
  });

  test('rules parser', () {
    final r = parseRules('We need Python and FastAPI skills, Docker a plus. Minimum CGPA of 7.5. '
        'Open to students graduating in 2026 - 2027. Not React.js-only.');
    expect(r.minCgpa, 7.5);
    expect(r.allowedBatches, [2026, 2027]);
    expect(r.skills, containsAll(['python', 'fastapi', 'docker', 'react']));
    expect(r.skills, isNot(contains('go')));
    expect(parseRules('8.0+ CGPA required, 2025 batch').minCgpa, 8.0);
    expect(parseRules('C++ and Java').skills, containsAll(['c++', 'java']));
    expect(parseRules('No requirements here').minCgpa, isNull);
    expect(parseRules('Data Engineer Intern (2027)\nGo build things.').allowedBatches, [2027]);
    expect(parseRules('Let us go ship it').skills, isEmpty);
  });

  test('preflight: hard fails on CGPA and batch', () {
    final rep = runPreflight(me, job(const ParsedRules(minCgpa: 8.5, allowedBatches: [2025])), [pyApi]);
    expect(rep.cleared, isFalse);
    expect(rep.checks.where((c) => c.hard && !c.ok).length, 2);
    expect(runPreflight(me, job(const ParsedRules(minCgpa: 3.0)), [pyApi]).cleared, isTrue, reason: '8.1/10 = 3.24/4');
  });

  test('preflight: suggests project swap', () {
    final rep = runPreflight(me, job(const ParsedRules(skills: ['python', 'fastapi', 'docker'])), [flutterApp]);
    expect(rep.cleared, isTrue);
    expect(rep.swap, contains('Swap attached project to FastQ'));
    expect(runPreflight(me, job(const ParsedRules(skills: ['python'])), [pyApi]).swap, isNull);
  });

  test('pitch: reads like a person wrote it; corporate portals stay plain', () {
    final j = job(const ParsedRules(skills: ['python', 'fastapi']));
    final std = buildPitch(me, j, [pyApi, flutterApp], Channel.directEmail, Persona.recruiter, resumeAttached: true);
    expect(std.subject, 'Backend Intern application - Asha');
    expect(std.body, startsWith('Hello Acme hiring team,'));
    expect(std.body, contains("I'm Asha, a student at VJTI, graduating in 2027."));
    expect(std.body, contains('I work mostly with Python and FastAPI'));
    expect(std.body, contains("I've attached my resume."));
    expect(std.body, endsWith('Asha\ngithub.com/me'), reason: 'signs off with name and links');
    expect(buildPitch(me, j, [pyApi], Channel.directEmail, Persona.recruiter).body, isNot(contains('attached')),
        reason: 'never claim an attachment that is not there');

    final eng = buildPitch(me, j, [flutterApp, pyApi], Channel.directEmail, Persona.engineer).body;
    expect(eng.indexOf('FastQ'), lessThan(eng.indexOf('Habitly')), reason: 'engineers see the code first');

    final short = buildPitch(me, j, [pyApi], Channel.directEmail, Persona.founder, template: EmailTemplate.short, resumeAttached: true);
    expect(short.body.split(RegExp(r'\s+')).length, lessThanOrEqualTo(70));
    expect(short.body, contains('Resume attached.'));
    expect(short.body, contains("I'd love to join you as a Backend intern."), reason: 'not "as a Backend Intern"');
    expect(displaySkill('node.js'), 'Node.js');
    expect(displaySkill('react native'), 'React Native');

    final ent = buildPitch(me, j, [pyApi], Channel.enterpriseAts, Persona.recruiter);
    expect(ent.body, startsWith('Dear Hiring Manager,'));
    expect(RegExp(r'[^\x00-\x7F]').hasMatch(ent.subject + ent.body), isFalse);
    expect(ent.body, contains('My relevant skills include Python and FastAPI.'));
    expect(ent.body, contains('with a CGPA of 8.1'));
    expect(ent.body, contains('My resume is attached to this application.'));
  });

  test('pitch reads the post: quotes the duty your project proves, length, remote, honest gaps', () {
    const desc = '''Responsibilities:
• Build and maintain mobile apps using Flutter and Firebase
• Write clean code
Requirements:
• Experience with Python and FastAPI
Duration: 3 months, fully remote.''';
    final j = JobListing(id: 'x', company: 'Acme', title: 'Mobile Intern', applyTarget: 'jobs@acme.dev', description: desc, location: 'Remote', rules: parseRules(desc));
    final p = buildPitch(me, j, [pyApi, flutterApp], Channel.directEmail, Persona.recruiter).body;
    expect(p, contains("You need someone to build and maintain mobile apps using Flutter and Firebase; that's what I did in Habitly."),
        reason: "the post's own words, no repeated skill list");
    expect(p.indexOf('Habitly'), lessThan(p.indexOf('FastQ')), reason: 'the project that answers the post leads');
    expect(p, contains("I'm available for the full 3 months and comfortable working remotely."));

    final gap = JobListing(id: 'y', company: 'Acme', title: 'Mobile Intern', applyTarget: 'jobs@acme.dev',
        rules: const ParsedRules(skills: ['flutter', 'firebase', 'python', 'kotlin']));
    expect(buildPitch(me, gap, [flutterApp], Channel.directEmail, Persona.recruiter).body,
        contains("I haven't used Kotlin on a project yet, but I pick up new tools quickly."));
    expect(buildPitch(me, job(const ParsedRules()), [flutterApp], Channel.directEmail, Persona.recruiter).body, isNot(contains('You need someone')),
        reason: 'no post text, no made-up quote');
  });

  test('my template: placeholders fill in, unknown ones stay visible', () {
    final s = me.copyWith(templateSubject: 'Hi from {first_name}', templateBody: 'Dear {company},\nI built {project} ({project_link}). {nope}');
    final p = buildPitch(s, job(const ParsedRules()), [pyApi], Channel.directEmail, Persona.recruiter, template: EmailTemplate.mine);
    expect(p.subject, 'Hi from Asha');
    expect(p.body, 'Dear Acme,\nI built FastQ (https://github.com/me/fastq). {nope}');
    expect(fillTemplate('Hi {name} , at {college}', {'name': 'A', 'college': ''}), 'Hi A, at');
    final starter = buildPitch(me, job(const ParsedRules()), [pyApi], Channel.directEmail, Persona.recruiter, template: EmailTemplate.mine);
    expect(starter.body, contains('The project I\'m proudest of is FastQ'), reason: 'empty template falls back to the starter');
  });

  test('mailto encoding', () {
    final uri = buildMailto('hi@acme.dev', 'Hello there', 'Line one\nLine two & more');
    final s = uri.toString();
    expect(s, startsWith('mailto:hi@acme.dev?subject=Hello%20there&body='));
    expect(s, contains('%0A'));
    expect(s, contains('%26'));
    expect(s, isNot(contains('+')));
    expect(buildMailto('a@b.co', 's', 'x' * 5000).toString().length, lessThan(5000));
  });
}
