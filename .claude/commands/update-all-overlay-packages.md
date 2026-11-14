# Update All Overlay Packages

Update every overlay package in this repository to the latest version. Follow the steps below for each package.

## General Steps Per Package

1. **Check the current version** in `<package>/package.nix`
2. **Find the latest upstream version**:
   - For nixpkgs-based packages, check the latest version in the NixOS/nixpkgs repository (master branch) at `pkgs/by-name/` using gitcodes-mcp tools
   - For npm packages (e.g. claude-code): `curl -s https://registry.npmjs.org/@anthropic-ai/claude-code/latest | jq .version`
   - For GitHub Rust packages (e.g. codex): check the latest release tags on the GitHub repo
3. **Skip if already latest**: If the current version matches the latest, skip the package
4. **Update the package** (see package-type-specific instructions below)
5. **Build to verify**: `nix build .#<package-name> --no-link --print-out-paths`
6. **Verify the binary**: Run `<store-path>/bin/<binary> --version` to confirm

## npm Package Update (claude-code)

1. Get the source hash:
   ```sh
   nix-prefetch-url --unpack "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-<VERSION>.tgz" --type sha256
   nix hash to-sri --type sha256 <HASH>
   ```
2. Generate new `package-lock.json`:
   ```sh
   cd /tmp && rm -rf pkg-update && mkdir pkg-update && cd pkg-update
   curl -sL "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-<VERSION>.tgz" | tar xz --strip-components=1
   nix-shell -p nodejs --run "npm install --package-lock-only --ignore-scripts"
   cp package-lock.json <repo>/claude-code/package-lock.json
   ```
3. Update `version` and `hash` in `package.nix`
4. Set `npmDepsHash = ""`, git add, build to get the correct hash from the error message
5. Set the correct `npmDepsHash`, git add, build again to verify

## Rust Package Update (codex)

1. Prefetch the new source:
   ```sh
   nix-prefetch-url --unpack "https://github.com/openai/codex/archive/refs/tags/rust-v<VERSION>.tar.gz" --type sha256
   nix hash to-sri --type sha256 <HASH>
   ```
2. Update `version` and `hash` in `package.nix`
3. Check git dependencies in the new `Cargo.lock`:
   ```sh
   curl -sL "https://github.com/openai/codex/archive/refs/tags/rust-v<VERSION>.tar.gz" | tar xz
   grep 'source = "git' codex-rust-v<VERSION>/codex-rs/Cargo.lock
   ```
4. For each git dependency, get the hash:
   ```sh
   nix-shell -p nix-prefetch-git --run "nix-prefetch-git --quiet --rev <REV> <REPO_URL>" | jq -r '.sha256'
   nix hash to-sri --type sha256 <HASH>
   ```
5. Update `cargoLock.outputHashes` with new crate names/versions and hashes
6. git add, build to verify

## After All Updates

1. Run `task build-all` to verify everything builds
2. Report the version changes made
