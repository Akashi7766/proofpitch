import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data.dart';
import 'notify.dart';
import 'outreach.dart' show leadFromText;
import 'screens/cold_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/saved_screen.dart';
import 'screens/tracker_screen.dart';
import 'snow.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStore();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  runApp(const ProviderScope(child: ProofPitchApp()));
}

class ProofPitchApp extends StatelessWidget {
  const ProofPitchApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ProofPitch',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Android draws edge-to-edge: without this, sheets and pages sit under the 3-button nav bar.
        // One wrapper above the Navigator keeps every route and bottom sheet above it.
        builder: (context, child) => ColoredBox(
          color: C.white,
          child: SafeArea(top: false, left: false, right: false, child: child!),
        ),
        home: const Shell(),
      );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  // First launch with no profile → start on the profile tab.
  late int _tab = ref.read(profileProvider).isEmpty ? 3 : 0;

  static const _share = MethodChannel('proofpitch/share');

  @override
  void initState() {
    super.initState();
    // "Share → ProofPitch" from LinkedIn/Reddit/WhatsApp: turn the post into a lead the student confirms.
    _share.setMethodCallHandler((call) async {
      if (call.method == 'shared') _openShared(call.arguments as String);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final text = await _share.invokeMethod<String>('initialShare');
        if (text != null) _openShared(text);
      } on MissingPluginException {
        // Web/desktop: no share sheet.
      }
    });
  }

  void _openShared(String text) {
    if (!mounted) return;
    setState(() => _tab = 0);
    pasteLead(context, ref, prefill: leadFromText(text));
  }

  static const _tabs = [
    (Icons.bolt_rounded, 'HUNT', C.lime),
    (Icons.favorite_rounded, 'SAVED', C.pink),
    (Icons.view_kanban_rounded, 'TRACK', C.yellow),
    (Icons.person_rounded, 'ME', Color(0xFF9AD8FF)),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: const [HuntTab(), SavedScreen(), TrackerScreen(), ProfileScreen()]),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: C.white, border: Border(top: border)),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(children: [
                for (final (i, (icon, label, color)) in _tabs.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Brutal(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _tab = i);
                        },
                        color: _tab == i ? color : C.cream,
                        shadow: _tab == i ? 4 : 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedScale(
                            scale: _tab == i ? 1.2 : 1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.elasticOut,
                            child: Icon(icon, color: C.ink),
                          ),
                          Text(label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
}

/// HUNT: 🔥 Jobs (the feed) or ❄️ Cold pitch (companies that aren't advertising), switched at the top.
class HuntTab extends ConsumerWidget {
  const HuntTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cold = ref.watch(coldModeProvider);
    return Stack(children: [
      Positioned.fill(
        child: AnimatedOpacity(opacity: cold ? 1 : 0, duration: const Duration(milliseconds: 450), child: const DecoratedBox(decoration: iceBackground)),
      ),
      if (cold) const Positioned.fill(child: Snowfall()),
      SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: ModeToggle(cold: cold, onChanged: (v) => ref.read(coldModeProvider.notifier).set(v)),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: cold ? const ColdScreen(key: ValueKey('cold')) : const DiscoverScreen(key: ValueKey('jobs')),
            ),
          ),
        ]),
      ),
    ]);
  }
}
