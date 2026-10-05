import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/engines.dart';
import 'package:proof_pitch/insights.dart';
import 'package:proof_pitch/models.dart';
import 'package:proof_pitch/tailor.dart';

const _game = Project(id: 'g', name: 'Project Bonds', url: 'https://github.com/me/bonds', kind: ProjectKind.repo, tags: ['unity', 'c#'],
    bullets: ['Co-op puzzle game built in Unity']);
const _app = Project(id: 'a', name: 'Notes', url: 'https://play.google.com/store/apps/details?id=x', kind: ProjectKind.playStore,
    tags: ['flutter', 'firebase'], bullets: ['Designed a dark mode', 'Built offline sync with Firebase and Flutter']);
const _me = StudentProfile(name: 'Asha Rao', degree: 'B.Sc', college: 'VJTI', graduationYear: 2027, skills: ['java', 'flutter', 'git'],
    projects: [_game, _app], experience: ['Intern, Acme (2025)'], extras: ['Hackathon winner']);

void main() {
  test('tailored resume: the job\'s skills and the projects that prove them come first; nothing invented', () {
    const desc = 'Build mobile apps using Flutter and Firebase. Experience with Git.';
    final job = JobListing(id: 'x', company: 'Zethic Technologies LLP', title: 'Flutter Developer Intern', applyTarget: 'x', rules: parseRules(desc));
    final r = tailorResume(_me, job);
    expect(r.headline, startsWith('Flutter Developer Intern'));
    expect(r.relevantSkills, ['Flutter', 'Firebase', 'Git']);
    expect(r.otherSkills, isNot(contains('Flutter')));
    expect(r.projects.first.project.name, 'Notes', reason: 'the Flutter project leads for a Flutter job');
    expect(r.projects.first.bullets.first, 'Built offline sync with Firebase and Flutter', reason: 'most relevant bullet first');
    expect(r.summary, contains('with Flutter and Firebase'), reason: 'only skills a project shows (not Git)');
    expect(r.summary, contains('Zethic Technologies'));
    expect(r.sections.map((x) => x.title), ['Experience', 'Education', 'Achievements'], reason: 'older profiles fall back to the parsed fields');
    expect(r.projects, hasLength(2), reason: 'every project is kept, just reordered');
    expect(r.projects.first.bullets, hasLength(2), reason: 'every bullet is kept');

    final game = tailorResume(_me, JobListing(id: 'y', company: 'Studio', title: 'Unity Intern', applyTarget: 'x', rules: parseRules('Unity and C#')));
    expect(game.projects.first.project.name, 'Project Bonds', reason: 'same profile, different job, different order');
  });

  test('every section of the original resume is carried over, as written, in order', () {
    final s = _me.copyWith(resumeSections: const [
      ResumeSection('SUMMARY', 'summary', ['Flutter dev who ships.']),
      ResumeSection('PROJECTS', 'projects', ['Notes | Flutter']),
      ResumeSection('Experience', 'experience', ['Intern, Acme (2025)', '• Built the thing']),
      ResumeSection('CERTIFICATIONS', 'other', ['• Google Cloud Study Jams']),
      ResumeSection('Education', 'education', ['VJTI', 'B.Sc IT | 2027']),
    ]);
    final tailored = tailorResume(s, JobListing(id: 'x', company: 'Acme', title: 'Flutter Intern', applyTarget: 'x', rules: parseRules('Flutter')));
    expect(tailored.sections.map((x) => x.title), ['Experience', 'CERTIFICATIONS', 'Education'], reason: 'skills/projects/summary are rebuilt, the rest kept');
    expect(tailored.sections[1].lines, ['• Google Cloud Study Jams']);
    expect(tailored.summary, contains('Flutter'), reason: 'a job gets a summary written for it');
    expect(tailorResume(s).summary, 'Flutter dev who ships.', reason: 'without a job, the student\'s own summary stays');
  });

  test('tailored resume renders to a PDF', () async {
    final job = JobListing(id: 'x', company: 'Acme', title: 'Flutter Intern', applyTarget: 'x', rules: parseRules('Flutter'));
    final bytes = await resumePdfBytes(tailorResume(_me, job));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('resume import keeps project bullets, experience and achievements for tailoring', () {
    const text = '''
ASHA RAO
asha@example.com
PROJECTS
Notes App | Flutter, Firebase | https://github.com/asha/notes
● Built offline sync with Firebase so notes work without internet
● Published on Google Play with 1k installs
EXPERIENCE
Android Intern, Acme Labs (Jun 2025 – Aug 2025)
● Shipped a field-sales app used by 300 reps
ACHIEVEMENTS
● Winner, college hackathon 2025
''';
    final r = parseResume(text);
    expect(r.projects.single.bullets, ['Built offline sync with Firebase so notes work without internet', 'Published on Google Play with 1k installs']);
    expect(r.experience, ['Android Intern, Acme Labs (Jun 2025 – Aug 2025)', 'Shipped a field-sales app used by 300 reps']);
    expect(r.extras, ['Winner, college hackathon 2025']);
    final merged = r.mergeInto(const StudentProfile(projects: [Project(id: 'old', name: 'Notes App', url: 'u', kind: ProjectKind.repo)]));
    expect(merged.projects.single.id, 'old', reason: 'keeps the user\'s edited project');
    expect(merged.projects.single.bullets, hasLength(2), reason: 'but picks up its bullets');
    expect(merged.experience, hasLength(2));
  });
}
