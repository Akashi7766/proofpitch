enum Channel {
  directEmail('📧', 'Email the team directly'),
  modernAts('⚡', 'Apply online · links welcome'),
  enterpriseAts('📄', 'Corporate portal · plain text only'),
  customPortal('🌐', 'Apply on their site');

  const Channel(this.emoji, this.label);
  final String emoji;
  final String label;
}

/// Who opens the application. Shapes which project leads and how the email closes.
enum Persona {
  recruiter('🗂️', 'HR / Recruiter', 'Screens lots of applications. Wants the role, your fit and your resume, fast.'),
  founder('🚀', 'Founder / small team', 'Busy and hands-on. Wants to see what you built and that you can start.'),
  engineer('🛠️', 'Engineer / Tech lead', 'Wants proof. Your stack, your code, how you built it.'),
  designLead('🎨', 'Design / Product lead', 'Cares about users and polish. Demos and walkthroughs.');

  const Persona(this.emoji, this.label, this.blurb);
  final String emoji;
  final String label;
  final String blurb;
}

/// How the email is written. [mine] is the student's own template from the ME tab.
enum EmailTemplate {
  standard('Standard', 'Friendly, complete, ~120 words'),
  short('Short', '4 lines. For founders and DMs-by-email'),
  formal('Formal', 'Cover-letter tone for HR and big companies'),
  mine('My template', 'Yours, from the ME tab');

  const EmailTemplate(this.label, this.blurb);
  final String label;
  final String blurb;
}

enum ProjectKind {
  repo('GitHub'),
  playStore('Play Store'),
  web('Live demo'),
  figma('Figma');

  const ProjectKind(this.label);
  final String label;
}

enum AppStatus { draft, sent, followedUp, replied, rejected }

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.url,
    required this.kind,
    this.tags = const [],
    this.oneLiner = '',
    this.bullets = const [],
  });

  final String id;
  final String name;
  final String url;
  final ProjectKind kind;
  final List<String> tags; // lowercase skill tags
  final String oneLiner;

  /// The resume's own bullet points for this project (used by the tailored resume).
  final List<String> bullets;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'url': url, 'kind': kind.name, 'tags': tags, 'oneLiner': oneLiner, 'bullets': bullets};

  factory Project.fromJson(Map j) => Project(
        id: j['id'],
        name: j['name'],
        url: j['url'],
        kind: ProjectKind.values.byName(j['kind']),
        tags: List<String>.from(j['tags'] ?? const []),
        oneLiner: j['oneLiner'] ?? '',
        bullets: List<String>.from(j['bullets'] ?? const []),
      );
}

/// One section of the student's resume exactly as written ("CERTIFICATIONS", "Leadership & Activities"…),
/// so the tailored PDF keeps everything, and the student can edit it in the app.
class ResumeSection {
  const ResumeSection(this.title, this.kind, this.lines);
  final String title; // the heading as it appears on the resume
  final String kind; // experience / education / skills / projects / summary / other
  final List<String> lines;

  Map<String, dynamic> toJson() => {'title': title, 'kind': kind, 'lines': lines};
  factory ResumeSection.fromJson(Map j) => ResumeSection(j['title'] ?? '', j['kind'] ?? 'other', List<String>.from(j['lines'] ?? const []));
}

class StudentProfile {
  const StudentProfile({
    this.name = '',
    this.college = '',
    this.cgpa,
    this.graduationYear,
    this.github = '',
    this.portfolio = '',
    this.linkedin = '',
    this.email = '',
    this.phone = '',
    this.skills = const [],
    this.projects = const [],
    this.city = '',
    this.country = '',
    this.degree = '',
    this.interests = const [],
    this.resumePath = '',
    this.templateSubject = '',
    this.templateBody = '',
    this.experience = const [],
    this.extras = const [],
    this.resumeSections = const [],
  });

  final String name;
  final String college;
  final double? cgpa;
  final int? graduationYear;
  final String github;
  final String portfolio;
  final String linkedin;
  final String email;
  final String phone;
  final List<String> skills; // lowercase, from resume or typed
  final List<Project> projects;
  final String city;
  final String country;
  final String degree; // e.g. B.Sc, B.Tech, BCA, M.Tech
  final List<String> interests; // Interest.name values
  final String resumePath; // app-private copy of the resume PDF, attached to emails
  final String templateSubject; // '' = use the default "My template"
  final String templateBody;

  /// Raw lines from the resume's experience and achievements/certifications sections.
  final List<String> experience;
  final List<String> extras;
  final List<ResumeSection> resumeSections;

  bool get isEmpty => name.isEmpty && projects.isEmpty && skills.isEmpty;

  /// Everything you can claim: listed skills, every project tag, and what those clearly imply.
  Set<String> get allSkills {
    final all = {...skills, for (final p in projects) ...p.tags};
    if (all.any(const {'unity', 'unreal engine', 'godot'}.contains)) all.add('game development');
    for (final k in [...all]) {
      all.addAll(_implies[k] ?? const []);
    }
    return all;
  }

  StudentProfile copyWith({
    String? name,
    String? college,
    double? cgpa,
    int? graduationYear,
    String? github,
    String? portfolio,
    String? linkedin,
    String? email,
    String? phone,
    List<String>? skills,
    List<Project>? projects,
    String? city,
    String? country,
    String? degree,
    List<String>? interests,
    String? resumePath,
    String? templateSubject,
    String? templateBody,
    List<String>? experience,
    List<String>? extras,
    List<ResumeSection>? resumeSections,
  }) =>
      StudentProfile(
        name: name ?? this.name,
        college: college ?? this.college,
        cgpa: cgpa ?? this.cgpa,
        graduationYear: graduationYear ?? this.graduationYear,
        github: github ?? this.github,
        portfolio: portfolio ?? this.portfolio,
        linkedin: linkedin ?? this.linkedin,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        skills: skills ?? this.skills,
        projects: projects ?? this.projects,
        city: city ?? this.city,
        country: country ?? this.country,
        degree: degree ?? this.degree,
        interests: interests ?? this.interests,
        resumePath: resumePath ?? this.resumePath,
        templateSubject: templateSubject ?? this.templateSubject,
        templateBody: templateBody ?? this.templateBody,
        experience: experience ?? this.experience,
        extras: extras ?? this.extras,
        resumeSections: resumeSections ?? this.resumeSections,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'college': college,
        'cgpa': cgpa,
        'graduationYear': graduationYear,
        'github': github,
        'portfolio': portfolio,
        'linkedin': linkedin,
        'email': email,
        'phone': phone,
        'skills': skills,
        'projects': projects.map((p) => p.toJson()).toList(),
        'city': city,
        'country': country,
        'degree': degree,
        'interests': interests,
        'resumePath': resumePath,
        'templateSubject': templateSubject,
        'templateBody': templateBody,
        'experience': experience,
        'extras': extras,
        'resumeSections': [for (final r in resumeSections) r.toJson()],
      };

  factory StudentProfile.fromJson(Map j) => StudentProfile(
        name: j['name'] ?? '',
        college: j['college'] ?? '',
        cgpa: (j['cgpa'] as num?)?.toDouble(),
        graduationYear: j['graduationYear'],
        github: j['github'] ?? '',
        portfolio: j['portfolio'] ?? '',
        linkedin: j['linkedin'] ?? '',
        email: j['email'] ?? '',
        phone: j['phone'] ?? '',
        skills: List<String>.from(j['skills'] ?? const []),
        projects: [for (final p in (j['projects'] as List? ?? const [])) Project.fromJson(p)],
        city: j['city'] ?? '',
        country: j['country'] ?? '',
        degree: j['degree'] ?? '',
        interests: List<String>.from(j['interests'] ?? const []),
        resumePath: j['resumePath'] ?? '',
        templateSubject: j['templateSubject'] ?? '',
        templateBody: j['templateBody'] ?? '',
        experience: List<String>.from(j['experience'] ?? const []),
        extras: List<String>.from(j['extras'] ?? const []),
        resumeSections: [for (final r in (j['resumeSections'] as List? ?? const [])) ResumeSection.fromJson(r)],
      );
}

class ParsedRules {
  const ParsedRules({this.minCgpa, this.allowedBatches = const [], this.skills = const [], this.minYears = 0});

  final double? minCgpa;
  final List<int> allowedBatches; // empty = any
  final List<String> skills;

  /// "Experience: 2+ years": students can't meet it. 0 = none asked.
  final int minYears;

  Map<String, dynamic> toJson() => {'minCgpa': minCgpa, 'allowedBatches': allowedBatches, 'skills': skills, 'minYears': minYears};

  factory ParsedRules.fromJson(Map j) => ParsedRules(
        minCgpa: (j['minCgpa'] as num?)?.toDouble(),
        allowedBatches: List<int>.from(j['allowedBatches'] ?? const []),
        skills: List<String>.from(j['skills'] ?? const []),
        minYears: j['minYears'] ?? 0,
      );
}

class JobListing {
  const JobListing({
    required this.id,
    required this.company,
    required this.title,
    required this.applyTarget,
    this.location = '',
    this.description = '',
    this.rules = const ParsedRules(),
    this.postedAt,
    this.department = '',
    this.workplace = '',
    this.deadline,
    this.stipend = '',
    this.eligibleGroups = const [],
    this.applicants,
    this.source = '',
    this.sourceUrl = '',
  });

  final String id;
  final String company;
  final String title;

  /// URL or email address where the application goes.
  final String applyTarget;
  final String location;
  final String description; // plain text
  final ParsedRules rules;
  final DateTime? postedAt;
  final String department;
  final String workplace; // remote / hybrid / onsite, when the board says
  final DateTime? deadline;

  /// Display string from structured data ("₹12k–15k/month", "Unpaid"); '' when the source doesn't say.
  final String stipend;

  /// Who may apply, when the source lists it (Unstop: "Engineering Students", "Undergraduate"…).
  final List<String> eligibleGroups;

  /// How many people already applied, when the source says (Unstop does).
  final int? applicants;

  /// Where we found it, when the id prefix doesn't say enough ("Telegram · @goyalarsh", "Shared post").
  final String source;

  /// The original post (a Telegram message), to check the details.
  final String sourceUrl;

  JobListing copyWith({ParsedRules? rules, String? applyTarget}) => JobListing(
        id: id,
        company: company,
        title: title,
        applyTarget: applyTarget ?? this.applyTarget,
        location: location,
        description: description,
        rules: rules ?? this.rules,
        postedAt: postedAt,
        department: department,
        workplace: workplace,
        deadline: deadline,
        stipend: stipend,
        eligibleGroups: eligibleGroups,
        applicants: applicants,
        source: source,
        sourceUrl: sourceUrl,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'title': title,
        'applyTarget': applyTarget,
        'location': location,
        'description': description,
        'rules': rules.toJson(),
        'postedAt': postedAt?.toIso8601String(),
        'department': department,
        'workplace': workplace,
        'deadline': deadline?.toIso8601String(),
        'stipend': stipend,
        'eligibleGroups': eligibleGroups,
        'applicants': applicants,
        'source': source,
        'sourceUrl': sourceUrl,
      };

  factory JobListing.fromJson(Map j) => JobListing(
        id: j['id'],
        company: j['company'],
        title: j['title'],
        applyTarget: j['applyTarget'],
        location: j['location'] ?? '',
        description: j['description'] ?? '',
        rules: ParsedRules.fromJson(j['rules'] ?? const {}),
        postedAt: DateTime.tryParse(j['postedAt'] ?? ''),
        department: j['department'] ?? '',
        workplace: j['workplace'] ?? '',
        deadline: DateTime.tryParse(j['deadline'] ?? ''),
        stipend: j['stipend'] ?? '',
        eligibleGroups: List<String>.from(j['eligibleGroups'] ?? const []),
        applicants: j['applicants'],
        source: j['source'] ?? '',
        sourceUrl: j['sourceUrl'] ?? '',
      );
}

class Application {
  const Application({
    required this.job,
    required this.status,
    required this.updatedAt,
    this.to = '',
    this.subject = '',
    this.notes = '',
    this.body = '',
  });

  final JobListing job;
  final AppStatus status;
  final DateTime updatedAt;
  final String to;
  final String subject;
  final String notes;

  /// The message actually sent (or copied as a cover note), for the application page.
  final String body;

  Application copyWith({AppStatus? status, String? notes}) => Application(
        job: job,
        status: status ?? this.status,
        updatedAt: status == null ? updatedAt : DateTime.now(),
        to: to,
        subject: subject,
        notes: notes ?? this.notes,
        body: body,
      );

  Map<String, dynamic> toJson() => {
        'job': job.toJson(),
        'status': status.name,
        'updatedAt': updatedAt.toIso8601String(),
        'to': to,
        'subject': subject,
        'notes': notes,
        'body': body,
      };

  factory Application.fromJson(Map j) => Application(
        job: JobListing.fromJson(j['job']),
        status: AppStatus.values.byName(j['status']),
        updatedAt: DateTime.parse(j['updatedAt']),
        to: j['to'] ?? '',
        subject: j['subject'] ?? '',
        notes: j['notes'] ?? '',
        body: j['body'] ?? '',
      );
}

/// Knowing one means you can honestly say you know the other.
const _implies = {
  'flutter': ['dart'],
  'react': ['javascript'],
  'next.js': ['react', 'javascript'],
  'vue': ['javascript'],
  'angular': ['typescript', 'javascript'],
  'typescript': ['javascript'],
  'node.js': ['javascript'],
  'django': ['python'],
  'flask': ['python'],
  'fastapi': ['python'],
  'spring': ['java'],
  'pandas': ['python'],
};
