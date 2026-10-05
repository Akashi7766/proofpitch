import 'engines.dart';
import 'insights.dart' show ageLabel;
import 'models.dart';

// ───────────────────────── After you apply ─────────────────────────
// What to do next, what to prepare if they reply, what to ask them, what should worry you,
// and replies ready to send. Pure, so it's tested like the rest of the rules.

class ReplyTemplate {
  const ReplyTemplate(this.when, this.subject, this.body);
  final String when; // "They want a call"
  final String subject;
  final String body;
}

class FollowUpKit {
  const FollowUpKit({required this.nextStep, required this.prep, required this.askThem, required this.redFlags, required this.replies});
  final String nextStep;
  final List<String> prep;
  final List<String> askThem;
  final List<String> redFlags;
  final List<ReplyTemplate> replies;
}

const followUpAfterDays = 5;

FollowUpKit followUpKit(Application a, StudentProfile s, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final job = a.job;
  final company = cleanCompany(job.company);
  final first = s.firstName;
  final cold = job.source == 'Cold pitch';
  final role = cold ? 'internship' : job.title;
  final days = n.difference(a.updatedAt).inDays;
  final sentOn = '${a.updatedAt.day}/${a.updatedAt.month}';
  final re = a.subject.isEmpty ? '$role - ${s.name}' : 'Re: ${a.subject}';

  final nextStep = switch (a.status) {
    AppStatus.draft => "You haven't sent it yet. Finish it, send it, then mark it Sent.",
    AppStatus.sent when days >= followUpAfterDays => "It's been $days days. Send the short follow-up below today; most replies come after a nudge.",
    AppStatus.sent => 'Sent ${ageLabel(a.updatedAt, n)}. Give them ${followUpAfterDays - days} more day${followUpAfterDays - days == 1 ? '' : 's'}, '
        'then send the follow-up below. Meanwhile, prepare as if they\'ll reply.',
    AppStatus.followedUp => 'You\'ve nudged once. One more after a week at most, then move on; keep applying elsewhere meanwhile.',
    AppStatus.replied => 'They replied! Answer within 24 hours. Pick the reply that fits below and prepare using the checklist.',
    AppStatus.rejected => 'Thank them anyway (reply below) and ask to be kept in mind. Small teams remember polite people.',
  };

  // Prepare: the projects that match this job, the skills they want, and honest lines for the gaps.
  final want = techSkills(job.rules.skills);
  final have = [for (final k in want) if (s.allSkills.contains(k)) displaySkill(k)];
  final missing = [for (final k in want) if (!s.allSkills.contains(k)) displaySkill(k)];
  final projects = ([...s.projects]..sort((p, q) => q.tags.where(want.contains).length.compareTo(p.tags.where(want.contains).length))).take(2);
  final prep = [
    for (final p in projects) 'Walk through ${p.name} in 2 minutes: what it does, what you built, one hard problem you solved, what you\'d do next.',
    if (have.isNotEmpty) 'Brush up on ${andList(have.take(4).toList())}: expect "how would you…" questions on these.',
    if (missing.isNotEmpty) 'They also want ${andList(missing.take(3).toList())}. Don\'t bluff: say what you know and how you\'d learn it fast.',
    'Know what $company does. Open their website and app before the call, and have one honest thing you like about it.',
    'Keep your resume, GitHub and a working demo link open during the call.',
  ];

  final askThem = [
    'What would I work on in the first month, and who would I work with?',
    if (job.stipend.isEmpty || cold) 'Is it paid? What\'s the stipend and how long is the internship?',
    if (workplaceOf(job).isEmpty || cold) 'Is it remote, hybrid or in the office? What are the hours?',
    'Will I get an offer letter and a completion certificate? (My college needs these for internship credit.)',
    'Is there a chance of a PPO or full-time role after the internship?',
  ];

  const redFlags = [
    'They ask you to pay anything: registration, training, a "security deposit", a course or a laptop. Real internships never charge you.',
    'They want Aadhaar, PAN or bank details before you have a written offer.',
    'Only a WhatsApp number: no company email, website or LinkedIn page.',
    'Unpaid with no offer letter or certificate: only worth it if it\'s short and you\'ll learn a lot.',
    '"Guaranteed placement" if you buy a programme.',
  ];

  final team = '$company team';
  final replies = [
    ReplyTemplate('They want a call or interview', re,
        "Hi $team,\n\nThank you for getting back to me! I'd be glad to talk. I'm free [days and times], and happy to work around your schedule.\n\nLooking forward to it,\n$first"),
    ReplyTemplate('Before saying yes, ask the details', re,
        "Hi $team,\n\nThanks so much for considering me. Before we go ahead, could you share a few details: the stipend and duration, whether it's remote or in the office, and whether there's an offer letter and completion certificate? My college needs these for internship credit.\n\nThanks,\n$first"),
    ReplyTemplate('No reply after $followUpAfterDays days', re,
        "Hi $team,\n\nJust following up on my note from $sentOn about the $role${cold ? '' : ' role'}. I'm still very interested, and happy to do a short task if that helps you decide.\n\nThanks,\n$first"),
    ReplyTemplate('They sent an assignment', re,
        "Hi $team,\n\nThanks for sending this over! I'll have it back to you by [date]. One quick question before I start: [your question].\n\nBest,\n$first"),
    ReplyTemplate('After the interview', 'Thank you - ${s.name}',
        "Hi $team,\n\nThank you for your time today. I enjoyed hearing about $company's work, especially [something you discussed]. Happy to share anything else you need.\n\nBest,\n$first"),
    ReplyTemplate('They said no', re,
        "Hi $team,\n\nThank you for letting me know, and for considering me. If anything opens up later, I'd love to be kept in mind.\n\nBest,\n$first"),
  ];

  return FollowUpKit(nextStep: nextStep, prep: prep, askThem: askThem, redFlags: redFlags, replies: replies);
}
