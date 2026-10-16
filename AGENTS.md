# Project instructions

Read `~/.agents/AGENTS.md` for global instructions.

This is a native SwiftUI habit tracker for iOS, with a macOS companion and WidgetKit extensions. The owner selected the product name Avvi and the public repository turinglabsorg/avvi.

- Read `DESIGN.md` before changing UI.
- Use default system typography throughout app, widgets, and icon. Do not introduce serif or editorial typefaces.
- Keep the pure domain and scheduling logic in `Core/`; it must run under Swift Package Manager tests.
- App and widget share their SwiftData schema in `Shared/`.
- Never label simulated, disconnected, or unverified integrations as synchronized.
- Calendar completion and habit completion are separate concepts. Only explicit user logging changes progress.
- Calendar writes require a visible user confirmation and must be idempotent.
- All documentation and code are in English. The initial app interface is Italian.
