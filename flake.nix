{
  description = "Literature search and paper analysis for an agent: the papers skill and a packaged paper-search-mcp";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = paper-search-mcp;
        paper-search-mcp = pkgs.callPackage ./nix/package.nix { };
      });

      homeModules.default = import ./nix/home-module.nix { inherit self; };
      # homeModules is the name the flake schema knows; homeManagerModules is what most
      # consumers still write, so both point at the same module
      homeManagerModules.default = self.homeModules.default;

      # For a consumer who reaches for pkgs rather than this flake's packages directly
      overlays.default = final: _prev: {
        inherit (self.packages.${final.stdenv.hostPlatform.system}) paper-search-mcp;
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
            self.packages.${pkgs.stdenv.hostPlatform.system}.paper-search-mcp
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
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
