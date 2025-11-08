# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kelivo is a modern Flutter LLM chat client supporting multiple AI providers (OpenAI, Gemini, Anthropic, etc.) with cross-platform support for Android, iOS, Windows, and experimental Web/macOS. The app features custom assistants, MCP (Model Context Protocol) tool integration, multi-modal input, web search capabilities, and local Hive database storage.

**Core Technologies:**
- Flutter SDK 3.8.1+ / Dart SDK 3.7+ (mcp_client requires Dart >= 3.7)
- State Management: Provider pattern
- Local Storage: Hive (NoSQL database with type adapters)
- Multi-platform: Mobile-first with desktop (Windows) as added platform
- MCP: Model Context Protocol client integration

## Common Development Commands

### Setup and Dependencies
```bash
# Install dependencies
flutter pub get

# Generate code for Hive adapters, i18n, etc.
flutter pub run build_runner build --delete-conflicting-outputs

# Clean and rebuild when dependencies are problematic
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running the App
```bash
# Run debug build (auto-detects connected device)
flutter run

# Run on specific device
flutter run -d <device_id>

# List available devices
flutter devices

# Run Windows desktop (from Windows machine)
./flutter/bin/flutter.bat run -d windows --debug

# Run Windows release build
./flutter/bin/flutter.bat run -d windows --release
```

### Building Release Versions
```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS (requires macOS)
flutter build ios --release

# Windows (requires Windows)
# Use scripts/build_windows.ps1 for automated builds
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/build_windows.ps1
# Or use Flutter directly:
flutter build windows --release
```

### Code Quality and Testing
```bash
# Static analysis
flutter analyze

# Analyze specific file
flutter analyze lib/desktop/desktop_settings_page.dart

# Run tests
flutter test

# Format code
dart format .
```

### Build Runner (Code Generation)
```bash
# Generate Hive type adapters and other generated code
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for continuous generation during development
flutter pub run build_runner watch --delete-conflicting-outputs
```

## Architecture Overview

### High-Level Structure
```
lib/
├── core/              # Business logic, models, services, providers
│   ├── models/        # Data models (Hive-annotated, e.g., Conversation, ChatMessage)
│   ├── providers/     # State management (ChangeNotifier-based)
│   ├── services/      # Business services (API, chat, MCP, search, backup, TTS)
│   └── utils/         # Core utilities
├── features/          # Feature modules (UI + feature-specific logic)
│   ├── chat/          # Chat UI, message widgets, history
│   ├── assistant/     # Assistant management
│   ├── provider/      # AI provider configuration
│   ├── settings/      # Settings screens
│   ├── mcp/           # MCP server management UI
│   ├── search/        # Web search integration UI
│   └── ...
├── desktop/           # Desktop-specific UI (Windows/macOS/Linux)
├── shared/            # Shared widgets and components
├── theme/             # Theme configuration (Material You, palettes)
├── l10n/              # Internationalization (Chinese/English)
└── main.dart          # App entry point
```

### Core Architectural Patterns

**Provider-Based State Management:**
- All major state is managed via `ChangeNotifier` providers (ChatProvider, SettingsProvider, AssistantProvider, McpProvider, etc.)
- Providers are registered in `main.dart` via `MultiProvider`
- UI widgets consume state using `context.watch<T>()` and mutate using `context.read<T>()`

**Hive Database Storage:**
- Conversations and messages stored in Hive boxes (`conversations`, `messages`, `tool_events_v1`)
- Type adapters generated via build_runner for ChatMessage and Conversation models
- ChatService (lib/core/services/chat/chat_service.dart) manages all database operations
- Box initialization happens in ChatService.init() called early in app lifecycle

**Multi-Platform Routing:**
- `_selectHome()` in main.dart routes to DesktopHomePage (Windows/macOS/Linux) or HomePage (mobile/web)
- Desktop uses a nav rail layout; mobile uses bottom navigation
- Platform detection via `kIsWeb` and `defaultTargetPlatform`

**AI Provider Integration:**
- ChatApiService (lib/core/services/api/chat_api_service.dart) handles all LLM API calls
- Supports OpenAI-compatible APIs, Gemini, Anthropic, etc.
- Provider configurations stored in ModelProvider
- Custom headers/body overrides per model via modelOverrides map
- Built-in tool support (search, url_context) configured per-model

**MCP (Model Context Protocol):**
- McpProvider manages MCP server connections and tool discovery
- McpToolService provides tool execution for conversations/assistants
- Servers can be stdio, SSE (Server-Sent Events), or WebSocket
- Tools are enabled per-server and selected per-conversation or per-assistant
- Tool results are formatted as markdown for model consumption

**Search Integration:**
- Multiple search providers: Exa, Tavily, Brave, Bing, Perplexity, SearxNG, etc.
- SearchToolService (lib/core/services/search/search_tool_service.dart) unifies search calls
- Search tools can be invoked by models via function calling or manually by users

### Platform-Specific Considerations

**Windows Desktop:**
- Custom title bar via window_manager (TitleBarStyle.hidden) - see WindowTitleBar widget
- Desktop-specific layouts in lib/desktop/ directory
- TTS (flutter_tts) disabled on Windows by default (stub implementation) due to NUGET.EXE dependency
  - Conditional imports: tts_impl.dart (mobile), tts_stub.dart (Windows)
- Build automation in scripts/build_windows.ps1
- Requires Visual Studio Build Tools with C++ workload

**iOS:**
- Sandbox path migration for file attachments (SandboxPathResolver handles absolute path rewrites)
- Per-app language support via SettingsProvider.appLocaleForMaterialApp

**Android:**
- Material You dynamic color support (dynamic_color package)
- Edge-to-edge system UI mode (transparent status/nav bars)

## Key Files and Components

### Entry Point and App Shell
- **main.dart**: App initialization, provider setup, window manager init (desktop), theme configuration, localization
- **lib/desktop/desktop_home_page.dart**: Desktop layout with nav rail
- **lib/features/home/pages/home_page.dart**: Mobile layout with bottom nav

### State Management (Providers)
- **ChatProvider**: Manages chat list, pinning, renaming
- **ChatService**: Hive database operations for conversations and messages
- **SettingsProvider**: App settings (theme, locale, feature flags)
- **AssistantProvider**: Custom assistant management, defaults
- **McpProvider**: MCP server connections and tool management
- **ModelProvider**: AI provider configurations (base URLs, API keys, model lists)
- **UserProvider**: User profile data

### AI Integration
- **lib/core/services/api/chat_api_service.dart**: HTTP client for LLM APIs, streaming support, tool calling
- **lib/core/services/chat/prompt_transformer.dart**: Transforms prompts with variables (model name, time, etc.)
- **lib/core/services/mcp/mcp_tool_service.dart**: MCP tool execution and result formatting

### UI Components
- **lib/features/chat/widgets/chat_message_widget.dart**: Message rendering (markdown, code blocks, images, tool calls)
- **lib/shared/widgets/**: Reusable widgets (dialogs, sheets, buttons)
- **lib/desktop/window_title_bar.dart**: Custom Windows title bar with drag area and caption buttons

### Code Generation
- Hive type adapters: ChatMessageAdapter, ConversationAdapter
- Generated files: *.g.dart (run build_runner to regenerate)

## Development Workflow Best Practices

**When adding new features:**
1. Add model classes to core/models/ with Hive annotations if persistence needed
2. Create provider in core/providers/ if state management required
3. Add UI in features/<feature_name>/ following existing structure
4. Run build_runner if added/modified Hive models
5. Update l10n/ for new UI strings (app_en.arb, app_zh.arb)

**When modifying database schema:**
1. Update Hive model classes and increment typeId if adding new models
2. Run `flutter pub run build_runner build --delete-conflicting-outputs`
3. Consider migration logic in ChatService.init() for existing users

**When working with AI providers:**
- Test with multiple providers (OpenAI, Gemini, Anthropic) as API differences exist
- Use ChatApiService static helpers for API key selection, custom headers, built-in tools
- Check modelOverrides for provider-specific configurations

**Windows builds:**
- Use scripts/build_windows.ps1 for consistent builds
- TTS is disabled by default (no user-facing impact due to stub)
- Ensure Visual Studio Build Tools installed with C++ Desktop Development workload

**Testing:**
- Widget tests in test/ directory (currently minimal)
- Manual testing on multiple platforms is critical
- Use `flutter analyze` before commits to catch lint issues

## Localization (i18n)

- Supported locales: English (en), Chinese (zh)
- ARB files in lib/l10n/ (app_en.arb, app_zh.arb)
- Access via `AppLocalizations.of(context)!.keyName`
- Set `generate: true` in pubspec.yaml triggers auto-generation

## Common Pitfalls

1. **Forgetting to run build_runner**: After modifying Hive models, always run `flutter pub run build_runner build --delete-conflicting-outputs`
2. **Platform-specific APIs**: Check platform before calling desktop-only or mobile-only APIs (use PlatformUtils)
3. **Provider initialization order**: Some providers depend on others being initialized first (e.g., ChatService.init() must complete before UI accesses conversations)
4. **Sandbox path migration (iOS)**: Absolute paths in file attachments break when app sandbox changes; SandboxPathResolver handles this
5. **Windows TTS**: Don't expect flutter_tts to work on Windows; use the stub pattern for platform-specific features
6. **Dynamic color**: Only available on Android 12+; check `SettingsProvider.dynamicColorSupported` before showing UI options

## External Dependencies Notes

- **mcp_client**: Requires Dart SDK >= 3.7 (see pubspec.yaml environment constraint)
- **window_manager**: Desktop window control (drag, resize, title bar customization)
- **hive/hive_flutter**: NoSQL database; requires type adapter registration before use
- **dynamic_color**: Material You dynamic theming on Android
- **flutter_tts**: TTS functionality; disabled on Windows via conditional imports

## Git Workflow

- Main branch: `master`
- Current feature branch: `feat/supabase-sync` (as of this snapshot)
- Never commit secrets (.env, credentials.json) - use .gitignore
- Use Chinese commit messages following repo convention (see git log)

## Contact and Support

- Issues: [GitHub Issues](https://github.com/Chevey339/kelivo/issues)
- Discord: [https://discord.gg/Tb8DyvvV5T](https://discord.gg/Tb8DyvvV5T)
