import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'engines.dart';
import 'models.dart';

// ───────────────────────── Your resume, rebuilt (and tailored to one job) ─────────────────────────
// Same facts as the student's resume, nothing dropped, nothing invented. For a job, it's reordered:
// the job's skills first, the projects that prove them first (most relevant bullets first), and a
// headline/summary naming the role. Every other section of the original (experience, education,
// certifications, leadership…) is carried over word for word, in the original order.

class TailoredProject {
  const TailoredProject(this.project, this.bullets, this.matched);
  final Project project;
  final List<String> bullets;
  final List<String> matched; // job skills this project proves
}

class TailoredResume {
  const TailoredResume({
    this.skillLines = const [],
    this.profileUrl = '',
    required this.name,
    required this.headline,
    required this.contact,
    required this.summary,
    required this.relevantSkills,
    required this.otherSkills,
    required this.projects,
    required this.sections,
  });
  final String name, headline, contact, summary;
  final List<String> relevantSkills, otherSkills;

  /// The resume's own skills section as written ("Technical Skills: …", "Languages: …"); replaces [otherSkills] when present.
  final List<String> skillLines;

  /// Projects whose link is just this profile (no repo/demo of their own) don't print it again.
  final String profileUrl;
  final List<TailoredProject> projects;

  /// Everything else from the resume, as written (headings included).
  final List<ResumeSection> sections;
}

const _rebuilt = {'skills', 'projects', 'summary'}; // sections the generator writes itself

/// [job] null = the student's own resume, rebuilt from the profile (what the resume editor saves).
TailoredResume tailorResume(StudentProfile s, [JobListing? job]) {
  final want = job?.rules.skills.toSet() ?? const <String>{};
  final mine = s.allSkills;
  final relevant = [for (final k in job?.rules.skills ?? const <String>[]) if (mine.contains(k) && skillKeywords.contains(k)) k];
  final ordered = {...s.skills, for (final p in s.projects) ...p.tags}.where((k) => !relevant.contains(k));
  final other = [...ordered.where(skillKeywords.contains), ...ordered.where((k) => !skillKeywords.contains(k) && !isToolNotSkill(k))];

  int hits(String text) => scanSkills(text).where(want.contains).length;
  final scored = [
    for (final (i, p) in s.projects.indexed)
      (i, TailoredProject(p, [...p.bullets]..sort((a, b) => hits(b).compareTo(hits(a))), [for (final t in p.tags) if (want.contains(t)) t])),
  ]..sort((a, b) {
      final c = (b.$2.matched.length * 3 + b.$2.bullets.fold(0, (n, x) => n + hits(x)))
          .compareTo(a.$2.matched.length * 3 + a.$2.bullets.fold(0, (n, x) => n + hits(x)));
      return c != 0 ? c : a.$1.compareTo(b.$1); // keep the student's order on ties (and always, with no job)
    });
  final projects = [for (final e in scored) e.$2];
  // "Built … with X" only for skills a project actually shows (not Git, which every repo "uses").
  final shown = job == null ? [for (final p in s.projects) ...p.tags] : relevant;
  final proven = {for (final k in shown) if (s.projects.any((p) => p.tags.contains(k)) && k != 'git' && skillKeywords.contains(k)) k}.toList();

  final role = job == null ? '' : roleNoun(job.title);
  final y = s.graduationYear;
  final top = projects.firstOrNull?.project;
  final original = s.resumeSections.where((x) => x.kind == 'summary').expand((x) => x.lines).join(' ').trim();
  // Their own words lead when the resume has a summary; a job only adds one line naming it.
  final applying = job != null && role.isNotEmpty ? 'Applying for the $role internship at ${cleanCompany(job.company)}.' : '';
  final summary = original.isNotEmpty
      ? [original, applying].where((x) => x.isNotEmpty).join(' ')
      : '${[
          [
            if (s.degree.isNotEmpty) '${s.degree} student' else 'Student',
            if (s.college.isNotEmpty) 'at ${s.college}',
            if (y != null) (y < DateTime.now().year ? '($y graduate)' : '(graduating $y)'),
          ].join(' '),
          if (top != null)
            'Built ${s.projects.length == 1 ? 'a project' : '${s.projects.length} projects'}'
                '${proven.isEmpty ? '' : ' with ${andList(proven.take(3).map(displaySkill).toList())}'}, including ${top.name}'
                '${top.oneLiner.isEmpty ? '' : ' (${top.oneLiner})'}',
          if (job != null && role.isNotEmpty) 'Applying for the $role internship at ${cleanCompany(job.company)}',
        ].join('. ')}.';

  // Old profiles (imported before sections were kept) fall back to the few fields we had.
  final sections = s.resumeSections.isNotEmpty
      ? [for (final x in s.resumeSections) if (!_rebuilt.contains(x.kind)) x]
      : [
          if (s.experience.isNotEmpty) ResumeSection('Experience', 'experience', s.experience),
          ResumeSection('Education', 'education', [
            if (s.college.isNotEmpty) s.college,
            [s.degree, if (y != null) '$y', if (s.cgpa != null && s.cgpa! >= 7) 'CGPA ${s.cgpa}'].where((e) => e.isNotEmpty).join('  |  '),
          ]),
          if (s.extras.isNotEmpty) ResumeSection('Achievements', 'other', [for (final e in s.extras) '• $e']),
        ];

  final headSkills = (relevant.isNotEmpty ? relevant : other).take(4).map(displaySkill);
  return TailoredResume(
    name: s.name,
    headline: [if (role.isNotEmpty) '$role Intern', ...headSkills].join('  |  '),
    contact: [s.phone, s.email, s.city, if (s.linkedin.isNotEmpty) shortUrl(s.linkedin), if (s.github.isNotEmpty) shortUrl(s.github), if (s.portfolio.isNotEmpty) shortUrl(s.portfolio)]
        .where((e) => e.isNotEmpty)
        .join('  |  '),
    summary: summary,
    relevantSkills: relevant.map(displaySkill).toList(),
    otherSkills: other.map(displaySkill).toList(),
    skillLines: [for (final x in s.resumeSections) if (x.kind == 'skills') ...x.lines],
    profileUrl: s.github,
    projects: projects,
    sections: [for (final x in sections) if (x.lines.any((l) => l.trim().isNotEmpty)) x],
  );
}

/// The built-in font's encoding drops typographic punctuation and anything non-Latin, so those become plain ASCII.
String _latin(String s) => s
    .replaceAll('₹', 'Rs ')
    .replaceAll(RegExp('[✓✔➢▪●◦•–—]'), '-')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('…', '...')
    .replaceAll(RegExp('[^\\x20-\\x7E\\u00A0-\\u00FF]'), '');

final _bulletGlyph = RegExp(r'^\s*[•●▪◦\-*–>➢✓]\s*');

/// One clean single-column PDF: ATS parsers read it top to bottom without surprises.
Future<List<int>> resumePdfBytes(TailoredResume r) async {
  final doc = PdfDocument();
  doc.pageSettings.size = PdfPageSize.a4;
  doc.pageSettings.margins.all = 40;
  var page = doc.pages.add();
  final w = page.getClientSize().width;
  final title = PdfStandardFont(PdfFontFamily.helvetica, 21, style: PdfFontStyle.bold);
  final head = PdfStandardFont(PdfFontFamily.helvetica, 11.5, style: PdfFontStyle.bold);
  final body = PdfStandardFont(PdfFontFamily.helvetica, 10.5);
  final strong = PdfStandardFont(PdfFontFamily.helvetica, 10.5, style: PdfFontStyle.bold);
  final grey = PdfSolidBrush(PdfColor(90, 90, 90));
  final fmt = PdfStringFormat(lineSpacing: 2.5);
  var y = 0.0;

  void text(String t, PdfFont f, {double indent = 0, double gap = 3, PdfBrush? brush}) {
    if (t.trim().isEmpty) return;
    final res = PdfTextElement(text: _latin(t), font: f, brush: brush, format: fmt)
        .draw(page: page, bounds: Rect.fromLTWH(indent, y, w - indent, 0), format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate))!;
    page = res.page;
    y = res.bounds.bottom + gap;
  }

  void section(String t) {
    y += 10;
    text(t.toUpperCase(), head, gap: 2);
    page.graphics.drawLine(PdfPen(PdfColor(0, 0, 0), width: 0.7), Offset(0, y), Offset(w, y));
    y += 6;
  }

  void bullet(String t) => text('-   $t', body, indent: 10, gap: 2.5);

  text(r.name, title, gap: 4);
  if (r.headline.isNotEmpty) text(r.headline, strong, gap: 3);
  text(r.contact, body, brush: grey, gap: 4);
  if (r.summary.isNotEmpty) {
    section('Summary');
    text(r.summary, body);
  }
  if (r.relevantSkills.isNotEmpty || r.otherSkills.isNotEmpty || r.skillLines.isNotEmpty) {
    section('Skills');
    if (r.relevantSkills.isNotEmpty) text('Relevant to this role: ${r.relevantSkills.join(', ')}', strong);
    if (r.skillLines.isNotEmpty) {
      for (final l in r.skillLines) {
        text(l, body, gap: 2.5);
      }
    } else if (r.otherSkills.isNotEmpty) {
      text('${r.relevantSkills.isEmpty ? '' : 'Also: '}${r.otherSkills.join(', ')}', body);
    }
  }
  if (r.projects.isNotEmpty) {
    section('Projects');
    for (final p in r.projects) {
      final tags = [...p.matched, ...p.project.tags.where((t) => !p.matched.contains(t))].take(6).map(displaySkill).join(', ');
      text('${p.project.name}${tags.isEmpty ? '' : '   |   $tags'}', strong, gap: 1.5);
      if (p.project.url.isNotEmpty && shortUrl(p.project.url) != shortUrl(r.profileUrl)) text(shortUrl(cleanUrl(p.project.url)), body, brush: grey, gap: 2.5);
      if (p.bullets.isEmpty && p.project.oneLiner.isNotEmpty) bullet(p.project.oneLiner);
      for (final b in p.bullets) {
        bullet(b);
      }
      y += 5;
    }
  }
  for (final sec in r.sections) {
    section(sec.title);
    for (final l in sec.lines) {
      if (_bulletGlyph.hasMatch(l)) {
        bullet(l.replaceFirst(_bulletGlyph, ''));
      } else {
        text(l, body, gap: 2.5);
      }
    }
  }
  final bytes = await doc.save();
  doc.dispose();
  return bytes;
}

String _safe(String x) => x.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

/// Writes the PDF to app storage and returns its path ("Kashif_Mukaddam_Resume_Zethic.pdf", or
/// "Kashif_Mukaddam_Resume.pdf" without a job). Null on web.
Future<String?> writeTailoredResume(StudentProfile s, [JobListing? job]) async {
  if (kIsWeb) return null;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/${job == null ? 'resume_edited' : 'tailored'}')
    ..createSync(recursive: true);
  final name = '${_safe(s.name.isEmpty ? 'Resume' : s.name)}_Resume${job == null ? '' : '_${_safe(cleanCompany(job.company))}'}.pdf';
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(await resumePdfBytes(tailorResume(s, job)), flush: true);
  return f.path;
}
