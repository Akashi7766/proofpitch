// Regression tests for issues found by walking through the app as a student.
import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/engines.dart';
import 'package:proof_pitch/insights.dart';
import 'package:proof_pitch/models.dart';

const _bonds = Project(id: 'b', name: 'Project Bonds', url: 'https://github.com/me', kind: ProjectKind.repo, tags: ['unity', 'c#']);
const _notes = Project(
  id: 'n',
  name: 'Study Notes Handler',
  url: 'https://play.google.com/store/apps/details?id=com.me.notes&pcampaignid=web_share',
  kind: ProjectKind.playStore,
  tags: ['flutter', 'dart', 'firebase'],
  oneLiner: 'Bypassed typical junior developer training cycles by independently designing, b…',
);
const _me = StudentProfile(name: 'Kashif M', college: 'Mithibai', github: 'https://github.com/me', skills: ['java'], projects: [_bonds, _notes]);

JobListing _job({String company = 'Resolute AI Software Private Limited', String desc = '', List<String> skills = const [], String target = 'https://unstop.com/x'}) =>
    JobListing(id: 'j', company: company, title: 'Flutter Intern', applyTarget: target, description: desc, rules: ParsedRules(skills: skills));

void main() {
  test('"Java Script" is JavaScript, not Java', () {
    expect(scanSkills('Dart, Firebase, Java Script, Rest Api'), containsAll(['javascript', 'dart', 'firebase']));
    expect(scanSkills('Dart, Firebase, Java Script'), isNot(contains('java')));
  });

  test('soft skills never block and never count toward match %', () {
    final j = _job(skills: ['flutter', 'dart', 'cross-functional collaboration', 'project management', 'task tracking', 'aws', 'ui/ux']);
    expect(techSkills(j.rules.skills), ['flutter', 'dart', 'aws', 'ui/ux']);
    expect(isEligible(_me, j), isTrue, reason: '2 of 4 technical skills is enough');
    expect(matchScore(_me.allSkills, j), 50);
  });

  test('Unity implies game development', () {
    expect(_me.allSkills, contains('game development'));
  });

  test('company names and links are cleaned up for pitches', () {
    expect(cleanCompany('Resolute AI Software Private Limited'), 'Resolute AI Software');
    expect(cleanCompany('Blacklitt Technologies Pvt Ltd'), 'Blacklitt Technologies');
    expect(cleanCompany('Zethic Technologies LLP'), 'Zethic Technologies');
    expect(cleanCompany('Stripe'), 'Stripe');
    expect(cleanUrl('https://play.google.com/store/apps/details?id=com.me.notes&pcampaignid=web_share'),
        'https://play.google.com/store/apps/details?id=com.me.notes');
    expect(cleanUrl('https://acme.dev/x?utm_source=li'), 'https://acme.dev/x');
  });

  test('pitch: no legal suffix, no filler one-liner, no duplicate links, no "is live" for code', () {
    final p = buildPitch(_me, _job(), [_notes, _bonds], Channel.customPortal, Persona.founder).body;
    expect(p, startsWith('Hi Resolute AI Software team,'));
    expect(p, isNot(contains('Bypassed')));
    expect(p, isNot(contains('pcampaignid')));
    expect('github.com/me'.allMatches(p).length, 1, reason: 'repo fallback + GitHub signature must not repeat');
    expect(p, contains('My resume is attached to this application.'), reason: 'portals take the resume as an upload');
    expect(p, contains("It's live on Google Play"));

    final repoFirst = buildPitch(_me, _job(), [_bonds], Channel.directEmail, Persona.founder).body;
    expect(repoFirst, isNot(contains('live')));
    expect(repoFirst, contains('The code is here: https://github.com/me'));
  });

  test('work mode is read from a pasted description when there is no location', () {
    expect(workplaceOf(_job(desc: 'Stipend 15k per month, in office in Andheri.')), 'on-site');
    expect(workplaceOf(_job(desc: 'This role is fully remote.')), 'remote');
    expect(workplaceOf(_job(desc: 'Hybrid, 3 days a week.')), 'hybrid');
    expect(workplaceOf(_job(desc: 'We build games.')), '');
  });

  test('channel label is plain words', () {
    expect(channelLabel(_job(target: 'https://unstop.com/internships/x')), 'Apply on unstop.com');
    expect(channelLabel(_job(target: 'founder@x.io')), 'Email the team directly');
  });

  test('resume: long filler bullets are not one-liners; Play Store apps say so', () {
    const text = '''
JANE DOE
PROJECTS
Notes App | Flutter, Firebase |
Playstore : https://play.google.com/store/apps/details?id=com.jane.notes&pcampaignid=web_share
● Zero-Ramp Deployment: Bypassed typical junior developer training cycles by independently designing things
TECHNICAL SKILLS
● Tools: VS Code, Android Studio, Git, Agile Workflows
''';
    final r = parseResume(text);
    expect(r.projects.single.oneLiner, 'Live on Google Play');
    expect(r.projects.single.url, 'https://play.google.com/store/apps/details?id=com.jane.notes');
    expect(r.skills, isNot(contains('vs code')));
    expect(r.skills, isNot(contains('agile workflows')));
    expect(r.skills, contains('git'));
  });
}
