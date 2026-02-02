# Repository Guidelines

## Project Structure & Module Organization
- `reflect/`: App source (SwiftUI views, models) and `Assets.xcassets`.
- `reflect.xcodeproj/`: Xcode project and shared scheme.
- `reflectTests/`, `reflectUITests/`: Unit and UI tests.

## Build, Test, and Development Commands
```sh
xcodebuild -scheme reflect -destination 'platform=iOS Simulator,name=iPhone 15' build
```
```sh
xcodebuild -scheme reflect -destination 'platform=iOS Simulator,name=iPhone 15' test
```

## Coding Style & Naming Conventions
- 4-space indentation, no tabs; follow Swift naming (`UpperCamelCase` types, `lowerCamelCase` members).
- File names match the primary type (e.g., `ContentView.swift`); keep Xcode’s formatting.

## Testing Guidelines
- Methods start with `test`; unit tests live in `reflectTests/`, UI tests in `reflectUITests/`.
- No coverage threshold; add tests for new behavior and regressions.

## Commit & Pull Request Guidelines
- History is minimal (only “Initial Commit”), so no convention is established.
- Use concise, imperative commit subjects (e.g., “Add item list view”).
- PRs should include a brief summary, testing notes, and screenshots for UI changes.

## Security & Configuration Tips
- Configuration lives in `reflect/Info.plist` and `reflect/reflect.entitlements`; document capability changes.

## Agent-Specific Instructions
- Always use Context7 MCP for library/API docs, code generation, and setup/config steps without being asked.
- Use Supabase as the server backend and connect to it via MCP.

## Agent Conduct
- Verify assumptions before commands; call out uncertainties first.
- Ask for clarification when a request is ambiguous, destructive, or risky.
- Summarize intent before multi-step fixes.
- Cite documentation sources; quote exact lines instead of paraphrasing.
- Work in small steps and confirm with the smallest relevant check.

## Commands and Checks
- Show a plan before large edits.
- Capture exit codes and logs.
- Run impacted checks only: lint → changed files; typecheck → touched modules; test → nearest tests (expand only if upstream fails).
- Stop on failure; summarize root cause; propose the smallest fix.
- If no automated checks apply, say so and describe manual validation.
- After each incremental change, run the quickest verifying command from this file.

## Critical Thinking
- Fix root causes, not band-aids.
- If unsure, read more code; if still stuck, ask with short options.
- Call out conflicts and choose the safer path.
- If you encounter unrecognized changes, assume another agent made them and keep your changes focused; if it causes issues, stop and ask the user.
- Leave breadcrumb notes in the thread.
