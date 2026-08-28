# Storyloom Android — Progress & Handoff Notes

> Session ledger so any future session can pick up fast. Last updated: 2026-08-28 (APK milestone).

## Objective
Turn Storyloom (the web app at `/mnt/data2/AI model/storybot`) into a standalone
**Android app** for a single user: no backend, all data on-device (SQLite), Gemini
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
- Gemini is the only external dependency; API key entered on-device in Settings (do **NOT** bake a key into the APK).
- Framework: Flutter (user's choice, confirmed).
- Default model: `gemini-2.5-flash` (deprecated 1.x/gemini-2.0-flash list already replaced in the web app).

## Work state
### Completed
1. Toolchain installed + `flutter doctor` verified.
2. `flutter create` done, fvm 3.47.2 pinned, deps added:
   `google_generative_ai 0.4.7`, `sqflite 2.4.3`, `path`, `path_provider`,
   `shared_preferences 2.5.5`, `provider 6.1.5+1`, `http ^1.6.0`,
   `flutter_secure_storage 9.2.4` (dev: `sqflite_common_ffi`).
3. **Data models**: `lib/models/analysis.dart` (TurnAnalysis + Gemini response
   `Schema` builder), `scenario.dart`, `character.dart`, `story.dart`
   (Story/StoryMessage/StoryNPC/Quest/InventoryItem/Memory).
4. **Data layer**: `lib/data/database.dart` (sqflite schema + CRUD; tables:
   scenarios, stories, messages, npcs, quests, inventory_items, memories),
   `lib/data/settings.dart` (AppSettings + **SettingsStore**: non-secret
   settings in SharedPreferences JSON, but the **Gemini API key is now stored
   in `flutter_secure_storage`** (EncryptedSharedPreferences/Android Keystore),
   with graceful fallback on devices/tests where secure storage is unavailable;
   old plaintext `api_key` pref is still read as a migration fallback),
   `lib/data/seed_scenarios.dart`
   (5 scenarios: The Last Mage, Neon Ashes, After the Fall, The Village Beyond
   the Mist, Another World, Another Life).
5. **Engine (ported faithfully from backend)**: `lib/engine/world_state.dart`
   (default_state, apply_analysis — port of state_service.py),
   `prompt_builder.dart` (system prompt, world/player/state/NPC/memory/scene/
   action sections, analysis/summarize/opening prompts — port of prompt_builder.py),
   `memory.dart` (maxPinned=15, summary handling — port of memory_service.py),
   `gemini_api.dart` (stream narrative with retry-until-first-token,
   structured JSON analysis via response schema, summarize, opening, connection
   test, error mapping — port of gemini_provider.py; uses Dart typed `Schema`;
   SDK 0.4.7 exports `GenerativeAIException`/`InvalidApiKey`/`UnsupportedUserLocation`/
   `ServerException`/`GenerativeAISdkException` — **NOT `ApiException`**),
   `story_engine.dart` (createStory, generateOpening, runTurn pipeline,
   applyAnalysisToWorld with NPC/quest/inventory upserts + deduped system cards
   cap 6, periodic summarize, **regenerate**).
6. **UI (ALL written + compiling)**: `lib/ui/theme.dart` (Material3, dark-first),
   `lib/ui/widgets.dart` (GenreBanner, TagChip, ScenarioCard, StoryTile,
   kind→icon map), `lib/ui/home_page.dart` (library + discover tabs,
   API-key gate), `lib/ui/scenario_page.dart` (detail, rating badge, NPC rows,
   character-creator bottom sheet, begin flow), `lib/ui/player_page.dart`
   (streaming narration w/ blinking cursor, dialogue parsing, suggestion chips,
   free input, Continue/Regenerate, immersive mode, World/Companions/Quests/Items
   sheet, error snacks), `lib/ui/settings_page.dart` (API key dialog via secure
   storage, model dropdown `supportedModels`, temperature/token/context sliders,
   auto-memory/summarize toggles, dark mode, **test connection**),
   `lib/app.dart` (`StoryloomApp` + `ChangeNotifierProvider<AppState>`),
   `lib/main.dart`.
7. **Toolchain gates pass**:
   - `fvm flutter analyze`: **No issues found!**
   - `fvm flutter test`: passes — widget smoke test boots `StoryloomApp` using
     `sqflite_common_ffi` (`sqfliteFfiInit(); databaseFactory = databaseFactoryFfiNoIsolate;`)
     + `SharedPreferences.setMockInitialValues({})`; use timed `pump` loops,
     NOT `pumpAndSettle` (DB unlock/dialogs never settle).
   - `fvm flutter build apk --debug` ✓ and `--release` ✓ →
     `build/app/outputs/flutter-apk/app-release.apk` (54.5 MB, debug-signed).
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
- Onboarding showing STEP 1: get a Gemini API key.

## Key files (web backend = source of truth to port)
- `/mnt/data2/AI model/storybot/backend/app/services/ai/prompt_builder.py`
- `/mnt/data2/AI model/storybot/backend/app/services/state_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/memory_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/story_service.py`
- `/mnt/data2/AI model/storybot/backend/app/services/ai/gemini_provider.py`
- `/mnt/data2/AI model/storybot/backend/app/services/settings_service.py`
- `/mnt/data2/AI model/storybot/backend/app/core/config.py` (defaults; model now gemini-2.5-flash)
- `/mnt/data2/AI model/storybot/.env` — real Gemini key (reference only, never in APK)

## Known web-app work already done (storybot) — don't redo
- alembic migrations applied + seeded; gemini-2.0-flash → 2.5 models everywhere;
  gemini_provider schema fix (`_gemini_response_schema` helpers) verified E2E;
  31/31 backend tests pass; frontend typecheck/lint/build pass.

## API reference (Dart SDK)
- `~/.pub-cache/hosted/pub.dev/google_generative_ai-0.4.7/lib/src/function_calling.dart`
  → `Schema.object({properties, requiredProperties, nullable})`, `SchemaType.*`,
  `Schema.enumString(...)`, `Schema.array(items:)`.
- `.../model.dart` → `GenerativeModel(model:, apiKey:, generationConfig:, systemInstruction:)`,
  `generateContent([])`, `generateContentStream([])` → each `GenerateContentResponse.text`.