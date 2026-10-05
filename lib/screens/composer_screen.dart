import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data.dart';
import '../cold.dart' show ColdBrief, buildColdPitch;
import '../engines.dart';
import '../models.dart';
import '../notify.dart';
import '../outreach.dart';
import '../tailor.dart';
import '../theme.dart';
import 'resume_import.dart' show pickResumeFile;

/// The apply page: pick where it goes, who reads it and a template, edit, send — resume attached.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key, required this.job, required this.projects, this.cold, this.knownContacts = const [], this.knownDomain});
  final JobListing job;
  final List<Project> projects;

  /// Set for a ❄️ cold pitch (no job post): the email is written from this instead of a job description.
  final ColdBrief? cold;

  /// Contacts the cold-pitch screen already found, so the lookup doesn't run twice.
  final List<SiteContact> knownContacts;
  final String? knownDomain;
  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  late final PersonaGuess _guess = guessPersona(widget.job);
  late Persona _persona = _guess.persona;
  List<SiteContact> _siteContacts = const [];
  String? _siteDomain;
  late List<ContactRoute> _routes = contactRoutes(widget.job, _persona);
  late ContactRoute _route = _routes.first;
  late EmailTemplate _template = _defaultTemplate();
  late final _to = TextEditingController(text: _route.isEmail ? _route.target : '');
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _attach = true;
  late bool _tailored = _canTailor; // a resume reordered for this job, generated on the phone
  String? _tailoredPath;
  bool _finding = false;
  String? _findResult; // what the website/email lookup found, in words
  bool _sent = false;

  bool get _isDm => _route.kind == RouteKind.linkedin || _route.kind == RouteKind.x;
  String get _resumePath => ref.read(profileProvider).resumePath;
  bool get _hasOriginal => !kIsWeb && _resumePath.isNotEmpty && File(_resumePath).existsSync();
  bool get _canTailor => !kIsWeb && ref.read(profileProvider).projects.isNotEmpty;

  /// What actually goes out with the email, or null for none.
  String? get _attachPath => !_attach
      ? null
      : (_tailored && _tailoredPath != null)
          ? _tailoredPath
          : (_hasOriginal ? _resumePath : null);

  Future<void> _makeTailored() async {
    try {
      final path = await writeTailoredResume(ref.read(profileProvider), widget.job);
      if (mounted && path != null) setState(() => _tailoredPath = path);
    } catch (_) {
      // Fall back to their own PDF, and re-word the email so it never claims a missing attachment.
      if (mounted) {
        setState(() {
          _tailored = false;
          _regenerate();
        });
      }
    }
  }

  void _previewTailored() {
    final r = tailorResume(ref.read(profileProvider), widget.job);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.cream,
      shape: const Border(top: border),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (_, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
          Text('Your resume, for this role', style: display(22)),
          const SizedBox(height: 6),
          const Text("Same facts as your resume, reordered: this job's skills first, the projects that prove them first. Nothing is made up.",
              style: TextStyle(color: muted)),
          const SizedBox(height: 14),
          Brutal(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.name, style: display(18)),
              Text(r.headline, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
              Text(r.contact, style: const TextStyle(color: muted, fontSize: 12)),
              const SizedBox(height: 10),
              Text(r.summary),
              const SizedBox(height: 10),
              if (r.relevantSkills.isNotEmpty)
                Text('Relevant: ${r.relevantSkills.join(', ')}', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
              if (r.otherSkills.isNotEmpty) Text('Also: ${r.otherSkills.join(', ')}'),
              for (final p in r.projects) ...[
                const SizedBox(height: 10),
                Text(p.project.name, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
                for (final b in p.bullets.isEmpty && p.project.oneLiner.isNotEmpty ? [p.project.oneLiner] : p.bullets) Text('• $b'),
              ],
              for (final sec in r.sections) ...[
                const SizedBox(height: 10),
                Text(sec.title.toUpperCase(), style: display(12, C.blue)),
                for (final l in sec.lines) Text(l),
              ],
              if (ref.read(profileProvider).resumeSections.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('Tip: re-import your resume on ME to bring in project bullets, experience and achievements too.',
                      style: TextStyle(color: muted, fontSize: 13)),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_tailoredPath != null)
            BrutalButton('Save / share PDF', icon: Icons.ios_share_rounded, onTap: () async {
              try {
                await const MethodChannel('proofpitch/share').invokeMethod('sharePdf', {'path': _tailoredPath});
              } catch (_) {
                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Couldn't open the share sheet")));
              }
            }),
        ]),
      ),
    );
  }
  bool get _hasRealEmail => _routes.any((r) => r.kind == RouteKind.email);

  EmailTemplate _defaultTemplate() {
    final p = ref.read(profileProvider);
    if (p.templateBody.isNotEmpty) return EmailTemplate.mine; // they wrote one — use it
    if (detectChannel(widget.job.applyTarget) == Channel.enterpriseAts) return EmailTemplate.formal;
    return _persona == Persona.founder ? EmailTemplate.short : EmailTemplate.standard;
  }

  @override
  void initState() {
    super.initState();
    if (widget.knownContacts.isNotEmpty || widget.knownDomain != null) {
      _siteContacts = widget.knownContacts;
      _siteDomain = widget.knownDomain;
      _routes = contactRoutes(widget.job, _persona, siteContacts: _siteContacts, siteDomain: _siteDomain);
      final pick = widget.cold?.contact?.email;
      _route = _routes.firstWhere((r) => r.target == pick, orElse: () => _routes.first);
      if (_route.isEmail) _to.text = _route.target;
    }
    _regenerate();
    if (_canTailor) _makeTailored();
    // The official site and its inbox are worth more than an apply button that may not work, so look right away.
    if (!_hasRealEmail && widget.knownDomain == null) _findEmail();
  }

  void _regenerate() {
    final profile = ref.read(profileProvider);
    if (_isDm) {
      _body.text = shortNote(profile, widget.job, widget.projects, _persona);
      return;
    }
    final cold = widget.cold;
    if (cold != null) {
      final to = _to.text.trim();
      final p = buildColdPitch(
        profile,
        ColdBrief(
          company: cold.company,
          domain: cold.domain,
          contact: _siteContacts.where((c) => c.email == to).firstOrNull ?? (to.isEmpty ? cold.contact : null),
          holes: cold.holes,
          ownNote: cold.ownNote,
          field: cold.field,
        ),
        widget.projects,
        resumeAttached: _attachPath != null || (_attach && _tailored && _canTailor),
      );
      _subject.text = p.subject;
      _body.text = p.body;
      return;
    }
    final ch = _route.isEmail ? Channel.directEmail : detectChannel(widget.job.applyTarget);
    final p = buildPitch(profile, widget.job, widget.projects, ch, _persona, template: _template, resumeAttached: _attachPath != null || (_attach && _tailored && _canTailor));
    _subject.text = p.subject;
    _body.text = p.body;
  }

  void _pickRoute(ContactRoute r) => setState(() {
        _route = r;
        if (r.isEmail) _to.text = r.target;
        _regenerate();
      });

  void _rebuildRoutes() {
    _routes = contactRoutes(widget.job, _persona, siteContacts: _siteContacts, siteDomain: _siteDomain);
    _route = _routes.firstWhere((r) => r.kind == _route.kind && r.target == _route.target, orElse: () => _routes.first);
  }

  void _pickPersona(Persona p) => setState(() {
        _persona = p;
        _rebuildRoutes(); // who to look for on LinkedIn depends on who's reading
        _regenerate();
      });

  Future<void> _findEmail() async {
    setState(() => _finding = true);
    EmailSearch found;
    try {
      found = await findCompanyEmails(widget.job);
    } catch (_) {
      found = const EmailSearch(null, []); // no network, odd company name…: fall back to LinkedIn/search
    }
    if (!mounted) return;
    setState(() {
      _finding = false;
      _siteContacts = found.contacts;
      _siteDomain = found.domain;
      _rebuildRoutes();
      final best = found.contacts.firstOrNull;
      if (best != null) {
        _route = _routes.firstWhere((r) => r.target == best.email, orElse: () => _route);
        _to.text = _route.target;
        _regenerate();
      }
      _findResult = found.domain == null
          ? "Couldn't find ${cleanCompany(widget.job.company)}'s own website. LinkedIn is your best bet."
          : best == null
              ? 'Found ${found.domain}, but it lists no email. Try their site or LinkedIn.'
              : best.role.index <= ContactRole.techLead.index
                  ? '🎯 Picked ${best.label} (${best.email})${best.guessed ? ' — guessed from how their emails look' : ''}.'
                  : 'Only a ${best.role.label.toLowerCase()} on ${found.domain}; it may not reach the person who hires. LinkedIn below finds them.';
    });
  }

  String get _cta => switch (_route.kind) {
        RouteKind.email || RouteKind.guessedEmail => _attachPath != null ? 'Open in email app 📎' : 'Open in email app 🚀',
        RouteKind.applyPage => 'Copy note + open apply page',
        RouteKind.linkedin => 'Copy note + open LinkedIn',
        RouteKind.x => 'Copy note + open X',
        RouteKind.website || RouteKind.search => 'Open ${_route.kind == RouteKind.website ? 'website' : 'search'} 🔎',
      };

  Future<bool> _openEmail(ScaffoldMessengerState messenger) async {
    final to = _to.text.trim();
    final path = _attachPath;
    final attach = path != null;
    try {
      await FlutterEmailSender.send(Email(
        recipients: [to],
        subject: _subject.text,
        body: _body.text,
        attachmentPaths: attach ? [path] : null,
      ));
      return true;
    } catch (_) {
      // No email app that takes attachments (or web): plain mailto, attach by hand.
      final ok = await launchUrl(buildMailto(to, _subject.text, _body.text));
      if (ok && attach) messenger.showSnackBar(const SnackBar(content: Text('Opened without the attachment — add your resume in the email app.')));
      return ok;
    }
  }

  Future<void> _launch() async {
    final messenger = ScaffoldMessenger.of(context);
    final bool ok;
    if (_route.isEmail) {
      if (!_to.text.contains('@')) {
        messenger.showSnackBar(const SnackBar(content: Text('Add an email address first')));
        return;
      }
      ok = await _openEmail(messenger);
    } else {
      // Copying can fail (permissions, some browsers). Never let that stop the student from getting to the page.
      var copied = false;
      if (_route.countsAsApplication) copied = await _copy();
      ok = await launchUrl(Uri.parse(_route.target), mode: LaunchMode.externalApplication);
      if (ok && _route.countsAsApplication) {
        messenger.showSnackBar(SnackBar(
          content: Text(!copied
              ? "Couldn't copy automatically — long-press the text to copy it."
              : _isDm
                  ? 'Note copied — open their profile, hit Connect → Add a note, paste 📋'
                  : 'Copied — upload your resume there and paste this as the cover note 📋'),
        ));
      }
    }
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't open that. Is the app installed?")));
      return;
    }
    if (!_route.countsAsApplication || !mounted) return; // research step: nothing to log yet

    // Opening Gmail or a page isn't the same as sending. Ask when they come back.
    final sent = await _askSent();
    if (sent == null) return;
    ref.read(appsProvider.notifier).put(Application(
          job: widget.job,
          status: sent ? AppStatus.sent : AppStatus.draft,
          updatedAt: DateTime.now(),
          to: _route.isEmail ? _to.text.trim() : _route.label,
          subject: _isDm ? 'DM via ${_route.label}' : _subject.text,
          body: _body.text,
        ));
    if (!sent) {
      messenger.showSnackBar(const SnackBar(content: Text('Saved as a draft in TRACK — finish it when you can.')));
      return;
    }
    try {
      final reminded = await scheduleFollowUp(widget.job.id.hashCode & 0x7fffffff, widget.job.company);
      if (!reminded) {
        messenger.showSnackBar(const SnackBar(content: Text('Notifications are off, so no reminder will pop up. TRACK still shows when to follow up.')));
      }
    } catch (_) {
      // Reminders are a nice-to-have; never block the send on them.
    }
    HapticFeedback.heavyImpact();
    if (mounted) setState(() => _sent = true);
  }

  Future<bool> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: _isDm || !_route.isEmail ? _body.text : '${_subject.text}\n\n${_body.text}'));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool?> _askSent() => showModalBottomSheet<bool>(
        context: context,
        backgroundColor: C.cream,
        shape: const Border(top: border),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Did you send it?', style: display(22)),
            const SizedBox(height: 6),
            Text(
              _route.isEmail ? 'We only log it once it actually left your outbox.' : 'We only log it once you actually submitted or sent it.',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            BrutalButton('Yes, sent it ✅', big: true, onTap: () => Navigator.pop(ctx, true)),
            const SizedBox(height: 12),
            BrutalButton('Not yet — save as draft', color: C.white, onTap: () => Navigator.pop(ctx, false)),
          ]),
        ),
      );

  Widget _step(String n, String title) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 10),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: C.ink),
            child: Text(n, style: display(14, C.lime)),
          ),
          const SizedBox(width: 10),
          Text(title, style: display(18)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final job = widget.job;
    final email = _route.isEmail;
    return Stack(children: [
      Scaffold(
        appBar: AppBar(title: const Text('Apply')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
          children: [
            Text(job.title, style: display(22).copyWith(height: 1.15)),
            const SizedBox(height: 4),
            Text('at ${cleanCompany(job.company)}', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: muted)),

            // ── 1. Where it goes ──
            _step('1', 'Send it to'),
            for (final r in _routes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Brutal(
                  onTap: () => _pickRoute(r),
                  color: r == _route ? C.lime : C.white,
                  shadow: r == _route ? 2 : 3,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Text(r.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.label, style: display(13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(r.detail, style: const TextStyle(color: muted, fontSize: 12)),
                      ]),
                    ),
                    if (!r.verified) const Pill('GUESS', color: C.yellow),
                    if (r == _route) const Icon(Icons.check_circle_rounded),
                  ]),
                ),
              ),
            if (_finding)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 3, color: C.ink)),
                  SizedBox(width: 12),
                  Expanded(child: Text('Finding their official website and email…')),
                ]),
              )
            else if (_findResult != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_findResult!, style: const TextStyle(color: muted))),

            // ── 2. Who reads it ──
            _step('2', "Who's reading"),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final x in Persona.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: BrutalChip('${x.emoji} ${x.label}${x == _guess.persona ? ' · AUTO' : ''}',
                        selected: x == _persona, color: const Color(0xFFFFD1E6), onTap: () => _pickPersona(x)),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              _persona == _guess.persona ? '${_persona.blurb} Picked because: ${_guess.reasons.join(', ')}.' : _persona.blurb,
              style: const TextStyle(color: muted, fontSize: 13),
            ),

            // ── 3. Message ──
            _step('3', _isDm ? 'Your note' : (email ? 'Your email' : 'Your cover note')),
            if (_route.countsAsApplication && !_isDm && widget.cold == null) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in EmailTemplate.values)
                  BrutalChip(t.label, selected: t == _template, color: C.lime, onTap: () => setState(() {
                        _template = t;
                        _regenerate();
                      })),
              ]),
              const SizedBox(height: 6),
              Text(_template == EmailTemplate.mine && profile.templateBody.isEmpty ? 'Using the starter template — make it yours on the ME tab.' : _template.blurb,
                  style: const TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 14),
            ],
            if (email) ...[
              TextField(controller: _to, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'To', isDense: true)),
              const SizedBox(height: 12),
            ],
            if (!_isDm && email) ...[
              TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject', isDense: true)),
              const SizedBox(height: 12),
            ],
            if (_route.countsAsApplication)
              TextField(
                controller: _body,
                maxLines: null,
                minLines: _isDm ? 4 : 12,
                maxLength: _isDm ? linkedInNoteLimit : null,
                decoration: InputDecoration(labelText: _isDm ? 'Note (300 max on LinkedIn)' : 'Message — edit anything'),
              )
            else
              const Text('This opens their site so you can find a team page or contact form. Come back and pick another route to send.',
                  style: TextStyle(color: muted)),
            if (!_isDm && _route.countsAsApplication) ...[
              const SizedBox(height: 8),
              Row(children: [
                GestureDetector(
                  onTap: () async {
                    final ok = await _copy();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Copied 📋' : "Couldn't copy")));
                    }
                  },
                  child: const Text('Copy text', style: TextStyle(decoration: TextDecoration.underline)),
                ),
                const Spacer(),
                ValueListenableBuilder(
                  valueListenable: _body,
                  builder: (_, v, _) {
                    final words = v.text.trim().split(RegExp(r'\s+')).length;
                    final long = email && words > 200;
                    return Pill(long ? '$words words · trim it!' : '$words words', color: long ? C.red : C.lime);
                  },
                ),
              ]),
            ],

            // ── Resume ──
            if (!kIsWeb && _route.countsAsApplication && !_isDm) ...[
              const SizedBox(height: 18),
              Text(email ? 'RESUME TO ATTACH' : 'RESUME TO UPLOAD', style: display(12, C.blue)),
              const SizedBox(height: 8),
              if (_canTailor || _hasOriginal)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_canTailor)
                    BrutalChip('✨ Tailored for this role', selected: _attach && _tailored, color: C.lime, onTap: () => setState(() {
                          _attach = true;
                          _tailored = true;
                          _regenerate();
                        })),
                  if (_hasOriginal)
                    BrutalChip('📄 My PDF', selected: _attach && !_tailored, color: C.lime, onTap: () => setState(() {
                          _attach = true;
                          _tailored = false;
                          _regenerate();
                        })),
                  if (email)
                    BrutalChip('None', selected: !_attach, color: C.white, onTap: () => setState(() {
                          _attach = false;
                          _regenerate();
                        })),
                ]),
              if (_canTailor) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      _tailoredPath == null ? 'Building your tailored resume…' : 'Your skills and projects, reordered for this job.',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  GestureDetector(
                    onTap: _previewTailored,
                    child: const Text('Preview & save', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
              if (!_hasOriginal) ...[
                const SizedBox(height: 10),
                Brutal(
                  onTap: () async {
                    await pickResumeFile(ref);
                    if (mounted) setState(_regenerate);
                  },
                  color: _canTailor ? C.white : C.yellow,
                  shadow: 3,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    const Text('📎', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_canTailor ? 'Add your own resume PDF too (optional)' : 'Add your resume PDF — it gets attached to every email',
                          style: display(13)),
                    ),
                  ]),
                ),
              ],
              if (_route.kind == RouteKind.applyPage) ...[
                const SizedBox(height: 12),
                const Text('On their page: upload your resume ("Preview & save" gets you the tailored PDF), then paste this note into the cover letter / "why you" box.',
                    style: TextStyle(color: muted)),
              ],
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: BrutalButton(_cta, big: true, onTap: _launch),
          ),
        ),
      ),
      if (_sent) ...[
        Positioned.fill(child: GestureDetector(onTap: () => Navigator.pop(context), child: Container(color: C.cream.withValues(alpha: 0.85)))),
        const Positioned.fill(child: ConfettiBurst()),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Stamp(angle: -12, child: StampLabel('SHIPPED', color: C.blue)),
            const SizedBox(height: 28),
            Material(
              color: Colors.transparent,
              child: Text("Logged in TRACK. We'll nudge you to follow up.", style: display(14), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 20),
            BrutalButton('Next lead →', onTap: () => Navigator.popUntil(context, (r) => r.isFirst)),
          ]),
        ),
      ],
    ]);
  }
}
