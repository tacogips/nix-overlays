# Packaged Codex TLS security update

Codex 0.116.0 embeds its own Rust trust data. The adjacent Cargo.lock updates
rustls-webpki to 0.103.16 and both webpki-roots / webpki-root-certs to 1.0.11.
The 0.26.11 compatibility package reexports the updated 1.x store.
The required AWS-LC patch resolution and source workspace version normalization
are retained from Cargo; git dependency revisions and Nix output hashes are unchanged.
Both Nix vendoring and the source build consume the same lockfile.

This Nix package builds with Cargo; the upstream Bazel lock is unused.
Rebuild and redeploy installed Codex packages to incorporate this update.
