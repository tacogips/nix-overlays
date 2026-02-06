{
  description = "nix overlays";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      outputs = flake-utils.lib.eachSystem systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          packages = {
            claude-code = pkgs.callPackage ./claude-code/package.nix { };
            codex = pkgs.callPackage ./codex/package.nix { };
          };

          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              go-task
              nix-prefetch-git
              jq
              curl
            ];
          };

          # nix fmt
          formatter = pkgs.nixfmt-rfc-style;
        }
      );
    in
    outputs
    // {
      overlays = {
        claude-code = final: prev: {
          claude-code = final.callPackage ./claude-code/package.nix { };
        };
        codex = final: prev: {
          codex = final.callPackage ./codex/package.nix { };
        };
      };
    };
}
