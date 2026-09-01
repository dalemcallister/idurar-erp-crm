# Conversation Coach — Project Tracker

The living record of this project. **Read this first** each session; update it
when meaningful work lands. Chat context is ephemeral — this file is the memory.

_Last updated: 2026-08-31 (added communication persona pillar)._

---

## Vision

Part of a larger product to help people **refine their communication skills**.
Users record real conversations, get evidence-backed, goal-aligned coaching,
build **measurable skills over time**, and can **optionally publish achievements**
(badges, skill levels) to show employers/friends — all while conversation
content stays **private on the device**.

Guiding principles:
1. **Privacy first** — audio and transcripts never leave the device. Only
   derived, aggregate achievements are ever shareable, on explicit user action.
2. **On-device intelligence** — analysis and transcription run locally.
3. **Goal-aligned & evidence-backed** — coaching is scored against a rubric and
   cites the moments it relies on.

---

## Current status

**Basic application reached ✅** — fully on-device, working on Android (Oppo Find
N5) and iOS (TestFlight).

- **v1 (cloud, BYO-key)** — branch `v1-cloud`, PR #1. TestFlight + Android pilot.
  Kept as a fallback/reference; not the active line.
- **v2 (fully on-device)** — branch `v2-on-device`, PR #2. **Active.**
  - Analysis: Gemma 4 E2B (`flutter_gemma` / LiteRT-LM).
  - Transcription: Whisper base (`whisper_ggml` / whisper.cpp).
  - No keys; nothing leaves the device.
- Branding: **Conversation Coach**, bundle id `com.mcallister.clariconvo`,
  teal speech-bubble icon.
- Goal contexts shipped: Discovery call, Negotiation, Job interview, Difficult
  feedback, Teaching, Team meeting.

Docs: `CLAUDE.md` (orientation), `V2_SETUP.md` (build/platform + gotchas),
`BRANDING.md`, `DISTRIBUTION.md`, `TESTFLIGHT.md`.

---

## Architecture (quick map)

- Flutter iOS/Android. Encrypted SQLCipher store + OS keystore.
- Swappable `LLMProvider` and `TranscriptionEngine`; **all native model calls
  isolated in `lib/core/local_models.dart`**.
- Pipeline: record → transcribe → segment → analyse (structured JSON vs a
  weighted rubric) → summary / coaching / emotion timeline / per-session Ask.
- Goal → `Rubric` (weighted dimensions) drives scoring. Templates in
  `lib/core/goal_templates.dart`.

---

## Roadmap

### 1. More conversation types / goal contexts
- Extend `GoalTemplates` (rubric + goal) — cheap to add.
- Consider **user-defined goals & editable rubrics** (custom-rubric UI).
- Possibly group contexts (sales, leadership, interpersonal, public speaking…).

### 2. Proprietary LLM tuning ("skills")
Options, cheapest → deepest (keep the `local_models.dart` seam so a model swap
is one file):
- **Prompt + rubric library** (near-term): curated, proprietary skill
  definitions, rubric wording, and few-shot examples baked into the prompts.
- **On-device RAG**: retrieve from a proprietary coaching knowledge base and
  ground the analysis/Q&A in it.
- **Fine-tune (LoRA)** Gemma on proprietary coaching data, convert to
  `.litertlm`, ship as the model.

### 3. Skills & progress model
- Define a **skills taxonomy** mapped to rubric dimensions, with **levels**,
  streaks, and **badges** earned over time.
- Extend the existing Progress tab into skill levels + badge history + trends.

### 4. Privacy-preserving publishing (badges/skills → LinkedIn / Facebook)
- **Invariant:** conversation content never leaves the device. Only derived
  achievements (skill levels, badges, aggregate scores/streaks) are shareable.
- **MVP:** generate a shareable **achievement card** (image) + native share
  sheet → user posts to LinkedIn/Facebook manually. No backend, no data leaves
  beyond the card the user chooses to share.
- **Credible/verifiable badges** (for employers): consider Open Badges /
  verifiable credentials. This likely needs a **minimal opt-in backend that
  stores ONLY badge metadata** (never conversations) — open design decision; must
  not break the privacy invariant.
- LinkedIn: "Add to profile / certifications" deep link or share; Facebook:
  share dialog.

### 5. Communication persona & longitudinal "who I want to be" feedback
A persistent, on-device **communication persona** that evolves from every
session, giving identity-level feedback across three questions:
- **"How am I going?"** — trends across sessions (rubric dimensions, talk-time,
  questions, filler, empathy, recurring strengths/patterns) as an evolving
  narrative of the user's style.
- **"Am I who I want to be?"** — the user defines an **aspirational self**
  (target traits/values/role, editable); the app does a **gap analysis** between
  the observed persona and that aspiration. The user sets the aspiration — the
  app never imposes values.
- **"How do I improve?"** — focused, evidence-backed practice tied to the gap
  and to the skills/badges model (roadmap #3).

Design notes:
- **Hierarchical summarisation** — store a compact per-session *digest*, then
  synthesise the persona from digests. Avoids on-device context overflow from
  feeding many full sessions to a small model.
- Recompute after each session or on a schedule, not every app open.
- Supportive, evidence-backed, non-judgmental tone; self-directed aspiration.
- Privacy invariant holds: computed entirely on-device from local data.

### 6. Distribution & store readiness
- **Un-gated on-device model** so no HF token ships (prerequisite for wide
  distribution). Rotate the current HF token.
- App Store / Play Store: icons ✅, privacy nutrition labels are simple (on-device),
  store listings, screenshots.

---

## Decisions log (append-only)

- **2026-08:** v2 replaces cloud with on-device for privacy; v1 preserved on
  `v1-cloud`.
- **2026-08:** Analysis model = Gemma 4 E2B (mobile `.litertlm`, quality/size
  balance; 1B was too weak — invalid JSON, weak content). STT = Whisper base.
- **2026-08:** iOS requires **dynamic** frameworks (static breaks whisper_ggml
  FFI). Documented in `V2_SETUP.md` / `CLAUDE.md`.
- **2026-08:** Resilient JSON parsing (repairs + field-extraction fallback) to
  tolerate small-model output; compact strict on-device prompt to reduce errors.
- **2026-08:** Record at 16 kHz mono (whisper requirement).
- **2026-09:** Long recordings overflowed Gemma's 4096-token context (a ~9-min
  meeting = ~16k tokens → `token ids are too long 16403 >= 4096`). First fix
  (superseded): evenly sample segments to fit. **Now:** two changes together —
  (a) on-device prompts render the transcript **without the UUID segment ids**
  (`renderTranscript(withIds: false)`); those ids were ~50 chars/line and a big
  share of the 16k tokens, and the compact prompt never cites them; (b) a
  **map-reduce** path (`AnalysisOrchestrator._analyzeOnDevice`): short meetings
  go in one call, long ones digest each windowed chunk (`PromptRegistry.
  digestChunk`, MAP) then analyse from the digests (REDUCE) — full coverage, no
  overflow. Per-call output budgets (`PromptRequest.maxTokens` → Gemma
  `maxOutputTokens`: analysis 1024, digest 512) keep input+output inside 4096.
  Map-reduce is gated on the **resolved provider's** window (≤8192), so a local
  config that falls back to the offline mock (model not downloaded) or to cloud
  takes the standard full-transcript path. The per-chunk digests are the same
  raw material the **communication persona** (roadmap #5) will reuse.

---

## Open questions / to decide
- Verifiable badges: fully on-device (self-signed, less credible) vs. minimal
  badge-only backend (more credible, adds infra) — pick before building sharing.
- Which proprietary-tuning path (prompt library vs RAG vs LoRA) to invest in first.
- Un-gated model choice for distribution (host our own vs. an un-gated repo).
- Persona: how the aspirational self is captured (onboarding prompt, chips,
  free-text), and the recompute cadence (per-session vs weekly).
