{
  description = "nix overlays";
  inputs = {
    nixpkgs.url = "github:tacogips/nixpkgs-security/d2a93d2fe7820d90eaa10af53891412ec3614f56";
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
            # zededitor = pkgs.callPackage ./zededitor/package.nix { };
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
          formatter = pkgs.nixfmt;
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
        # zededitor = final: prev: {
        #   zededitor = final.callPackage ./zededitor/package.nix { };
        # };
      };
    };
}
