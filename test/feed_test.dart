import 'package:flutter_test/flutter_test.dart';
import 'package:proof_pitch/feed.dart';
import 'package:proof_pitch/models.dart';

final _now = DateTime(2026, 10, 4);

JobListing _job(String id, String title,
        {String company = 'Tiny Labs', int daysOld = 3, int? applicants, String location = 'Remote, India', String stipend = '', DateTime? deadline}) =>
    JobListing(
      id: id,
      company: company,
      title: title,
      applyTarget: 'https://unstop.com/x',
      location: location,
      postedAt: _now.subtract(Duration(days: daysOld)),
      applicants: applicants,
      stipend: stipend,
      deadline: deadline,
    );

void main() {
  test('only jobs from the last 3 months that are still open', () {
    expect(isFresh(_job('gh-1', 'Intern', daysOld: 10), _now), isTrue);
    expect(isFresh(_job('gh-1', 'Intern', daysOld: 100), _now), isFalse);
    expect(isFresh(_job('gh-1', 'Intern', deadline: _now.subtract(const Duration(days: 1))), _now), isFalse);
    expect(isFresh(const JobListing(id: 'gh-2', company: 'A', title: 'Intern', applyTarget: 'x'), _now), isFalse, reason: 'unknown age');
    expect(isFresh(const JobListing(id: 'manual-1', company: 'A', title: 'Intern', applyTarget: 'x'), _now), isTrue);
  });

  test('stipend → monthly rupees', () {
    expect(monthlyInr('₹12k–15k/month'), 12000);
    expect(monthlyInr('₹5,000/month'), 5000);
    expect(monthlyInr('₹2k/week'), 8000);
    expect(monthlyInr('Unpaid'), isNull);
    expect(monthlyInr(r'$2000/month'), isNull);
  });

  test('fields are read from the title', () {
    expect(interestsOf(_job('a', 'Flutter Developer Intern')), contains(Interest.mobile));
    expect(interestsOf(_job('a', 'Digital Marketing Intern')), {Interest.marketing});
    expect(interestsOf(_job('a', 'Data Analyst Intern')), contains(Interest.data));
  });

  test('field matching uses whole words (the "comm-unity is game dev" bug)', () {
    expect(interestsOf(_job('a', 'Community Lead Internship')), isNot(contains(Interest.game)));
    expect(interestsOf(_job('a', 'Unity Developer Intern')), contains(Interest.game));
    expect(interestsOf(_job('a', 'AR/VR Intern')), contains(Interest.game));
    expect(interestsOf(_job('a', 'VLSI Design Internship')), isNot(contains(Interest.design)));
    expect(interestsOf(_job('a', 'Maintenance Intern')), isNot(contains(Interest.data)), reason: '"ai" inside a word');
    expect(interestsOf(_job('a', 'Contest Coordinator')), isNot(contains(Interest.qa)));
    // The title decides; the board's noisy category list is only a fallback.
    const tagged = JobListing(id: 'us-9', company: 'X', title: 'Brand Ambassador Internship', applyTarget: 'x', department: 'AI Engineering, Digital Marketing');
    expect(interestsOf(tagged), {Interest.marketing});
    const untitled = JobListing(id: 'us-8', company: 'X', title: 'Internship', applyTarget: 'x', department: 'Mobile App Development');
    expect(interestsOf(untitled), {Interest.mobile});
  });

  test('search terms: interests first, then project tags and skills', () {
    const p = StudentProfile(interests: ['mobile'], skills: ['python']);
    expect(searchTermsFor(p).take(3), ['flutter', 'android', 'python']);
  });

  final me = const StudentProfile(name: 'A', interests: ['mobile'], country: 'India');
  final easy = _job('us-1', 'Flutter Intern', applicants: 40, daysOld: 2);
  final crowded = _job('gh-2', 'Android Developer Intern', company: 'Google', applicants: 9000, daysOld: 40, location: 'Bengaluru, India');
  final marketing = _job('us-3', 'Social Media Marketing Intern', applicants: 300, daysOld: 5);

  test('default feed follows your fields', () {
    final r = rankFeed([easy, crowded, marketing], me, const FeedFilter(), now: _now);
    expect(r.map((e) => e.job.id), containsAll(['us-1', 'gh-2']));
    expect(r.any((e) => e.job.id == 'us-3'), isFalse);
  });

  test('need-one-fast: any field, last 30 days, easiest doors first', () {
    final r = rankFeed([crowded, marketing, easy], me, FeedFilter.fast, now: _now);
    expect(r.map((e) => e.job.id), ['us-1', 'us-3'], reason: 'the 40-day-old big-company post drops out');
    expect(easeScore(me, easy, _now), greaterThan(easeScore(me, crowded, _now)));
  });

  test('how to apply: email (post or checked website) or their own careers page', () {
    const inPost = JobListing(id: 'us-10', company: 'Tiny Labs', title: 'Flutter Intern', applyTarget: 'https://unstop.com/x',
        description: 'Send your resume to hr@tinylabs.in');
    final checked = _job('us-11', 'Flutter Intern', company: 'Zethic Technologies LLP');
    final board = JobListing(id: 'gh-12', company: 'Groww', title: 'Flutter Intern', applyTarget: 'https://boards.greenhouse.io/groww/1', postedAt: _now);
    final none = _job('us-13', 'Flutter Intern', company: 'Nobody Inc');
    final jobs = [inPost, checked, board, none];
    const email = FeedFilter(applyVia: ApplyVia.email);
    expect(rankFeed(jobs, me, email, now: _now, emailCompanies: {'Zethic Technologies'}).map((e) => e.job.id), containsAll(['us-10', 'us-11']));
    expect(rankFeed(jobs, me, email, now: _now, emailCompanies: {'Zethic Technologies'}).length, 2);
    expect(rankFeed(jobs, me, const FeedFilter(applyVia: ApplyVia.careersPage), now: _now).single.job.id, 'gh-12');
    expect(postHasEmail(const JobListing(id: 'x', company: 'A', title: 'B', applyTarget: 'x', description: 'Questions? privacy@a.com')), isFalse);
  });

  test('filters: stipend floor, work mode, sort by fewest applicants', () {
    final paid = _job('us-4', 'Flutter Intern', stipend: '₹15k/month', applicants: 900);
    final low = _job('us-5', 'Flutter Intern', stipend: '₹3k/month', applicants: 20);
    expect(rankFeed([paid, low], me, const FeedFilter(minStipend: 10000), now: _now).single.job.id, 'us-4');
    expect(rankFeed([paid, low, crowded], me, const FeedFilter(mode: WorkMode.remote), now: _now).length, 2);
    expect(rankFeed([paid, low], me, const FeedFilter(sort: SortBy.fewest), now: _now).first.job.id, 'us-5');
    expect(const FeedFilter(minStipend: 5000, sort: SortBy.newest).advancedCount, 2);
  });
}
