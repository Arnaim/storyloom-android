# Storyloom

**Create worlds. Become anyone. Write your own story.**

Storyloom is a private, on-device AI storytelling app for Android. You step into a
scenario — a fantasy kingdom, a neon-noir city, a dystopian wasteland — and let a
Gemini model narrate, react to your choices, and keep the world consistent as you go.

**Your stories never leave your phone.** There is no account, no backend, and no cloud
sync. Characters, quests, world state, and your entire history are stored in a local
SQLite database. The only network calls are to Google's Gemini API, using **your own
API key** (Bring Your Own Key).

## Features

- **Multi-character scenarios** — pick from 5 built-in stories (fantasy, cyberpunk,
  post-apocalyptic, storybook, isekai) or let the narrator run free-form roleplay.
- **Streaming narration** — story text streams in token-by-token as the model writes it.
- **Live world state** — the engine keeps a running model of NPCs, quests, inventory
  items, current location, mood, and tensions, and applies every turn's outcome to it.
- **Character creator** — before a story begins, tinker with your character's profile
  (appearance, personality, role).
- **Suggested actions** — tap a suggested next action or type your own.
- **Memory & summaries** — key facts are pinned as long-term memories; long stories get
  periodically summarized so the model never loses context.
- **Companion sheets** — open the world, your companions, active quests, and inventory
  at any time.
- **Regenerate** — rewrite the last turn's narration when you don't like the direction.
- **Immersive mode** — hide the chrome and focus on the story.
- **Dark mode + light mode**, adjustable model temperature, token budget, and context size.

## Tech Stack

| Layer      | Choice                                                        |
|------------|---------------------------------------------------------------|
| Language   | Dart 3 / Flutter 3.47 (Material 3)                           |
| AI         | Google Gemini (`google_generative_ai` 0.4.7)                  |
| Storage    | SQLite via `sqflite` (world state, stories, memories)          |
| Settings   | `shared_preferences` (non-secret) + `flutter_secure_storage` (API key, encrypted) |
| State      | `provider`                                                     |

## Requirements

- Android 6.0+ (minSdk 19); tested against Android 36 (SDK 36).
- A Google Gemini API key (free tier available at
  <https://aistudio.google.com/app/apikey>). The default model is
  `gemini-flash-latest` (auto-updates to the newest Flash); you can also pick
  a specific recent model in Settings.

## Get Started

### Option A — Install the APK (no build required)

1. Grab the latest release APK from
   `build/app/outputs/flutter-apk/app-release.apk`.
2. Copy it to your phone and open it (or run `adb install app-release.apk`).
3. Launch **Storyloom** → open **Settings** → paste your Gemini API key →
   tap **Test connection**.
4. Pick a scenario on the **Discover** tab → customize your character → **Begin**.

### Option B — Build from source

Prerequisites: Flutter 3.47+ (`fvm` or a system install), JDK 17, Android SDK.

```bash
git clone <this-repo>
cd storyloom-android
flutter pub get
flutter build apk --release
# outputs to build/app/outputs/flutter-apk/app-release.apk
```

Contributors and future sessions: toolchain details, porting notes, and session state
live in [`PROGRESS.md`](PROGRESS.md).

## Privacy & Security

- The Gemini API key is **your own** and is stored encrypted
  (`flutter_secure_storage`, backed by the Android Keystore). It is never hardcoded
  into the APK, never logged, and never uploaded anywhere except to Google's Gemini
  API when you use the app.
- All story data is stored locally in SQLite. Deleting the app deletes your stories.
- No analytics, no tracking, no permissions beyond what's needed for offline data
  (no INTERNET permission is even required for data access — only for calling Gemini).

## Project Structure

```
lib/
  app.dart             # App widget + Provider wiring
  main.dart            # Entry point
  app_state.dart       # Global state (settings, engine lifecycle)
  data/
    database.dart      # SQLite schema + CRUD
    settings.dart      # Settings + secure API-key storage
    seed_scenarios.dart# 5 built-in scenarios
  engine/
    story_engine.dart  # Turn pipeline: opening, run-turn, regenerate
    gemini_api.dart    # Gemini client, streaming, error mapping
    prompt_builder.dart# System/world/state/memory prompt sections
    memory.dart        # Long-term memory + summarization
    world_state.dart   # NPC/quest/inventory/location state model
  models/              # analysis, scenario, character, story
  ui/
    home_page.dart     # Library + Discover tabs
    scenario_page.dart # Scenario detail + character creator
    player_page.dart   # The story player
    settings_page.dart # API key, model, temperature, theme
    theme.dart, widgets.dart
```

## Status

Working Android build with a passing analyze/test gate. The release APK is currently
signed with the debug keystore (fine for sideloading); a dedicated signing keystore is
needed before distributing to a store. See [`PROGRESS.md`](PROGRESS.md) for the full
handoff ledger and outstanding items.