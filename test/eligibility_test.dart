import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/data.dart' show unstopJob;
import 'package:proof_pitch/engines.dart';
import 'package:proof_pitch/insights.dart';
import 'package:proof_pitch/models.dart';

// Same layout as a real student resume that broke the old parser (anonymised).
const _resume = '''
JANE ANITA DOE
Email: jane.doe@example.com Phone: +91 9000000000
GitHub Profile: https://github.com/janedoe
LinkedIn Profile : https://www.google.com/search?q=https://www.linkedin.com/in/jane-doe-123/
PRODUCTION VALUE SUMMARY
Self-directed developer shipping across mobile (Flutter/Firebase) and game engines (Unity/C#).
TECHNICAL SKILLS (IMMEDIATE EXECUTION)
● Languages: Python, Java, Dart, C#, C, SQL, JavaScript, HTML/CSS, XML
● Frameworks & Engines: Flutter, Unity Engine, Firebase, Java Servlets, JSP, JDBC
● Core Systems: Data Structures & Algorithms (DSA), Object-Oriented Programming
(OOP), REST APIs, JSON
● Tools & Databases: Git, GitHub, MySQL, Android Studio, VS Code
FEATURED SOFTWARE PROJECTS
Study Notes Handler | Flutter, Dart, Firebase |
Playstore : https://play.google.com/store/apps/details?id=com.jane.notes
● Zero-Ramp Deployment: Independently designed, built and deployed a mobile utility to the
Google Play Store under Early Access.
Project Bonds (Visual Novel Architecture) | Unity Engine, C# | [View GitHub Repository]
● Scalable Engine Design: Built a reusable C# event controller for non-linear narrative trees.
Project Rogue (Turn-Based Mechanics Engine) | Unity Engine, C# | [View GitHub Repository]
● Deterministic Logic Systems: Engineered a combat calculation engine with buff/debuff modifiers.
ACADEMIC TRAJECTORY & METRICS
SVKM's Mithibai College | Bachelor of Science in Computer Science | Expected Graduation:
May 2027
● Cumulative CGPA: 8.51
''';

JobListing _job({String location = '', String workplace = '', List<String> skills = const [], List<String> groups = const [], String desc = ''}) =>
    JobListing(
      id: 'j',
      company: 'Acme',
      title: 'Intern',
      applyTarget: 'https://acme.dev',
      location: location,
      workplace: workplace,
      description: desc,
      rules: ParsedRules(skills: skills),
      eligibleGroups: groups,
    );

void main() {
  final r = parseResume(_resume);
  final me = r.mergeInto(const StudentProfile()).copyWith(city: 'Mumbai');

  test('resume: skills section is read token by token', () {
    expect(r.skills, containsAll(['unity', 'c#', 'c', 'mysql', 'rest api', 'oop', 'jsp', 'jdbc', 'servlets', 'flutter', 'html', 'css']));
    expect(r.skills, isNot(contains('android')), reason: '"Android Studio" is a tool, not Android dev');
  });

  test('resume: projects under a custom heading with "Name | Tech | Link" lines', () {
    expect(r.projects.map((p) => p.name), ['Study Notes Handler', 'Project Bonds', 'Project Rogue']);
    expect(r.projects[0].kind, ProjectKind.playStore);
    expect(r.projects[0].url, contains('play.google.com'));
    expect(r.projects[1].tags, containsAll(['unity', 'c#']));
    expect(r.projects[1].tags, isNot(contains('git')), reason: '"[View GitHub Repository]" is a label, not a skill');
    expect(r.projects[1].oneLiner, 'Visual Novel Architecture');
    expect(r.warnings.where((w) => w.contains('no URL behind it')).length, 2);
  });

  test('resume: name, degree, CGPA, links, country', () {
    expect(r.name, 'Jane Anita Doe');
    expect(r.degree, 'B.Sc');
    expect(r.cgpa, 8.51);
    expect(r.graduationYear, 2027);
    expect(r.college, "SVKM's Mithibai College");
    expect(r.linkedin, startsWith('https://www.linkedin.com/in/jane-doe-123'), reason: 'Google-wrapped link is unwrapped');
    expect(r.warnings.any((w) => w.contains('Google search')), isTrue);
    expect(r.country, 'India');
  });

  test('match % and pre-flight agree: resume skills count, not just attached projects', () {
    final job = _job(location: 'Mumbai, India', skills: ['unity', 'c#', 'mysql']);
    final unityOnly = me.projects.where((p) => p.name == 'Project Bonds').toList();
    final rep = runPreflight(me, job, unityOnly);
    expect(matchScore(me.allSkills, job), 100);
    expect(rep.missingSkills, isEmpty);
    expect(rep.cleared, isTrue);
    expect(rep.checks.firstWhere((c) => c.label.startsWith('Tech skills')).ok, isTrue);
  });

  test('hard gates: missing most required skills blocks applying', () {
    final rep = runPreflight(me, _job(location: 'Pune', skills: ['react', 'node.js', 'mongodb', 'flutter']), me.projects);
    expect(rep.cleared, isFalse);
    expect(rep.blockers.single.label, 'Tech skills 1/4');
  });

  test('hard gates: location and work authorization', () {
    expect(isEligible(me, _job(location: 'San Francisco, CA')), isFalse);
    expect(isEligible(me, _job(location: 'Remote - US')), isFalse);
    expect(isEligible(me, _job(location: 'Remote')), isTrue, reason: 'unrestricted remote is fine');
    expect(isEligible(me, _job(location: 'Bengaluru, India')), isTrue);
    final blocked = eligibility(me, _job(location: 'New York, NY', desc: 'Must be authorized to work in the United States.'));
    expect(blocked.single.detail, contains('work authorization'));
  });

  test('hard gates: degree groups (Unstop eligibility)', () {
    expect(isEligible(me, _job(groups: ['Engineering Students'])), isFalse, reason: 'B.Sc is not engineering');
    expect(isEligible(me, _job(groups: ['Engineering Students', 'Undergraduate'])), isTrue);
    expect(isEligible(me, _job(groups: ['Arts, Commerce, Sciences & Others'])), isTrue);
  });

  test('nearness ranks your city, then remote-in-country, then country, then the world', () {
    expect(nearness(me, _job(location: 'Mumbai, India')), 3);
    expect(nearness(me, _job(location: 'Remote, India', workplace: 'remote')), 3);
    expect(nearness(me, _job(location: 'Bangalore, India')), 2);
    expect(nearness(me, _job(location: 'Remote')), 1);
    expect(nearness(me, _job(location: 'London, UK')), 0);
  });

  test('unstopJob maps stipend, work mode, cities, eligibility and required skills', () {
    final j = unstopJob({
      'id': 42,
      'title': 'Unity Developer Internship',
      'seo_url': 'https://unstop.com/internships/unity-42',
      'organisation': {'name': 'PixelForge'},
      'details': '<p>Build games in <b>Unity</b>.</p>',
      'approved_date': '2026-10-01 15:24:43 GMT+0530',
      'end_date': '2026-10-16T12:59:33+05:30',
      'jobDetail': {'type': 'in_office', 'min_salary': 12000, 'max_salary': 15000, 'pay_in': 'monthly', 'paid_unpaid': 'paid'},
      'locations': [
        {'city': 'Mumbai', 'country': 'India'},
      ],
      'filters': [
        {'type': 'eligible', 'name': 'Undergraduate'},
        {'type': 'category', 'name': 'Gaming'},
      ],
      'required_skills': [
        {'skill_name': 'Unity Engine'},
        {'skill_name': 'C#'},
      ],
    });
    expect(j.stipend, '₹12k–15k/month');
    expect(workplaceOf(j), 'on-site');
    expect(j.location, 'Mumbai, India');
    expect(j.eligibleGroups, ['Undergraduate']);
    expect(j.rules.skills, containsAll(['unity', 'c#']));
    expect(j.postedAt, isNotNull);
    expect(nearness(me, j), 3);
    expect(isEligible(me, j), isTrue);
  });

  test('canonSkill folds Unstop-style names', () {
    expect(canonSkill('Flutter Framework'), 'flutter');
    expect(canonSkill('Git Version Control'), 'git');
    expect(canonSkill('Unity Engine'), 'unity');
    expect(canonSkill('API Development'), 'rest api');
    expect(canonSkill('Backend Development'), 'backend development', reason: 'unknown skills pass through');
  });

  test('payFromText', () {
    expect(payFromText(r'This internship pays $45/hour.'), r'$45/hour');
    expect(payFromText('Stipend: ₹15,000 per month'), '₹15,000 per month');
    expect(payFromText('Stipend of 20k per month'), '₹20k/month');
    expect(payFromText('This is an unpaid internship'), 'Unpaid');
    expect(payFromText(r'We raised $50M from top investors.'), isNull);
    expect(payFromText('No pay info here'), isNull);
    expect(payFromText(r'Internship $46 — $46 USD'), r'$46');
    expect(payFromText(r'$40 – $55 per hour'), r'$40 – $55 per hour');
  });
}
