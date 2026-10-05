import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/engines.dart';
import 'package:proof_pitch/feed.dart';
import 'package:proof_pitch/models.dart';
import 'package:proof_pitch/telegram.dart';

/// A t.me/s/ page in Telegram's markup, with posts written the way real Indian job channels write them.
String _page(String channel, List<(int, String)> posts) => [
      for (final (id, text) in posts)
        '<div class="tgme_widget_message_wrap js-widget_message_wrap"><div class="tgme_widget_message js-widget_message" data-post="$channel/$id">'
            '<div class="tgme_widget_message_text js-message_text" dir="auto">$text</div>'
            '<span class="tgme_widget_message_meta"><a class="tgme_widget_message_date" href="https://t.me/$channel/$id">'
            '<time datetime="2026-10-04T10:00:00+00:00" class="time">10:00</time></a></span></div></div>',
    ].join('\n');

const _join = '<br/><br/>✅ Join Our Telegram Group- <a href="https://telegram.me/somejobs">https://telegram.me/somejobs</a>'
    '<br/>Join for more opportunities: <a href="https://whatsapp.com/channel/abc">https://whatsapp.com/channel/abc</a>';

void main() {
  test('labelled posts: company, role, batch, location, apply link; tagged with the channel', () {
    final html = _page('jobsupdates', [
      (
        7401,
        'Company name: Smytten<br/>Role: SDE Intern<br/>Batch Eligible: 2027 &amp; 2028 graduates<br/>Location: Bengaluru<br/><br/>'
            'Apply Link: <a href="https://www.linkedin.com/jobs/view/4471337817/">https://www.linkedin.com/jobs/view/4471337817/</a>$_join'
      ),
    ]);
    final p = parseTelegramPage('jobsupdates', html);
    final j = p.jobs.single;
    expect(j.company, 'Smytten');
    expect(j.title, 'SDE Intern');
    expect(j.location, 'Bengaluru');
    expect(j.rules.allowedBatches, [2027, 2028]);
    expect(j.applyTarget, 'https://www.linkedin.com/jobs/view/4471337817/', reason: 'never the channel\'s WhatsApp/Telegram promo');
    expect(j.source, 'Telegram · @jobsupdates');
    expect(j.sourceUrl, 'https://t.me/jobsupdates/7401');
    expect(j.postedAt, DateTime.utc(2026, 10, 4, 10));
    expect(sourceLabel(j), '✈️ Telegram @jobsupdates');
    expect(p.oldestId, 7401);
  });

  test('"X is hiring for Y" posts with several jobs each; experience-only roles are flagged', () {
    final html = _page('dotjobs', [
      (
        15000,
        '📌FarEye is hiring for Associate Solutions Engineer<br/>Batch: 2026, 2027<br/>Salary: 4.5 LPA<br/>'
            'Apply here: <a href="https://go.acciojob.com/fEh2Sx">https://go.acciojob.com/fEh2Sx</a><br/><br/>'
            '📌Cisco is hiring for Software Engineer<br/>Experience: 5+ years<br/>Salary: 28-35 LPA<br/>'
            'Apply here: <a href="https://careers.cisco.com/job/1?utm_source=linkedin">https://careers.cisco.com/job/1?utm_source=linkedin</a>'
      ),
    ]);
    final jobs = parseTelegramPage('dotjobs', html).jobs;
    expect(jobs.map((j) => j.company), ['FarEye', 'Cisco']);
    expect(jobs.first.stipend, '4.5 LPA');
    expect(jobs.last.rules.minYears, 5);
    expect(jobs.last.applyTarget, 'https://careers.cisco.com/job/1', reason: 'tracking params cleaned');
    expect(isEligible(const StudentProfile(), jobs.last), isFalse, reason: 'students have no work years');
    expect(isEligible(const StudentProfile(), jobs.first), isTrue);
  });

  test('headline posts ("X Recruitment 2026: Role | City", fancy bold letters) and ads are told apart', () {
    final html = _page('offcampus', [
      (1, 'Reliance Jio Off Campus Drive 2026: Graduate Engineer Trainee | Mumbai<br/><br/>Apply Link- <a href="https://offcampus.example/jio">https://offcampus.example/jio</a>$_join'),
      (2, 'Oculon Software Engineering Intern 2026 – Remote | ₹10,000/Month<br/><br/>Apply Link- <a href="https://offcampus.example/oculon">https://offcampus.example/oculon</a>'),
      (3, '🚀 𝗗𝗲𝗹𝗼𝗶𝘁𝘁𝗲 𝗥𝗲𝗰𝗿𝘂𝗶𝘁𝗺𝗲𝗻𝘁 𝗗𝗿𝗶𝘃𝗲 | 𝗔𝗽𝗽𝗹𝘆 𝗡𝗼𝘄<br/>💼 Roles: Tech &amp; Non-Tech<br/>📍 Location: PAN India<br/>https://tinyurl.com/5yuxa6uh'),
      (4, 'FREE 3 hour AI workshop happening today!<br/>Register now: <a href="https://link.example/a">https://link.example/a</a>'),
      (5, 'Do you want to learn about the FDE role? A FREE report to download: https://tinyurl.com/fde-report'),
      (6, 'Krishan Kumar - Jobs pinned «Last 1 day left to apply»'),
    ]);
    final jobs = parseTelegramPage('offcampus', html).jobs;
    expect(jobs.map((j) => '${j.company} | ${j.title} | ${j.location}'), [
      'Reliance Jio | Graduate Engineer Trainee | Mumbai',
      'Oculon | Software Engineering Intern | Remote',
      'Deloitte | Tech & Non-Tech | India',
    ]);
    expect(plainLetters('𝗗𝗲𝗹𝗼𝗶𝘁𝘁𝗲 𝟮𝟬𝟮𝟲'), 'Deloitte 2026');
  });

  test('channel names from whatever the student pastes', () {
    expect(telegramName('@GoyalArsh'), 'goyalarsh');
    expect(telegramName('https://t.me/s/goyalarsh/6371'), 'goyalarsh');
    expect(telegramName('t.me/jobs_and_internships_updates'), 'jobs_and_internships_updates');
    expect(telegramName('not a channel!'), isNull);
  });

  test('years of experience are read from the wording students actually see', () {
    expect(minYearsIn('Experience: 2+ years'), 2);
    expect(minYearsIn('Engineer in Bangalore | 1+ Year'), 1);
    expect(minYearsIn('3-5 years of relevant experience'), 3);
    expect(minYearsIn('Experience: Freshers'), 0);
    expect(minYearsIn('0-1 years of experience'), 0);
    expect(minYearsIn('A 6 month internship'), 0);
  });

  test('every job says where it came from', () {
    JobListing j(String id, {String source = ''}) => JobListing(id: id, company: 'A', title: 'B', applyTarget: 'x', source: source);
    expect(sourceLabel(j('us-1')), '🟣 Unstop');
    expect(sourceLabel(j('lv-1')), '🏢 Careers page · Lever');
    expect(sourceLabel(j('manual-1', source: 'Shared post')), '🔗 Shared post');
    expect(sourceLabel(j('manual-2', source: 'Added by you')), '✍️ Added by you');
    expect(onCareersPage(j('tg-x-1-0')), isFalse, reason: 'a Telegram repost is not the company\'s own page');
  });
}
