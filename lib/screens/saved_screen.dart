import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data.dart';
import '../insights.dart';
import '../theme.dart';
import 'discover_screen.dart';

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedProvider).values.toList();
    final apps = ref.watch(appsProvider);
    final mine = ref.watch(profileProvider).allSkills;
    final closingSoon = saved.where((j) => j.deadline != null && j.deadline!.difference(DateTime.now()).inDays < 7).length;

    return SafeArea(
      child: saved.isEmpty
          ? const EmptyState('♡', 'Nothing saved yet', 'Tap the heart or swipe a job right to keep it here for later.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                Row(children: [
                  Text('Saved.', style: display(36)),
                  const SizedBox(width: 10),
                  Sticker('${saved.length}', color: C.pink, angle: 5),
                ]),
                const SizedBox(height: 4),
                Text(
                  closingSoon > 0 ? '$closingSoon closing this week — apply first.' : 'Your shortlist. Pitch before they go stale.',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 16),
                for (final j in saved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: JobCard(
                      job: j,
                      score: matchScore(mine, j),
                      showScore: mine.isNotEmpty,
                      mine: mine,
                      saved: true,
                      status: apps[j.id]?.status,
                    ),
                  ),
              ],
            ),
    );
  }
}
