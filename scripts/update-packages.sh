#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

log()  { echo "==> $*"; }
err()  { echo "ERROR: $*" >&2; }

###############################################################################
# claude-code (npm / buildNpmPackage)
###############################################################################
update_claude_code() {
  log "Checking claude-code..."
  local pkg_nix="$REPO_ROOT/claude-code/package.nix"
  local pkg_lock="$REPO_ROOT/claude-code/package-lock.json"

  # Current version
  local current
  current=$(grep -oP 'version = "\K[^"]+' "$pkg_nix" | head -1)
  log "  current version: $current"

  # Latest version from npm
  local latest
  latest=$(curl -sf https://registry.npmjs.org/@anthropic-ai/claude-code/latest | jq -r .version)
  if [[ -z "$latest" ]]; then
    err "Failed to fetch latest claude-code version from npm"
    return 1
  fi
  log "  latest  version: $latest"

  if [[ "$current" == "$latest" ]]; then
    log "  claude-code is already up to date"
    return 0
  fi

  log "  Updating claude-code $current -> $latest"

  # Prefetch source hash
  local raw_hash sri_hash
  raw_hash=$(nix-prefetch-url --unpack \
    "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${latest}.tgz" \
    --type sha256 2>/dev/null)
  sri_hash=$(nix hash to-sri --type sha256 "$raw_hash")
  log "  source hash: $sri_hash"

  # Generate package-lock.json
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" RETURN
  curl -sL "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${latest}.tgz" \
    | tar xz --strip-components=1 -C "$tmpdir"
  (cd "$tmpdir" && nix shell nixpkgs#nodejs -c npm install --package-lock-only --ignore-scripts 2>/dev/null)
  cp "$tmpdir/package-lock.json" "$pkg_lock"
  log "  package-lock.json updated"

  # Update version and source hash in package.nix
  sed -i "s/version = \"[^\"]*\"/version = \"${latest}\"/" "$pkg_nix"
  sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|" "$pkg_nix"

  # Set npmDepsHash to fake value to trigger hash mismatch
  sed -i 's|npmDepsHash = "sha256-[^"]*"|npmDepsHash = ""|' "$pkg_nix"

  # Build to extract correct npmDepsHash
  log "  Building to obtain npmDepsHash (expected to fail)..."
  local build_output
  build_output=$(nix build "$REPO_ROOT#claude-code" --no-link 2>&1 || true)
  local npm_hash
  npm_hash=$(echo "$build_output" | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' | head -1)

  if [[ -z "$npm_hash" ]]; then
    err "Failed to extract npmDepsHash from build output"
    git -C "$REPO_ROOT" checkout -- claude-code/
    return 1
  fi
  log "  npmDepsHash: $npm_hash"

  # Set correct npmDepsHash
  sed -i "s|npmDepsHash = \"\"|npmDepsHash = \"${npm_hash}\"|" "$pkg_nix"

  # Verify build
  log "  Verifying build..."
  if ! nix build "$REPO_ROOT#claude-code" --no-link --print-out-paths; then
    err "claude-code build failed"
    git -C "$REPO_ROOT" checkout -- claude-code/
    return 1
  fi

  log "  claude-code updated to $latest"
  return 0
}

###############################################################################
# codex (Rust / buildRustPackage)
###############################################################################
update_codex() {
  log "Checking codex..."
  local pkg_nix="$REPO_ROOT/codex/package.nix"

  # Current version
  local current
  current=$(grep -oP 'version = "\K[^"]+' "$pkg_nix" | head -1)
  log "  current version: $current"

  # Latest release tag matching rust-vX.Y.Z (no alpha/beta)
  local latest_tag latest
  latest_tag=$(curl -sf "https://api.github.com/repos/openai/codex/releases?per_page=20" \
    | jq -r '.[].tag_name' | grep '^rust-v[0-9]' | grep -v alpha | grep -v beta | head -1)
  if [[ -z "$latest_tag" ]]; then
    err "Failed to fetch latest codex release tag"
    return 1
  fi
  latest="${latest_tag#rust-v}"
  log "  latest  version: $latest"

  if [[ "$current" == "$latest" ]]; then
    log "  codex is already up to date"
    return 0
  fi

  log "  Updating codex $current -> $latest"

  # Prefetch source hash
  local raw_hash sri_hash
  raw_hash=$(nix-prefetch-url --unpack \
    "https://github.com/openai/codex/archive/refs/tags/rust-v${latest}.tar.gz" \
    --type sha256 2>/dev/null)
  sri_hash=$(nix hash to-sri --type sha256 "$raw_hash")
  log "  source hash: $sri_hash"

  # Download and extract Cargo.lock to parse git dependencies
  local tmpdir
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" RETURN
  curl -sL "https://github.com/openai/codex/archive/refs/tags/rust-v${latest}.tar.gz" \
    | tar xz -C "$tmpdir"
  local cargo_lock="$tmpdir/codex-rust-v${latest}/codex-rs/Cargo.lock"
  if [[ ! -f "$cargo_lock" ]]; then
    err "Cargo.lock not found in source"
    return 1
  fi

  # Parse git dependencies from Cargo.lock
  log "  Parsing git dependencies from Cargo.lock..."
  local git_deps
  git_deps=$(awk '
    /^\[\[package\]\]/ { name=""; ver="" }
    /^name = / { gsub(/"/, "", $3); name=$3 }
    /^version = / { gsub(/"/, "", $3); ver=$3 }
    /^source = "git\+/ {
      src=$0; gsub(/.*git\+/, "", src); gsub(/".*/, "", src)
      url=src; rev=src; sub(/[?#].*/, "", url); sub(/.*#/, "", rev)
      print name, ver, url, rev
    }
  ' "$cargo_lock")

  # Build outputHashes block
  local output_hashes_body=""
  if [[ -n "$git_deps" ]]; then
    while IFS=' ' read -r dep_name dep_ver dep_url dep_rev; do
      log "  Prefetching git dep: $dep_name-$dep_ver ($dep_rev)"
      local dep_raw_hash dep_sri_hash
      dep_raw_hash=$(nix shell nixpkgs#nix-prefetch-git nixpkgs#jq -c \
        "nix-prefetch-git --quiet --rev '$dep_rev' '$dep_url'" 2>/dev/null \
        | jq -r '.sha256')
      dep_sri_hash=$(nix hash to-sri --type sha256 "$dep_raw_hash")
      output_hashes_body+="      \"${dep_name}-${dep_ver}\" = \"${dep_sri_hash}\";"$'\n'
    done <<< "$git_deps"
  fi

  # Update version in package.nix
  sed -i "s/version = \"[^\"]*\"/version = \"${latest}\"/" "$pkg_nix"

  # Replace only the FIRST hash = "sha256-..." (the fetchFromGitHub source hash)
  awk -v new="$sri_hash" '
    !done && /hash = "sha256-/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" new "\""); done=1 }
    { print }
  ' "$pkg_nix" > "$pkg_nix.tmp" && mv "$pkg_nix.tmp" "$pkg_nix"

  # Replace outputHashes block
  local new_block
  new_block="    outputHashes = {"$'\n'"${output_hashes_body}    };"
  awk -v block="$new_block" '
    /outputHashes = \{/ { print block; skip=1; next }
    skip && /};/ { skip=0; next }
    !skip { print }
  ' "$pkg_nix" > "$pkg_nix.tmp" && mv "$pkg_nix.tmp" "$pkg_nix"

  # Verify build
  log "  Verifying build..."
  if ! nix build "$REPO_ROOT#codex" --no-link --print-out-paths; then
    err "codex build failed"
    git -C "$REPO_ROOT" checkout -- codex/
    return 1
  fi

  log "  codex updated to $latest"
  return 0
}

###############################################################################
# Main
###############################################################################
main() {
  log "Starting package updates..."
  local failed=0

  update_claude_code || { err "claude-code update failed"; failed=1; }
  update_codex       || { err "codex update failed"; failed=1; }

  if [[ $failed -ne 0 ]]; then
    log "Some packages failed to update"
    exit 1
  fi

  log "All package updates completed"
}

main "$@"
