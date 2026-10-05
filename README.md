# ProofPitch

A Flutter app (Android) that helps Indian college students land internships by reaching a real person with proof of work, instead of mass "Easy Apply".

- **Reads your resume PDF on the phone** and fills your profile (skills, projects, CGPA, every section).
- **Pulls live internships** from Unstop's public API, companies' own careers pages (Greenhouse, Lever, Ashby, SmartRecruiters) and public Telegram job channels, tagged by source and filtered by field, pay, work mode and eligibility.
- **Blocks applications you can't qualify for** (CGPA, batch, degree, location, experience, skills).
- **Finds the person who hires** on the company's own website and writes a human-sounding email from the job description, with a resume tailored to that role attached.
- **❄️ Cold pitch mode**: small companies from your feed, Y Combinator startups and GitHub studios by field, visible issues on their website you could offer to fix, and a short cold email.
- **Tracks applications** with follow-up reminders, interview prep, questions to ask, red flags and ready-to-send replies.

No backend: everything runs on the phone and data stays in local storage.

## Run

```bash
flutter pub get
flutter test
flutter run
```
