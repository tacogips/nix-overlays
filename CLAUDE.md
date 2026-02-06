# nix-overlays

## Purpose

This repository provides Nix overlays to override or add packages on top of nixpkgs. It is consumed as a flake input (`github:tacogips/nix-overlays`) from the NixOS/Darwin configuration repository (`~/nix/nixos`).

The primary use case is pinning packages to newer versions than what nixpkgs currently provides.

## Directory Structure

```
nix-overlays/
├── CLAUDE.md                        # This file
├── flake.nix                        # Flake entry point: exposes overlays, packages, devShell
├── Taskfile.yml                     # go-task definitions for build verification
├── .claude/commands/                # Claude slash commands
│   └── update-all-overlay-packages.md  # /update-all-overlay-packages
├── .github/workflows/               # GitHub Actions
│   ├── build.yml                    # CI build on push
│   └── update-packages.yml         # Daily auto-update of overlay packages
├── scripts/
│   └── update-packages.sh          # Package update script (used by CI and locally)
├── claude-code/                     # claude-code package overlay (npm / buildNpmPackage)
│   ├── package.nix
│   └── package-lock.json
├── codex/                           # codex package overlay (Rust / buildRustPackage)
│   └── package.nix
└── zig/                             # zig package (legacy, requires sources.json)
    └── default.nix
```

## How Overlays Work

Each overlay is a subdirectory containing a `package.nix`. The `flake.nix` exposes them in two ways:

1. **`overlays.<name>`** -- Overlay function (`final: prev: { ... }`) for consumers to apply via `import nixpkgs { overlays = [ ... ]; }`
2. **`packages.<system>.<name>`** -- Directly buildable package for standalone testing

### Consumer Side (nixos repo)

In `~/nix/nixos/linux/flake.nix` and `~/nix/nixos/darwin/flake.nix`:

```nix
inputs.nix-overlays.url = "github:tacogips/nix-overlays";

pkgs = import nixpkgs {
  overlays = [
    nix-overlays.overlays.claude-code
    nix-overlays.overlays.codex
  ];
};
```

This makes `pkgs.claude-code` and `pkgs.codex` resolve to the versions defined in this repo instead of the nixpkgs defaults.

## Development Shell

Enter with `nix develop`. Provides: go-task, nix-prefetch-git, jq, curl.

## Package Types

### npm packages (claude-code)

Uses `buildNpmPackage`. Requires:
- `package.nix` with `fetchzip` from npm registry
- `package-lock.json` generated via `npm install --package-lock-only --ignore-scripts`
- `npmDepsHash` (obtain by setting to `""`, building, reading error output)

### Rust packages (codex)

Uses `rustPlatform.buildRustPackage`. Requires:
- `package.nix` with `fetchFromGitHub`
- `cargoLock` with `lockFile` pointing to `Cargo.lock` from source
- `outputHashes` for any git dependencies (obtain via `nix-prefetch-git`)

## Adding a New Overlay

1. Create a directory: `mkdir new-package/`
2. Write `new-package/package.nix` with the package definition
3. Add to `flake.nix`:
   - `packages.<name>` in the `eachSystem` block
   - `overlays.<name>` in the overlays attrset
4. Add a build task to `Taskfile.yml`
5. Verify with `task build-<name>`
6. Push, then update the lock in the nixos repo: `nix flake lock --update-input nix-overlays`

## Updating Packages

Use the Claude slash command `/user-update-all-overlay-packages` to update all packages at once, or follow the manual steps below.

### Updating claude-code (npm)

1. Check latest: `curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | jq .version`
2. Prefetch source:
   ```sh
   nix-prefetch-url --unpack "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-<VERSION>.tgz" --type sha256
   nix hash to-sri --type sha256 <HASH>
   ```
3. Generate `package-lock.json`:
   ```sh
   cd /tmp && rm -rf pkg-update && mkdir pkg-update && cd pkg-update
   curl -sL "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-<VERSION>.tgz" | tar xz --strip-components=1
   nix-shell -p nodejs --run "npm install --package-lock-only --ignore-scripts"
   cp package-lock.json <repo>/claude-code/
   ```
4. Update `version`, `hash` in `package.nix`, set `npmDepsHash = ""`
5. `git add`, build (fails with correct hash), set `npmDepsHash`, rebuild

### Updating codex (Rust)

1. Check latest: `curl -s "https://api.github.com/repos/openai/codex/releases?per_page=5" | jq -r '.[].tag_name' | grep '^rust-v[0-9]' | grep -v alpha | head -1`
2. Prefetch source:
   ```sh
   nix-prefetch-url --unpack "https://github.com/openai/codex/archive/refs/tags/rust-v<VERSION>.tar.gz" --type sha256
   nix hash to-sri --type sha256 <HASH>
   ```
3. Update `version`, `hash` in `package.nix`
4. Check and update git deps in `cargoLock.outputHashes` (see `.claude/commands/update-all-overlay-packages.md` for details)
5. `git add`, build to verify

## Automated Updates

A daily GitHub Action (`.github/workflows/update-packages.yml`) runs at 09:00 UTC to check for new versions of all overlay packages. It runs `scripts/update-packages.sh`, which:

1. Checks npm registry / GitHub releases for newer versions
2. Prefetches source hashes
3. Updates `package.nix` files (version, hash, npmDepsHash / outputHashes)
4. Verifies builds with `nix build`
5. Commits and pushes changes directly to main

The workflow can also be triggered manually via `gh workflow run update-packages.yml`.

To run the update script locally: `bash scripts/update-packages.sh` or `task update-packages`.

## Build Verification

```sh
task build-claude-code   # Build claude-code
task build-codex         # Build codex
task build-all           # Build all packages
task check               # Check flake configuration
task fmt                 # Format nix files
```
