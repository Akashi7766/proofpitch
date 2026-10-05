import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/insights.dart';
import 'package:proof_pitch/models.dart';
import 'package:proof_pitch/screens/tracker_screen.dart' show weekStreak;
import 'package:syncfusion_flutter_pdf/pdf.dart';

const resume = '''
Asha Rao
asha.rao@gmail.com | +91 98765 43210 | github.com/asharao | linkedin.com/in/asharao | asharao.dev
EDUCATION
Veermata Jijabai Technological Institute, Mumbai
B.Tech in Computer Engineering, 2023 - 2027
CGPA: 8.42/10
SKILLS
Python, Flutter, Dart, SQL, Docker, Firebase, Figma
PROJECTS
FastQ | Python, Redis, Docker
• Async job queue handling 10k jobs/min; 1.2k GitHub stars github.com/asharao/fastq
• Built a retry scheduler
Habitly - Flutter, Firebase
• Habit tracker with 5k installs on Play Store play.google.com/store/apps/details?id=dev.habitly
EXPERIENCE
Backend Intern, Acme (Summer 2025)
• Did things
''';

void main() {
  test('parseResume extracts profile fields', () {
    final r = parseResume(resume);
    expect(r.name, 'Asha Rao');
    expect(r.email, 'asha.rao@gmail.com');
    expect(r.phone, contains('98765'));
    expect(r.github, 'https://github.com/asharao');
    expect(r.linkedin, 'https://linkedin.com/in/asharao');
    expect(r.portfolio, 'https://asharao.dev');
    expect(r.cgpa, 8.42);
    expect(r.graduationYear, 2027);
    expect(r.college, startsWith('Veermata Jijabai Technological Institute'));
    expect(r.skills, containsAll(['python', 'flutter', 'sql', 'docker', 'figma']));
    expect(r.projects.map((p) => p.name), ['FastQ', 'Habitly']);
    expect(r.projects[0].url, 'https://github.com/asharao/fastq');
    expect(r.projects[0].tags, containsAll(['python', 'redis', 'docker']));
    expect(r.projects[1].kind, ProjectKind.playStore);
  });

  test('mergeInto keeps existing data and dedupes projects', () {
    const existing = StudentProfile(
      portfolio: 'https://mine.me',
      skills: ['rust'],
      projects: [Project(id: 'x', name: 'FastQ', url: 'u', kind: ProjectKind.repo)],
    );
    final merged = parseResume(resume).mergeInto(existing);
    expect(merged.name, 'Asha Rao');
    expect(merged.skills, containsAll(['rust', 'python']));
    expect(merged.projects.map((p) => p.name), ['FastQ', 'Habitly']);
  });

  test('real PDF round-trip', () {
    final doc = PdfDocument();
    doc.pages.add().graphics.drawString(resume, PdfStandardFont(PdfFontFamily.helvetica, 10),
        bounds: const Rect.fromLTWH(0, 0, 500, 800));
    final bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    final r = parseResume(pdfToText(bytes));
    expect(r.email, 'asha.rao@gmail.com');
    expect(r.skills, contains('flutter'));
  });

  test('matchScore, roleOf, ageLabel', () {
    const job = JobListing(id: '1', company: 'c', title: 't', applyTarget: 'a', rules: ParsedRules(skills: ['python', 'sql', 'golang', 'kubernetes']));
    expect(matchScore({'python', 'sql'}, job), 50);
    expect(matchScore({'python'}, const JobListing(id: '1', company: 'c', title: 't', applyTarget: 'a')), isNull);
    const oneSkill = JobListing(id: '2', company: 'c', title: 't', applyTarget: 'a', rules: ParsedRules(skills: ['sql']));
    expect(matchScore({'sql'}, oneSkill), 33, reason: 'one keyword is not a perfect fit');
    expect(roleOf('Android Engineer Intern'), Role.mobile);
    expect(roleOf('Data Science Intern (2027)'), Role.data);
    expect(roleOf('Product Design Intern'), Role.design);
    expect(roleOf('Software Engineer Intern, Backend'), Role.engineering);
    final now = DateTime(2026, 10, 3);
    expect(ageLabel(now.subtract(const Duration(hours: 3)), now), 'today');
    expect(ageLabel(now.subtract(const Duration(days: 5)), now), '5d ago');
    expect(ageLabel(now.subtract(const Duration(days: 20)), now), '2w ago');
    expect(ageLabel(null, now), '');
  });

  test('summarize pulls sections, pay and duration', () {
    const desc = '''
About Acme
Acme builds rockets for everyone and has done so for many years now.
In this role, you will help our team ship the flight software that runs every launch.
What you'll do
• Write Python services for telemetry
• Review code with senior engineers
What we're looking for
• Currently pursuing a CS degree
• Comfortable with SQL
This is a 12 week internship paying \$45/hour, fully remote.
''';
    final s = summarize(const JobListing(id: '1', company: 'Acme', title: 'SWE Intern', applyTarget: 'a', description: desc));
    expect(s.doing, ['Write Python services for telemetry', 'Review code with senior engineers']);
    expect(s.wants.first, 'Currently pursuing a CS degree');
    expect(s.pay, r'$45/hour');
    expect(s.duration, '12 week');
    expect(s.workplace, 'remote');
    expect(s.tldr, contains('you will help'));
  });

  test('weekStreak counts consecutive weeks hitting the goal', () {
    final now = DateTime(2026, 10, 3); // Saturday
    final sends = [
      for (var i = 0; i < 2; i++) DateTime(2026, 9, 29), // this week: 2 (goal not yet hit)
      for (var i = 0; i < 3; i++) DateTime(2026, 9, 23), // last week: 3
      for (var i = 0; i < 3; i++) DateTime(2026, 9, 16), // week before: 3
      DateTime(2026, 9, 9), // only 1 → breaks streak
    ];
    expect(weekStreak(sends, 3, now), 2);
    expect(weekStreak(sends, 2, now), 3);
  });
}
