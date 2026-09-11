{
  description = "Literature search and paper analysis for an agent: the papers skill, a packaged paper-search-mcp and a locked PaperQA2";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # PaperQA2 is not in nixpkgs and pins litellm below what nixpkgs carries, so it comes as
    # the whole tree uv resolved in nix/paperqa/uv.lock, built by uv2nix from wheels
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The PaperQA2 environment: nix/paperqa/pyproject.toml names paper-qa, uv.lock names
      # everything it resolved to, and the lock is what a rebuild reproduces
      paperqaWorkspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./nix/paperqa; };
      paperqaOverlay = paperqaWorkspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
      paperqaEnv =
        pkgs:
        let
          pythonSet =
            (pkgs.callPackage pyproject-nix.build.packages {
              # The lock was resolved for 3.13; the wheels it names are that interpreter's
              python = pkgs.python313;
            }).overrideScope
              (
                lib.composeManyExtensions [
                  pyproject-build-systems.overlays.wheel
                  paperqaOverlay
                ]
              );
        in
        pythonSet.mkVirtualEnv "paper-qa-env" paperqaWorkspace.deps.default;
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = paper-search-mcp;
        paper-search-mcp = pkgs.callPackage ./nix/package.nix { };
        paper-qa = paperqaEnv pkgs;
        # The command alone, for a profile: the environment carries a whole site-packages,
        # and two Python environments in one Home Manager profile collide on any file they
        # share, so what a profile installs is this wrapper rather than the environment
        pqa = pkgs.writeShellScriptBin "pqa" ''
          exec ${paper-qa}/bin/pqa "$@"
        '';
        # Retrieval without the answer model: the passages PaperQA2 would summarise, printed
        # as they are, run by the environment's own interpreter so it sees the same lock
        pqa-evidence = pkgs.writeShellScriptBin "pqa-evidence" ''
          exec ${paper-qa}/bin/python ${./tools/evidence.py} "$@"
        '';
      });

      homeModules.default = import ./nix/home-module.nix { inherit self; };
      # homeModules is the name the flake schema knows; homeManagerModules is what most
      # consumers still write, so both point at the same module
      homeManagerModules.default = self.homeModules.default;

      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system})
          paper-search-mcp
          paper-qa
          pqa
          pqa-evidence
          ;
      };

      # The pinned toolbox for check.sh, locally and in CI. A check whose tools come from
      # the registry changes behaviour with zero change in the repository
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            actionlint
            shellcheck
            shfmt
            jq
            git
            python3
            uv
            self.packages.${pkgs.stdenv.hostPlatform.system}.paper-search-mcp
            self.packages.${pkgs.stdenv.hostPlatform.system}.paper-qa
            self.packages.${pkgs.stdenv.hostPlatform.system}.pqa-evidence
          ];
        };
      });

      checks = forAllSystems (pkgs: {
        # The package builds and both entry points answer offline: `sources` lists the
        # connectors without a request, and the server's --help imports the 1.x FastMCP
        # module that mcp 2.x removed, which is the failure this package exists to avoid
        paper-search-mcp =
          pkgs.runCommand "paper-search-mcp-smoke"
            {
              nativeBuildInputs = [
                self.packages.${pkgs.stdenv.hostPlatform.system}.paper-search-mcp
                pkgs.jq
              ];
            }
            ''
              paper-search sources 2>/dev/null | tee sources.json
              jq -e '.sources | index("arxiv") != null and index("semantic") != null' sources.json >/dev/null ||
                { echo 'arxiv or semantic is missing from the source list' >&2; exit 1; }
              paper-search-mcp --help >/dev/null
              touch $out
            '';

        # The locked PaperQA2 environment imports and its CLI answers offline
        paper-qa =
          pkgs.runCommand "paper-qa-smoke"
            {
              nativeBuildInputs = [ self.packages.${pkgs.stdenv.hostPlatform.system}.paper-qa ];
            }
            ''
              export HOME=$TMPDIR
              pqa --help >/dev/null
              python -c 'import paperqa; print(paperqa.__version__)' | tee version.txt
              grep -q '^2026\.8\.12$' version.txt || { echo 'paper-qa is not the locked 2026.8.12' >&2; exit 1; }
              ${self.packages.${pkgs.stdenv.hostPlatform.system}.pqa-evidence}/bin/pqa-evidence --help >/dev/null
              touch $out
            '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
