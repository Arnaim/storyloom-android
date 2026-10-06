# Storyloom Android — Progress & Handoff Notes

> Session ledger so any future session can pick up fast. Last updated: 2026-10-06 (Phase 1 + Phase 2 + Phase 3 done; Phase 4 next).

## Session 4 (2026-10-06): Scenario library expansion (Phase 3 — DONE)

**What:** Expanded the scenario library from 10 to 16 with deeper premises, richer casts, and fork-branching on every scenario.

**Done:**
- **seed_scenarios.dart** fully rewritten cleanly (was broken from incremental edits). All 16 scenarios compiled, analyzed, and tested.
- **Arcanum Academy upgraded** with storyexample.txt version: 11 NPCs (Valeria, Sera, Kira, Elena, Rhea, Terra, Lune, Mira, Flynn, Cassius, Matthias), 7-element Archive system, faction war (Traditionalists vs Progressives vs Ancients), merit ranking, high-stakes dueling, hidden mysteries (Founder's Office, The Big Hive, Student Disappearances), 3 forks (allied / rebel / independent).
- **My Bullies Got Isekaied Too!** added as a new scenario from storyexample.txt: 5 NPCs (Riko, Rei, Akane, Kana, Yui), dungeon survival, 3 forks (protect / dominate / abandon).
- **6 new scenarios added:**
  1. Cast Out by the Kingdom — male prince/exile, demi-human companions (fox/elf/cat/mouse/wolf girls), slow-burn romance, 3 forks (reclaim / new_family / revenge)
  2. Hero Academy: Underdog — male underdog with unique hidden power, no quirk system, 3 forks (reveal / hide / leave)
  3. Tower of Ascension — ORV/gods style, infinite tower, mythical beings, 3 forks (solo / party / betray)
  4. Zombie Apocalypse: Last Light — mixed cast, dynamic recruitment, 3 forks (trust_all / selective / solo)
  5. Wholesome Isekai: Walking Path — simple adventure, no OP system, 3 forks (settle / walk / help)
- **All 10 existing scenarios** updated with forks (previously had none): Kicked to the Curb, The Extra in the Villainess Story, The Ninth Hour, Low Orbit: ELLEN, The Hollow Crown, Analog Heart, Fault Lines, plus Arcanum Academy and My Entire Class Got Isekaied already had forks from earlier session.
- **All scenarios** follow the detailed storyexample.txt pattern: rich premise, world description, rules, tone, narrator style, 10+ NPCs with personalities/backstory hooks, locations, lore, opening suggestions, cover art, and 2-3 forks each.

**storyexample.txt used for:**
1. **UPDATE** — Arcanum Academy: replaced old premise with "The Hidden World / The Masquerade" version from storyexample.txt (7-element Archive, faction war, merit ranking, high-stakes dueling, hidden mysteries, First-Generation Mage opening, Elena cast).
2. **NEW** — My Bullies Got Isekaied Too!: added as a separate dungeon survival scenario from storyexample.txt (Riko/Rei/Akane/Kana/Yui cast).

## Session 3b (2026-10-06): Branching engine (Phase 1)

**What:** Core branching/divergence machinery so stories no longer
follow a single fixed path.

**Changes:**
- `world_state.dart`: `defaultState` now includes `branching` map
  (`act`, `branch`, `arc_progress`, `tone`) plus helpers
  `currentBranch/Act/ArcProgress/Tone`.
- `models/scenario.dart`: new `Fork` + `ForkTrigger` classes with
  `toJson`/`fromJson`; `Scenario.forks` field, wired into
  `copyWith`/`toJson`/`fromJson`.
- `story_engine.dart`: `_checkForks` + `_triggerMatches` + `_compare`
  — after each analysis, evaluates scenario forks against current
  world + NPC state; on match switches `branch` and advances `act`;
  records a system event. Hooked into `applyAnalysisToWorld` which
  is called by `runTurn`, `regenerate`, `rewindTo`, `generateOpening`.
- `prompt_builder.dart`: `buildStateSection` now prints `BRANCH`,
  `Act`, `Tone/mood`; `openingUserMessage` accepts optional `state`
  and uses `fork.openingScene` when a branch is active.
- `seed_scenarios.dart`: Arcanum Academy gets two forks
  (allied/rebel) with fact-triggered conditions + branch-specific
  opening scenes.

**Result:** Stories can now pivot — the model sees `BRANCH: X` and
branch-specific opening text every turn, and forks fire automatically
when triggers (relationship/fact/flag thresholds) are met.

**Still pending:** Phase 2 cast persistence (NPC memory, background
sim, relationship drift), Phase 3 genre expansion, Phase 4 creator
refinement, Phase 5 polish.

## Session 3c (2026-10-06): Cast persistence (Phase 2)

**What:** Characters no longer fade into the background. Four changes:

1. **Per-NPC memory table** (`npc_memories` in DB v4, `NPCMemory` model
   in `story.dart`, CRUD in `database.dart`). `buildNpcs` injects each
   NPC's last 3 personal memories into their card so the model knows
   what they remember about the player. Bounded to 6 per NPC.

2. **Relationship drift** (`_applyRelationshipDrift` in `story_engine.dart`).
   NPCs not mentioned in a turn's `npc_updates` lose 0.5 relationship
   and get an updated emotional-state label (devoted/friendly/neutral/wary/hostile).
   Prevents frozen relationships.

3. **NPC memory pinning** (`_pinNpcMemories`). Relationship deltas,
   emotional states, and locations reported by the model are pinned
   as per-NPC facts so they resurface in future prompts.

4. **Uncapped cast** (`buildNpcs limit=14` + overflow "BACKGROUND N more"
   summary line). Arcanum's 16 NPCs now all appear in the prompt.

**DB migration:** v3 → v4 (`npc_memories` table).

**Still pending:** Phase 3 genre expansion, Phase 4 creator refinement,
Phase 5 polish.

**What prompted:** User critique — stories follow a fixed path, chars fade into
background, only 10 scenarios, "create your character" label confusion,
created-story images don't show in library, needs more genres.

**Diagnosis (verified in code):**
- `story_engine.dart` + `prompt_builder.dart`: no branching engine; single
  fixed `opening_scene` per scenario; `buildNpcs` caps cast at 8 (Arcanum
  has 16); no off-screen NPC simulation; no plot-state tracking.
- `widgets.dart` `StoryTile`: never renders story cover — shows letter avatar
  only, so created-story images "don't show".
- `create_story_page.dart`: 1-on-1 NPC section labeled "YOUR CHARACTER",
  then player sheet also "Your character" — confusing collision.
- `assets/covers/`: only `scenario1.jpg` exists; scenarios 2–10 reference
  missing files → GenreBanner fallback (confirmed).

**Plan written** (detailed in this session): 4-phase roadmap — Phase 0 quick
wins, Phase 1 branching engine, Phase 2 cast persistence, Phase 3 genre
expansion, Phase 4 creator overhaul, Phase 5 polish/retention.

**Done now:**
- UI/UX quick win #2: renamed 1-on-1 section "WHO YOU'LL MEET" and player
  sheet "About you" (`create_story_page.dart`, `scenario_page.dart`).
- UI/UX quick win #6: template-driven creator — 12 genre templates
  (8 full-story, 4 1-on-1) with pre-filled tone/world/rules; horizontal
  picker grid in creator; templates seed defaults without overwriting
  user edits (`create_story_page.dart`).
- Visual identity overhaul: "Ink & Ember" warm literary palette replacing
  generic purple — burnished bronze `#C8956C`, ink `#0C0A0F`, plum `#171320`,
  leather `#8B6F4A`, ember `#B85A44`. Updated `theme.dart` fully
  (text theme, input decorations, bottom sheet, dialog, tabs, snackbar).
- Genre-specific icons in `widgets.dart` (`genreIconFor`) so cover banners
  and GenreBanner show distinct glyphs per genre.

**Not yet done (next step):**
- Phase 0 #1: cover art for all 10 seed scenarios + StoryTile cover render
  (skipped — no images available).
- Phase 1: branching engine (story_state, forks, divergence scoring).
- Phase 2: cast persistence (per-NPC memory, background sim, relationship
  drift).
- Phase 3: genre expansion to 40+ scenarios.
- Phase 4: template creator refinement, AI cast art.
- Phase 5: onboarding, age gate, performance.

## Session 2b (2026-09-06): Launcher icon white-box fix

**Symptom:** app icon appeared inside a white box on the launcher.
**Root cause:** `ic_launcher.png` was a non-square RGB PNG (108×99, no alpha) of
the logo with its dark background baked in; there was no adaptive icon, so
modern launchers drew the legacy square icon on their own white circular
backdrop → white ring/box around the mark.

Fix (no new deps, generated with PIL — source of truth
`assets/branding/logo.png`, purple mark spans ~69% of the canvas, centered):
- Extracted the purple mark (bbox 42,38–256,248) as a transparent RGBA asset.
- Adaptive icon: `mipmap-anydpi-v26/ic_launcher.xml` → color background
  `#0E1620` (`values/ic_launcher_background.xml`) + `ic_launcher_foreground`
  (mark at 62% of the 108dp canvas, inside the 66dp safe zone), all densities.
- Legacy fallback `ic_launcher.png` regenerated: full square dark-navy + mark
  at 68%, RGBA, all densities (no more RGB-no-alpha non-square icon).
- Splash: `launch_image.png` (mark at 96dp base) on `@color/launch_background_color`
  (#0E1620) via both `launch_background.xml` variants — matches the dark first
  frame, no white flash. `values-v31/styles.xml` sets
  `windowSplashScreenBackground` so the Android 12+ system splash is also dark.
- Manifest label `storyloom` → `Storyloom`.
- Verified: `flutter build apk --release` ✓; aapt2 dump shows mipmap/ic_launcher,
  ic_launcher_foreground, launch_image in the APK; label = "Storyloom".

## Session 2 (2026-09-06): UX overhaul, cast fidelity, actions, story creator

Engine/prompt fixes:
- **Opening cast injection (major bug fix):** `openingUserMessage()` never sent the
  NPC cast to the model, so openings invented their own characters. The opening
  prompt now includes full NPC cards (from DB, falling back to scenario JSON) plus
  a hard rule: only cast members may appear as named characters.
- **Adaptive reply length:** storytelling rule #9 tells the model to size the reply
  to the moment (one sentence for small beats, 2-4 short paragraphs only for big
  moments). Removed the old blanket "2-5 paragraphs" rule.
- **NPC flexibility:** new rule #6 — NPCs are living people; moods/attitudes must
  react to player behavior, never stay frozen in their profile.
- **Action vs speech:** input wrapped in `*asterisks*` (or sent in Do mode) is a
  narrated ACTION; plain text is spoken. Scene transcript labels them `[ACTION]` /
  `[SAY]`; `StoryMessage.isUserAction` / `isActionSyntax` / `stripActionSyntax`
  in `lib/models/story.dart`; prompt labels in `buildAction()`.
- **restartStory** now wipes NPCs/quests/items/memories/snapshots (via
  `AppDatabase.deleteWorldData`) and re-seeds the scenario cast — it used to leak
  the previous run's world state.
- **Rewind now restores the world exactly:** new `world_snapshots` table (DB v3)
  stores full state + NPCs + quests + items after every turn. `rewindTo()`
  restores from the checkpoint, deletes the abandoned timeline, persists the new
  action as a proper user message, and works as a pure "return to this point"
  (empty action) too.

UI:
- Player: Say/Do mode toggle, action hint strip, distinct ACTION bubbles
  (tertiary container + italic), long-press any message → return-to-point /
  delete-from-here menu, fixed `_retryLast` fallback bug.
- Scenario page: hero cover with scrim, expandable cast cards (full About /
  Personality / Speech / Backstory), AI-cover button ("AI art" / "Redo art").
- Theme: refreshed dark palette, outlined cards, glow accents, layered
  `GenreBanner` (gradient + radial glow + rings), richer ScenarioCard with
  STORYLOOM/YOURS badge.
- Home: "New story" FAB.

New features:
- **Story creator** (`lib/ui/create_story_page.dart`): 1-on-1 roleplay mode
  (single character, dialogue-first narrator style, RPG off) and full story mode
  (world/rules/tone/opening + NPC editor sheets). Cover + character images picked
  from gallery (`image_picker`), copied into app docs dir, stored as absolute
  paths in `cover_art` / npc `image`.
- **AI cover art** (`lib/engine/cover_art.dart`): calls
  `gemini-2.5-flash-image` over REST (`x-goog-api-key` header, TEXT+IMAGE
  response modalities), saves PNG under docs/covers, updates scenario. Text-free
  prompt by design. Requires a Gemini key; not available on OpenRouter-only keys.
- DB: `insertScenario`, `deleteScenario`, `updateScenarioCover`, snapshot CRUD,
  `countNarrationsUpTo`. DB version 3 (snapshot table migration).
- Tests: `seed_data_test.dart` rewritten (old version expected a 23-scenario pack
  that no longer exists); now validates actual seed titles + cover round-trip.

Not yet done (carry-over + new):
- On-device end-to-end testing of: Do-mode turns, long-press rewind/delete,
  story creator (both modes), AI cover generation (needs Gemini key + quota).
- Release signing keystore (still debug-signed).
- OpenRouter has no image model — AI covers are Gemini-key-only (graceful
  error already handled).
- Stretch: NPC avatar display in player info sheet (npc `image` field is
  already persisted from the creator).

---

## Objective
Turn Storyloom (the web app at `/mnt/data2/AI model/storybot`) into a standalone
**Android app** for a single user: no backend, all data on-device (SQLite), AI
API called directly from the app. Deliverable: a usable **APK** — **DONE: `build/app/outputs/flutter-apk/app-release.apk`.**

## Environment / Toolchain (already installed & verified)
- App project: `/mnt/data2/AI model/storyloom-android` (project `storyloom`, org `io.storyloom`, Android-only).
- Flutter 3.47.2 via **fvm** 4.3.0:
  - SDK: `/home/mobius/fvm/versions/3.47.2`
  - Symlink: `/home/mobius/fvm/default/bin/flutter` (add to `PATH`)
  - fvm bin: `$HOME/.pub-cache/bin`
- JDK 17.0.20.1+1: `/mnt/data2/android-toolchain/jdk-17.0.20.1+1`
- Android SDK: `/mnt/data2/android-toolchain/android-sdk` (cmdline-tools/latest, platform-tools, platforms 34/35/36, build-tools 34/35/36).
  - ⚠️ `platforms/android-37.0` is a *broken/mislabeled platform 17* install — do NOT rely on it. Real `android-37` is NOT available from this SDK snapshot (sdkmanager can't fetch it). Any plugin whose compileSdk = 37 will fail the build; pin such plugins down (see flutter_secure_storage note below).
- `flutter doctor`: Android toolchain ✓ (SDK 36). Chrome/Linux warnings irrelevant.

### Shell gotcha
Each Bash call is a fresh shell — re-export every time:
```bash
export PATH="$HOME/fvm/default/bin:$PATH"
export JAVA_HOME=/mnt/data2/android-toolchain/jdk-17.0.20.1+1
export ANDROID_HOME=/mnt/data2/android-toolchain/android-sdk
```

## Product decisions (locked)
- Single user (the app owner). No backend, no auth.
- Data lives on-device in SQLite (`storyloom.db` via sqflite); settings in SharedPreferences.
- Two AI providers supported: **Google Gemini** (SDK) and **OpenRouter** (HTTP).
- API key entered on-device in Settings (do **NOT** bake a key into the APK).
- Framework: Flutter (user's choice, confirmed).
- Default model: `gemini-3.6-flash`.

## Supported Models (verified Aug 30, 2026)

**Gemini (free tier):**
- `gemini-3.6-flash` (default)
- `gemini-3.5-flash`
- `gemini-3.5-flash-lite`
- `gemini-2.5-flash`

**OpenRouter (free models):**
- `openrouter/free` (auto-router)
- `nvidia/nemotron-3-ultra-550b-a55b:free`
- `minimax/minimax-m3:free`
- `nvidia/nemotron-3.5-lightning:free`
- `z-ai/glm-5.2:free`
- `google/gemma-4-31b-it:free`

## Work state
### Completed
1. Toolchain installed + `flutter doctor` verified.
2. `flutter create` done, fvm 3.47.2 pinned, deps added:
   `google_generative_ai`, `sqflite`, `path`, `path_provider`,
   `shared_preferences`, `provider`, `http`, `flutter_secure_storage`.
3. **Data models**: `lib/models/analysis.dart` (TurnAnalysis + Gemini response
   `Schema` builder), `scenario.dart`, `character.dart`, `story.dart`
   (Story/StoryMessage/StoryNPC/Quest/InventoryItem/Memory).
4. **Data layer**: `lib/data/database.dart` (sqflite schema + CRUD; tables:
   scenarios, stories, messages, npcs, quests, inventory_items, memories),
   `lib/data/settings.dart` (AppSettings + **SettingsStore**: non-secret
   settings in SharedPreferences JSON, but the **API key is stored
   in `flutter_secure_storage`** (EncryptedSharedPreferences/Android Keystore)),
   `lib/data/seed_scenarios.dart` (**10 scenarios**: Arcanum Academy, My Entire
   Class Got Isekaied, The Hero's Shadow, Kicked to the Curb, The Extra in the
   Villainess Story, The Ninth Hour, Low Orbit: ELLEN, The Hollow Crown,
   Analog Heart, Fault Lines).
5. **Engine (ported faithfully from backend)**: `lib/engine/world_state.dart`
   (default_state, apply_analysis — port of state_service.py),
   `prompt_builder.dart` (system prompt, world/player/state/NPC/memory/scene/
   action sections, analysis/summarize/opening prompts — port of prompt_builder.py),
   `memory.dart` (maxPinned=15, summary handling — port of memory_service.py),
   `gemini_api.dart` (Gemini SDK streaming + OpenRouter HTTP streaming with SSE
   parsing, retry-until-first-token, structured JSON analysis via response schema,
   summarize, opening, connection test, error mapping — provider-aware routing),
   `story_engine.dart` (createStory, generateOpening, runTurn pipeline,
   applyAnalysisToWorld with NPC/quest/inventory upserts + deduped system cards
   cap 6, periodic summarize, **regenerate**, NPC data loss fix for
   backstory_hook/profession_class/speech_style).
6. **UI (ALL written + compiling)**: `lib/ui/theme.dart` (Material3, dark-first),
   `lib/ui/widgets.dart` (GenreBanner, TagChip, ScenarioCard, StoryTile with
   delete callback, kind→icon map), `lib/ui/home_page.dart` (library + discover
   tabs, API-key gate), `lib/ui/scenario_page.dart` (detail, rating badge, NPC rows,
   character-creator bottom sheet, begin flow, provider-agnostic text),
   `lib/ui/player_page.dart`
   (streaming narration w/ blinking cursor, dialogue parsing, SelectableText for
   copy, suggestion chips, free input, Continue/Regenerate, immersive mode,
   World/Companions/Quests/Items sheet, error snacks, story delete via popup menu),
   `lib/ui/settings_page.dart` (API key dialog via secure
   storage, model dropdown with provider-aware labels, temperature/token/context sliders,
   auto-memory/summarize toggles, dark mode, **test connection**),
   `lib/app.dart` (`StoryloomApp` + `ChangeNotifierProvider<AppState>`),
   `lib/main.dart`.
7. **OpenRouter integration** (Aug 30): HTTP streaming with SSE parsing,
   non-streaming helper for analysis/summarize/opening, model detection
   (`isOpenRouterModel`, `openRouterModelId`), provider-aware settings UI.
8. **Bug fixes** (Aug 30):
   - Chat messages disappearing: fixed sequence number collision in `applyAnalysisToWorld`.
   - Story delete: added long-press delete in library + popup menu in player.
   - Text selection/copy: all `Text` widgets in player changed to `SelectableText`.
   - Duplicate seed scenario removed ("The Extra in the Villainess Story" had a 350-line
     duplicate colliding with "The Ninth Hour").
   - NPC data loss: `backstory_hook`, `profession_class`, `speech_style` now preserved
     through world application and sent to AI prompt.
   - Provider-agnostic UI text: "Gemini" removed from all user-facing messages.
9. **Model list updated** (Aug 30): replaced dead models (Llama, Mistral, Qwen, DeepSeek
   no longer free on OpenRouter; old Gemini 2.x models) with current free models.
   Default changed to `gemini-3.6-flash`.
10. **Toolchain gates pass**:
    - `fvm flutter analyze`: **No issues found!**
    - `fvm flutter test`: passes — widget smoke test boots `StoryloomApp` using
      `sqflite_common_ffi` + `SharedPreferences.setMockInitialValues({})`.
    - `fvm flutter build apk --release` ✓ →
      `build/app/outputs/flutter-apk/app-release.apk` (debug-signed).
    - No `AIza…` key anywhere in source/assets; the repo has no real key in it.

### Not yet done
- On-device testing (no adb device/emulator available in this env) — install
  `app-release.apk` on a phone and run a real end-to-end story turn.
- Real release signing keystore (currently debug-signed via
  `signingConfigs.getByName("debug")` in `android/app/build.gradle.kts`).
- Replacing the deprecated `encryptedSharedPreferences` flag is moot: pinned at
  9.2.4 because **flutter_secure_storage ≥ 10 requires android-37 platform
  which is unavailable in this SDK snapshot** (build error: "Failed to find
  target with hash string 'android-37'").

### Remaining (stretch)
- Character creator UI is basic; could be polished.
- Onboarding showing STEP 1: get an API key.
- Age verification gate for mature-rated scenarios (currently prompt-level only, no UI gate).

## Key files (web backend = source of truth to port)
- `/mnt/data2/AI model/storybot/backend/app/services/ai/prompt_builder.py`
- `/mnt/data2/AI model/storybot/backend/app/services/state_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/memory_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/story_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/ai/gemini_provider.py`
- `/mnt/data2/AI model/storybot/backend/app/services/settings_service.py`
- `/mnt/data2/AI model/storybot/backend/app/core/config.py`
- `/mnt/data2/AI model/storybot/.env` — real key (reference only, never in APK)

## API reference (Dart SDK)
- `~/.pub-cache/hosted/pub.dev/google_generative_ai-0.4.7/lib/src/function_calling.dart`
  → `Schema.object({properties, requiredProperties, nullable})`, `SchemaType.*`,
  `Schema.enumString(...)`, `Schema.array(items:)`.
- `.../model.dart` → `GenerativeModel(model:, apiKey:, generationConfig:, systemInstruction:)`,
  `generateContent([])`, `generateContentStream([])` → each `GenerateContentResponse.text`.

 11. **Phase 3 — Scenario expansion** (2026-10-06):
     - `seed_scenarios.dart` fully rewritten with 16 scenarios (was broken from incremental edits).
     - Arcanum Academy upgraded with storyexample.txt version.
     - My Bullies Got Isekaied Too! added from storyexample.txt.
     - 6 new scenarios: Cast Out by the Kingdom, Hero Academy: Underdog, Tower of Ascension, Zombie Apocalypse: Last Light, Wholesome Isekai: Walking Path.
     - All 16 scenarios have 2-3 forks each.
