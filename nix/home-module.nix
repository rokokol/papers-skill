{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

# Home Manager module: puts paper-search and paper-search-mcp on the user's PATH and, when
# asked, points them at an env file with the API keys. The keys themselves never enter the
# module: the file is produced by whatever secret store the consumer runs
let
  cfg = config.programs.papers;
in
{
  options.programs.papers = {
    enable = lib.mkEnableOption "paper-search-mcp, the paper search server and CLI behind the papers skill";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.paper-search-mcp;
      defaultText = lib.literalExpression "papers-skill.packages.\${system}.paper-search-mcp";
      description = "The paper-search-mcp package to install";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/rendered/paper-search.env";
      description = "Path of a KEY=value file with the optional API keys, exported as PAPER_SEARCH_MCP_ENV_FILE so both binaries read it before falling back to ~/.config/paper-search-mcp/.env";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
    home.sessionVariables = lib.mkIf (cfg.envFile != null) {
      PAPER_SEARCH_MCP_ENV_FILE = cfg.envFile;
    };
  };
}
