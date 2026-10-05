import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data.dart';
import '../engines.dart' show cleanCompany;
import '../insights.dart';
import '../models.dart';
import '../theme.dart';
import 'application_screen.dart';

const _lanes = [
  (AppStatus.sent, '📤 Sent', C.lime),
  (AppStatus.followedUp, '👋 Followed up', C.yellow),
  (AppStatus.replied, '🎉 Replied', C.pink),
  (AppStatus.rejected, '🪦 Nope', Color(0xFFD9D9D9)),
  (AppStatus.draft, '📝 Draft', C.white),
];

const _next = {
  AppStatus.draft: AppStatus.sent,
  AppStatus.sent: AppStatus.followedUp,
  AppStatus.followedUp: AppStatus.replied,
  AppStatus.replied: AppStatus.replied,
  AppStatus.rejected: AppStatus.sent,
};

DateTime _weekStart(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

/// Consecutive weeks (ending this week, or last week if this one is still open) where the goal was hit.
int weekStreak(Iterable<DateTime> sends, int goal, [DateTime? now]) {
  final counts = <DateTime, int>{};
  for (final s in sends) {
    counts.update(_weekStart(s), (c) => c + 1, ifAbsent: () => 1);
  }
  var week = _weekStart(now ?? DateTime.now());
  if ((counts[week] ?? 0) < goal) week = week.subtract(const Duration(days: 7));
  var streak = 0;
  while ((counts[week] ?? 0) >= goal) {
    streak++;
    week = week.subtract(const Duration(days: 7));
  }
  return streak;
}

class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(appsProvider).values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final goal = ref.watch(weeklyGoalProvider);
    final sentDates = [for (final a in apps) if (a.status != AppStatus.draft) a.updatedAt];
    final thisWeek = sentDates.where((d) => !d.isBefore(_weekStart(DateTime.now()))).length;
    final streak = weekStreak(sentDates, goal);
    final replied = apps.where((a) => a.status == AppStatus.replied).length;
    final sentCount = apps.where((a) => a.status != AppStatus.draft).length;
    final rate = sentCount < 3 ? null : (replied * 100 / sentCount).round();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          Text('Track.', style: display(36)),
          const SizedBox(height: 14),
          Brutal(
            color: thisWeek >= goal ? C.lime : C.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('This week: $thisWeek / $goal pitches', style: display(16))),
                if (streak > 0) Sticker('🔥 $streak wk streak', color: C.yellow, angle: 4),
              ]),
              const SizedBox(height: 12),
              Container(
                height: 18,
                decoration: const BoxDecoration(border: Border.fromBorderSide(border), color: C.cream),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (thisWeek / goal).clamp(0, 1)),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutBack,
                    builder: (_, t, _) => FractionallySizedBox(widthFactor: t.clamp(0, 1), child: Container(color: C.pink)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text(thisWeek >= goal ? 'Goal smashed. Go touch grass.' : '${goal - thisWeek} more to hit your goal.',
                    style: const TextStyle(color: muted)),
                const Spacer(),
                _Stepper(goal, (v) => ref.read(weeklyGoalProvider.notifier).set(v)),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (final (n, label) in [(sentCount, 'sent'), (replied, 'replies'), (rate ?? '–', rate == null ? 'reply rate after 3' : '% reply rate')])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Brutal(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    child: Column(children: [
                      Text('$n', style: display(22)),
                      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          ]),
          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EmptyState('📭', 'Nothing shipped yet', 'Pitches you launch land here. Go hunt.'),
            )
          else ...[
            const SizedBox(height: 16),
            const Text('Tap for the company, next steps and replies · swipe → next stage · ← rejected', style: TextStyle(color: muted, fontSize: 13)),
            for (final (status, label, _) in _lanes)
              if (apps.any((a) => a.status == status)) ...[
                SectionTitle(label),
                for (final a in apps.where((a) => a.status == status))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Dismissible(
                      key: ValueKey('${a.job.id}-${a.status}'),
                      background: _swipeBg('NEXT →', C.lime, Alignment.centerLeft),
                      secondaryBackground: _swipeBg('← NOPE', C.red, Alignment.centerRight),
                      confirmDismiss: (dir) async {
                        HapticFeedback.mediumImpact();
                        final s = dir == DismissDirection.startToEnd ? _next[a.status]! : AppStatus.rejected;
                        ref.read(appsProvider.notifier).put(a.copyWith(status: s));
                        return false; // the card re-renders in its new lane
                      },
                      child: _AppCard(a, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ApplicationScreen(jobId: a.job.id)))),
                    ),
                  ),
              ],
          ],
        ],
      ),
    );
  }

  Widget _swipeBg(String text, Color color, Alignment align) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: color, border: const Border.fromBorderSide(border)),
        child: Text(text, style: display(16)),
      );
}

/// A tracker entry is about the outreach, not the job ad: who, how, when, and what's next.
class _AppCard extends StatelessWidget {
  const _AppCard(this.a, {required this.onTap});
  final Application a;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final how = a.to.contains('@') ? '📧 ${a.to}' : '📝 ${a.to.isEmpty ? 'Applied' : a.to}';
    final due = a.updatedAt.add(const Duration(days: 5));
    final left = (due.difference(DateTime.now()).inHours / 24).ceil(); // "5d" right after sending, not "4d"
    final next = switch (a.status) {
      AppStatus.sent || AppStatus.followedUp => left <= 0 ? '⏰ Follow up now' : '⏰ Follow up in ${left}d',
      AppStatus.draft => '✏️ Not sent yet',
      AppStatus.replied => '🎉 Reply to them fast',
      AppStatus.rejected => '🪦 On to the next one',
    };
    return Brutal(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${cleanCompany(a.job.company).toUpperCase()}  ·  ${ageLabel(a.updatedAt)}', style: display(12, C.blue)),
        const SizedBox(height: 2),
        Text(a.job.title, style: display(17)),
        const SizedBox(height: 8),
        Text(how, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: muted)),
        if (a.notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('📝 ${a.notes}', maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        Pill(next, color: next.startsWith('⏰ Follow up now') ? C.yellow : C.white),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.value, this.onChanged);
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text('goal ', style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 13)),
        for (final (icon, d) in [(Icons.remove, -1), (Icons.add, 1)])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Brutal(
              onTap: () => onChanged(value + d),
              shadow: 2,
              padding: const EdgeInsets.all(4),
              child: Icon(icon, size: 16),
            ),
          ),
      ]);
}
