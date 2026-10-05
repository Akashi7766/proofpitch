import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../feed.dart';
import '../theme.dart';

/// Where else to look, opened in the real apps where the student browses as themselves. Nothing is scraped:
/// LinkedIn, Internshala and Reddit don't allow it. Anything good comes back via Share → ProofPitch.
class _Spot {
  const _Spot(this.emoji, this.title, this.why, this.url);
  final String emoji, title, why, url;
}

List<_Spot> _spots(String kw, {bool game = false}) {
  String e(String s) => Uri.encodeComponent(s);
  return [
    _Spot('💼', 'LinkedIn posts: "hiring intern $kw"', 'Founders post here before any job board. Newest first.',
        'https://www.linkedin.com/search/results/content/?keywords=${e('hiring intern $kw')}&sortBy=%22date_posted%22'),
    _Spot('🧑‍💻', 'LinkedIn jobs: $kw internships in India', 'Internship level, posted this week.',
        'https://www.linkedin.com/jobs/search/?keywords=${e('$kw intern')}&location=India&f_E=1&f_TPR=r604800'),
    _Spot('🎓', 'Internshala: $kw', "India's biggest internship board.", 'https://internshala.com/internships/keywords-${e(kw.replaceAll(' ', '-'))}/'),
    _Spot('🇮🇳', 'r/developersIndia: hiring posts', 'Indian startups posting roles; many take interns.',
        'https://www.reddit.com/r/developersIndia/search/?q=${e('hiring intern')}&restrict_sr=1&sort=new'),
    if (game)
      const _Spot('🎮', 'r/gameDevClassifieds: [PAID] posts', 'Indie studios. Stick to [PAID]; rev-share rarely counts for college.',
          'https://www.reddit.com/r/gameDevClassifieds/search/?q=%5BPAID%5D&restrict_sr=1&sort=new'),
    _Spot('𝕏', 'X: "hiring intern $kw"', 'Founders tweet openings; reply or DM.', 'https://x.com/search?q=${e('hiring intern $kw')}&f=live'),
    _Spot('🚀', 'Startups on Wellfound', 'Startup jobs; many reply to a short note.',
        'https://www.google.com/search?q=${e('$kw intern India site:wellfound.com')}&tbs=qdr:m'),
    _Spot('🔎', 'Company careers pages (past week)', 'Roles posted on companies\' own sites.',
        'https://www.google.com/search?q=${e('"$kw" intern India careers apply')}&tbs=qdr:w'),
  ];
}

Future<void> showLeadsSheet(BuildContext context, WidgetRef ref) {
  final profile = ref.read(profileProvider);
  final terms = {...searchTermsFor(profile).take(4)}.toList();
  if (terms.isEmpty) terms.add('software');
  final game = profile.interests.contains(Interest.game.name) || profile.allSkills.contains('unity');
  var kw = terms.first;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.cream,
    shape: const Border(top: border),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
          Text('Find more leads', style: display(24)),
          const SizedBox(height: 6),
          const Text('Opens in the app or browser, as you. Found one? Tap Share → ProofPitch there and it comes straight back here, ready to pitch.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in terms) BrutalChip(t, selected: t == kw, color: C.lime, onTap: () => setSheet(() => kw = t)),
          ]),
          const SizedBox(height: 14),
          for (final s in _spots(kw, game: game))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Brutal(
                onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Text(s.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title, style: display(13)),
                      Text(s.why, style: const TextStyle(color: muted, fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.open_in_new_rounded, size: 18),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          const Text('⚠️ Real employers never ask you to pay a fee, buy a course or send money. Skip anyone who does.',
              style: TextStyle(fontSize: 13)),
        ]),
      ),
    ),
  );
}
