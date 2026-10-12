# PM Pane

A minimal macOS app that keeps developer packages up to date across Homebrew, npm, pip, gem, uv, and bun — one pane instead of jumping between CLIs.

<img width="1626" height="1097" alt="Screenshot 2026-10-12 at 14 17 44" src="https://github.com/user-attachments/assets/4dbb2020-40e2-41c6-96be-37de19e33eed" />

## What it does

- **Lists** installed Homebrew formulae/casks (with tap + trust info), global npm / pip / gem / bun packages, and `uv tool` installs
- **Surfaces outdated** packages in one Updates view, with search, filters, and optional tap grouping
- **Upgrades and removes** with the exact command shown first — nothing runs without confirmation
- **Respects local prefs** — ignore a package or skip a version without pinning in the package manager

Requires **macOS 15+**. Homebrew is recommended.

## Install with Homebrew

```sh
brew install --cask orknist/tap/pmpane
```

Upgrade later with:

```sh
brew update
brew upgrade --cask pmpane
```

## Build from source

You need **macOS 15+** and **Xcode 16+**.

### Xcode

1. Open the project:
   ```sh
   open PMPane.xcodeproj
   ```
2. Confirm the scheme is **PM Pane** and the destination is **My Mac**.
3. **Product → Run** (⌘R).

If no window appears:

- Check the Dock for **PM Pane**; it can open behind Xcode.
- Reset saved window/column state if needed:
  ```sh
  defaults delete app.pmpane.PMPane
  ```
  Then run again with ⌘R.
- For build errors, open the Report navigator (⌘9). Resolve packages once via **File → Packages → Resolve Package Versions**.

### Terminal

```sh
git clone https://github.com/orknist/pmpane.git
cd pmpane
xcodebuild -project PMPane.xcodeproj -scheme "PM Pane" -destination 'platform=macOS' -derivedDataPath build build
open "build/Build/Products/Debug/PM Pane.app"
```

## Middle-column controls

| Control | What it does |
| --- | --- |
| **Reload Packages** | Re-scans the current sidebar scope in parallel (All/Updates → every manager; Formulae/Casks/Taps → Homebrew only; npm/pip/gem/uv/bun → that manager only). Sidebar rows show a spinner per manager while it runs. Does not run `brew update`. |
| **Update Homebrew** | Separate toolbar capsule on All / Updates / Formulae / Casks / Taps. Runs `brew update` (catalog refresh), then reloads Homebrew only. Hidden on npm / pip / gem / uv / bun so the Reload / filter capsules do not shift. |
| **Search** | Filters packages in the middle list. |
| **All / Outdated / …** | Segmented list filters (**Ignored** shows packages muted via Ignore or Skip version). |
| **Group by Tap** | Groups packages under expandable tap sections; same table columns as the flat view. |
| **Include self-updating** | Shows greedy / self-updating cask upgrades in the package list and Updates count; passes `--greedy` when upgrading. When off, those greedy-only candidates are hidden (still listed under the **Self-update** filter). |

## UI overview

- Left: All / Updates / Formulae / Casks / Taps / npm / pip / gem / uv / bun
- Middle: package table (icons, optional tap grouping), search + filters
- Right: selected package icon, source, trust, **Dependencies** / **Required By**, actions (**Ignore this package** hides it from Updates / Outdated until cleared; **Skip this version** hides only the current latest and resurfaces when a newer release appears; both are local prefs, not Homebrew pin)
- Bottom: live command output

Every write operation (upgrade, remove, trust, …) shows the exact command first; nothing runs without confirmation. After a successful write, the UI applies an optimistic patch and re-scans only the affected package manager(s). Each manager’s busy state is independent — you can remove a bun package while pip is still refreshing.

## Tests

```bash
swift test
# Optional live brew merge:
PMPANE_LIVE_BREW=1 swift test --filter liveBrewMerge
```

## App icon

The Dock / Finder icon comes from `App/Assets.xcassets/AppIcon.appiconset` (wired as **AppIcon** in the Xcode target). Source PNGs also live under `icons/` for editing; after changing them, copy the new sizes into the `.appiconset` and rebuild (Product → Clean Build Folder if the Dock still shows the old icon).

## Notes

- App Sandbox is off so Homebrew can write under `/opt/homebrew` and home directories.
- Some casks need administrator access (e.g. files under `/usr/local`). At launch the app installs a `SUDO_ASKPASS` wrapper that re-opens PM Pane’s native password dialog when Homebrew invokes `sudo` — the app itself never runs as root. (Touch ID is unavailable on this path: Apple’s PAM skips biometrics in askpass mode.) Manual smoke: upgrade a cask like `battery` and confirm the Authorize dialog appears.
- Process PATH uses Homebrew / `/usr/local` / MacPorts plus the resolved tool’s own `bin` directory (so `#!/usr/bin/env node` works). Login-shell session shims (e.g. `fnm_multishells`) are not used.
- npm is discovered from system prefixes and stable version-manager defaults (Volta, fnm, nvm, asdf, mise, nodenv, proto, nodebrew, nix profile) — only the manager’s default Node, not every installed version.
- uv is discovered from Homebrew / `/usr/local` / MacPorts, then `~/.local/bin` and `~/.cargo/bin`. Only tools installed via `uv tool` are listed (not `uv pip` / project environments). Tools installed with a version pin (`==` / range) show as **Pinned**; **Upgrade anyway** runs `uv tool install name@latest` (clears the pin). Unpinned tools use `uv tool upgrade`.
- bun is discovered from Homebrew / `/usr/local` / MacPorts, then `~/.bun/bin`. Only global packages (`bun pm ls --global`) are listed. Prefer installing the bun binary with Homebrew (not `npm i -g bun`). Range-held globals (Update == Current, Latest newer) show as **Pinned**; **Upgrade anyway** / normal upgrades use `bun update --global --latest`.
- Sparkle, Mac App Store, and GitHub Releases are not implemented yet.

## License

[MIT](LICENSE)
