import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proof_pitch/data.dart';
import 'package:proof_pitch/feed.dart' show isInternship;

void main() {
  test('htmlToText handles Greenhouse double-escaped HTML', () {
    expect(htmlToText('&lt;p&gt;Hi &amp;amp; welcome&lt;/p&gt;&lt;ul&gt;&lt;li&gt;Flutter&lt;/li&gt;&lt;/ul&gt;'), 'Hi & welcome\n\n• Flutter');
  });

  test('fetchBoard parses each provider and isInternship filters titles', () async {
    final client = MockClient((req) async {
      final body = switch (req.url.host) {
        'boards-api.greenhouse.io' => {
            'jobs': [
              {'id': 1, 'title': 'Data Science Intern (2027)', 'absolute_url': 'https://boards.greenhouse.io/x/1', 'company_name': 'Figma',
                'location': {'name': 'SF'}, 'content': '&lt;p&gt;Python, CGPA 8.0, 2027 batch&lt;/p&gt;'},
              {'id': 2, 'title': 'IT Engineer, Internal AI', 'absolute_url': 'u', 'location': null, 'content': ''},
            ],
          },
        'api.lever.co' => [
            {'id': 'a', 'text': 'Android Intern', 'hostedUrl': 'https://jobs.lever.co/s/a', 'categories': {'location': 'London'},
              'descriptionPlain': 'Kotlin', 'lists': [{'text': 'Needs', 'content': '<li>Java</li>'}], 'additionalPlain': ''},
          ],
        _ => {
            'jobs': [{'id': 'z', 'title': 'Design Intern', 'jobUrl': 'https://jobs.ashbyhq.com/r/z', 'location': 'NYC', 'descriptionPlain': 'Figma', 'isListed': true}],
          },
      };
      return http.Response(jsonEncode(body), 200);
    });

    final gh = await fetchBoard('greenhouse:figma', client: client);
    expect(gh.first.rules.minCgpa, 8.0);
    expect(gh.first.rules.allowedBatches, [2027]);
    expect(gh.first.location, 'SF');
    expect(gh.where(isInternship).length, 1, reason: '"Internal" is not an internship');

    final lv = await fetchBoard('lever:spotify', client: client);
    expect(lv.single.company, 'Spotify');
    expect(lv.single.rules.skills, containsAll(['kotlin', 'java', 'android']));

    final ab = await fetchBoard('ashby:ramp', client: client);
    expect(ab.single.applyTarget, 'https://jobs.ashbyhq.com/r/z');
  });
}
