# Storyloom

**Create worlds. Become anyone. Write your own story.**

Storyloom is a private, on-device AI storytelling app for Android. You step into a
scenario — a fantasy kingdom, a neon-noir city, a dystopian wasteland — and let an AI
model narrate, react to your choices, and keep the world consistent as you go.

**Your stories never leave your phone.** There is no account, no backend, and no cloud
sync. Characters, quests, world state, and your entire history are stored in a local
SQLite database. The only network calls are to AI APIs, using **your own API key**
(Bring Your Own Key).

## Features

- **10 built-in scenarios** — fantasy academy, isekai, cyberpunk, post-apocalyptic,
  sci-fi, slice-of-life, political thriller, and more.
- **Create your own stories** — build a 1-on-1 roleplay (you + one character) or a
  full scenario with world, rules, tone, opening scene and a cast. Pick cover and
  character images from your gallery.
- **Say or Do** — plain input is spoken dialogue; type `*like this*` (or flip the
  Do toggle) to narrate an action, rendered as its own italic bubble and reacted
  to as a deed, not a quote.
- **Streaming narration** — story text streams in token-by-token as the model writes it.
- **Live world state** — the engine keeps a running model of NPCs, quests, inventory
  items, current location, mood, and tensions, and applies every turn's outcome to it.
- **Character creator** — before a story begins, tinker with your character's profile
  (appearance, personality, role).
- **Readable cast** — every scenario page has expandable character cards with full
  description, personality, speech style and backstory; the AI is bound to that
  cast and never invents replacement characters.
- **Suggested actions** — tap a suggested next action or type your own.
- **Rewind & delete** — long-press any message to return the story to that point
  (the world is restored from per-turn checkpoints) or delete from there; restart
  a story fresh at any time.
- **AI cover art** — generate a book-cover illustration for any scenario with your
  Gemini key (`gemini-2.5-flash-image`), saved on-device.
- **Memory & summaries** — key facts are pinned as long-term memories; long stories get
  periodically summarized so the model never loses context.
- **Immersive mode** — hide the chrome and focus on the story.
- **Companion sheets** — open the world, your companions, active quests, and inventory
  at any time.
- **Regenerate** — rewrite the last turn's narration when you don't like the direction.
- **Text selection & copy** — long-press any story text to copy it.
- **Story management** — long-press a story in the library to delete it.
- **Dark mode + light mode**, adjustable model temperature, token budget, and context size.

## AI Providers

Storyloom supports two providers — use whichever you prefer:

| Provider | Models | Cost |
|---|---|---|
| **Google Gemini** | `gemini-3.6-flash`, `gemini-3.5-flash`, `gemini-3.5-flash-lite`, `gemini-2.5-flash` | Free tier available |
| **OpenRouter** | `openrouter/free` (auto-router), Nemotron 3 Ultra, MiniMax M3, Nemotron 3.5 Lightning, GLM 5.2, Gemma 4 | Free models, no credit card required |

Get a Gemini key at <https://aistudio.google.com/app/apikey>.
Get an OpenRouter key at <https://openrouter.ai/keys>.

## Tech Stack

| Layer      | Choice                                                        |
|------------|---------------------------------------------------------------|
| Language   | Dart 3 / Flutter 3.47 (Material 3)                           |
| AI         | Google Gemini (`google_generative_ai`) + OpenRouter (`http`)  |
| Images     | `image_picker` (gallery covers/avatars) + Gemini image model  |
| Storage    | SQLite via `sqflite` (world state, stories, memories, rewind checkpoints) |
| Settings   | `shared_preferences` (non-secret) + `flutter_secure_storage` (API key, encrypted) |
| State      | `provider`                                                     |

## Requirements

- Android 6.0+ (minSdk 19); tested against Android 36 (SDK 36).
- A Gemini API key **or** an OpenRouter API key (both have free tiers).

## Get Started

### Option A — Install the APK (no build required)

1. Grab the latest release APK from
   `build/app/outputs/flutter-apk/app-release.apk`.
2. Copy it to your phone and open it (or run `adb install app-release.apk`).
3. Launch **Storyloom** → open **Settings** → paste your API key →
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

- Your API key is **your own** and is stored encrypted
  (`flutter_secure_storage`, backed by the Android Keystore). It is never hardcoded
  into the APK, never logged, and never uploaded anywhere except to the AI provider
  you configure.
- All story data is stored locally in SQLite. Deleting the app deletes your stories.
- No analytics, no tracking, no permissions beyond what's needed for offline data
  (only INTERNET permission for calling AI APIs).

## Project Structure

```
lib/
  app.dart             # App widget + Provider wiring
  main.dart            # Entry point
  app_state.dart       # Global state (settings, engine lifecycle)
  data/
    database.dart      # SQLite schema + CRUD (stories, world snapshots, scenarios)
    settings.dart      # Settings + secure API-key storage + model lists
    seed_scenarios.dart# 10 built-in scenarios
  engine/
    story_engine.dart  # Turn pipeline: opening, run-turn, regenerate, rewind, restart
    gemini_api.dart    # Gemini + OpenRouter client, streaming, error mapping
    prompt_builder.dart# System/world/state/cast/memory/scene prompt sections
    memory.dart        # Long-term memory + summarization
    world_state.dart   # NPC/quest/inventory/location state model
    cover_art.dart     # AI cover-art generation (Gemini image model)
  models/              # analysis, scenario, character, story
  ui/
    home_page.dart     # Library + Discover tabs + New story FAB
    create_story_page.dart # Story creator: 1-on-1 roleplay & full story modes
    scenario_page.dart # Scenario detail, cast cards, AI art, character creator
    player_page.dart   # The story player (streaming, Say/Do, rewind, delete)
    settings_page.dart # API key, model, temperature, theme
    theme.dart, widgets.dart
```

## Status

Working Android build with a passing analyze/test gate. Recent additions: story
creator, Say/Do actions, message rewind/delete with world checkpoints, AI cover
art, and cast-accurate openings — these are analyze/test-verified but not yet
exercised end-to-end on a device. The release APK is currently signed with the
debug keystore (fine for sideloading); a dedicated signing keystore is needed
before distributing to a store. See [`PROGRESS.md`](PROGRESS.md) for the full
handoff ledger and outstanding items.
