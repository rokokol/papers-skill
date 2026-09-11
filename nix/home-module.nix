{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

# Home Manager module: puts paper-search and paper-search-mcp on the user's PATH and, when
# asked, points them at an env file with the API keys. The keys themselves never enter the
# module: the file is produced by whatever secret store the consumer runs. The corpus block
# adds PaperQA2 with a settings preset for local models, which is what the skill's corpus
# mode runs
let
  cfg = config.programs.papers;
  flakePackages = self.packages.${pkgs.stdenv.hostPlatform.system};

  # One litellm route for a local OpenAI-compatible or Ollama model: the same shape PaperQA2's
  # README uses for a locally hosted LLM, keyed by the model name so every stage that names
  # the model resolves to this route
  route = model: {
    model_list = [
      {
        model_name = model;
        litellm_params = {
          inherit model;
          api_base = cfg.corpus.ollamaUrl;
          # litellm's default of 60 s is shorter than Ollama loading a 9B model into the
          # GPU on the first call, and that first call fails the whole index
          timeout = cfg.corpus.timeout;
          # A reasoning model spends its budget thinking and returns the summary empty;
          # Ollama's think switch turns that off for models that have it
          think = cfg.corpus.thinking;
        };
      }
    ];
  };

  settings = {
    llm = cfg.corpus.llm;
    llm_config = route cfg.corpus.llm;
    summary_llm = cfg.corpus.llm;
    summary_llm_config = route cfg.corpus.llm;
    embedding = cfg.corpus.embedding;
    embedding_config = {
      kwargs.api_base = cfg.corpus.ollamaUrl;
    };
    # The JSON summary prompt asks a small model for a score inside JSON, and it returns the
    # summary with the score missing; the text prompt is parsed by regex and survives that
    prompts.use_json = cfg.corpus.jsonPrompts;
    answer = {
      max_concurrent_requests = cfg.corpus.concurrency;
      evidence_k = cfg.corpus.evidenceK;
      answer_max_sources = cfg.corpus.answerMaxSources;
    };
    # PaperQA2's MultimodalOptions is an IntEnum: 0 is text only, 1 parses media and asks the
    # model for a caption of every figure and table, which on a local model turns one paper
    # into minutes of GPU time. The enrichment model is also what index time reaches for, so
    # it is routed too: left at its default it is an OpenAI model and fails without a key
    parsing = {
      multimodal = if cfg.corpus.multimodal then 1 else 0;
      # Doc details are one more model call per paper for a structured citation, then
      # Semantic Scholar and Crossref for its metadata; an anonymous Semantic Scholar 429
      # there ended the whole index with exit 1, and retrieval needs none of it
      use_doc_details = cfg.corpus.docDetails;
      enrichment_llm = cfg.corpus.llm;
      enrichment_llm_config = route cfg.corpus.llm;
    };
    agent = {
      agent_llm = cfg.corpus.llm;
      agent_llm_config = route cfg.corpus.llm;
      search_count = cfg.corpus.searchCount;
      index.paper_directory = cfg.corpus.directory;
    };
  }
  // cfg.corpus.extraSettings;
in
{
  options.programs.papers = {
    enable = lib.mkEnableOption "paper-search-mcp, the paper search server and CLI behind the papers skill";

    package = lib.mkOption {
      type = lib.types.package;
      default = flakePackages.paper-search-mcp;
      defaultText = lib.literalExpression "papers-skill.packages.\${system}.paper-search-mcp";
      description = "The paper-search-mcp package to install";
    };

    envFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/rendered/paper-search.env";
      description = "Path of a KEY=value file with the optional API keys, exported as PAPER_SEARCH_MCP_ENV_FILE so both binaries read it before falling back to ~/.config/paper-search-mcp/.env";
    };

    corpus = {
      enable = lib.mkEnableOption "PaperQA2 with a settings preset for local models, the corpus mode of the papers skill";

      package = lib.mkOption {
        type = lib.types.package;
        default = flakePackages.pqa;
        defaultText = lib.literalExpression "papers-skill.packages.\${system}.pqa";
        description = "What provides the pqa command in the profile; the default is a wrapper over the locked environment, since installing the environment itself collides with any other Python environment in the profile";
      };

      settingsName = lib.mkOption {
        type = lib.types.str;
        default = "papers";
        description = "Name of the settings preset written under PQA_HOME, so the skill runs pqa -s <name>";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        example = "/home/me/.cache/papers";
        description = "Absolute path of the folder of PDFs PaperQA2 indexes; the same folder the skill downloads into keeps one corpus";
      };

      llm = lib.mkOption {
        type = lib.types.str;
        default = "ollama_chat/qwen3.5:9b";
        description = "litellm model name for answering, summarising and the agent. An Ollama model is ollama_chat/<name>: that provider speaks to Ollama's chat endpoint, which carries tool calls; the ollama/ provider speaks to the generate endpoint, which does not, and every PaperQA2 agent ends a turn with a forced tool call";
      };

      thinking = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Let a reasoning model think before answering; off keeps its output to the summary and the answer, which is what PaperQA2 parses";
      };

      jsonPrompts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Ask for the per-passage summaries as JSON; off uses the text prompts, which a small local model fills in reliably";
      };

      evidenceK = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Passages retrieved per question; each one is a summary call to the local model";
      };

      answerMaxSources = lib.mkOption {
        type = lib.types.int;
        default = 3;
        description = "Passages the answer may cite";
      };

      searchCount = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Papers the agent's index search returns per query";
      };

      embedding = lib.mkOption {
        type = lib.types.str;
        default = "ollama/bge-m3";
        description = "litellm embedding model name; bge-m3 is multilingual, nomic-embed-text is smaller and English-only. Embeddings stay on the ollama/ provider, which is the one litellm embeds through";
      };

      ollamaUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:11434";
        description = "Where the Ollama API listens; every route in the preset points at it";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = "Seconds litellm waits for one model call; the first call also loads the model into the GPU";
      };

      concurrency = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "How many model calls PaperQA2 issues at once; Ollama serves one model, so more than a few only queue and time out";
      };

      multimodal = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Parse figures and tables too and have the model caption each one at index time; off keeps indexing to text and seconds per paper";
      };

      docDetails = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Look up each paper's metadata (DOI, venue, citation count) at index time; off keeps indexing off the network and keeps the citation the model reads off the first chunk";
      };

      extraSettings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Attributes merged over the generated PaperQA2 settings, for anything the options above do not name";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
    ]
    ++ lib.optionals cfg.corpus.enable [
      cfg.corpus.package
      flakePackages.pqa-evidence
    ];
    home.sessionVariables = lib.mkIf (cfg.envFile != null) {
      PAPER_SEARCH_MCP_ENV_FILE = cfg.envFile;
    };
    # PQA_HOME defaults to ~/.pqa, and pqa -s NAME reads settings/NAME.json under it
    home.file.".pqa/settings/${cfg.corpus.settingsName}.json" = lib.mkIf cfg.corpus.enable {
      text = builtins.toJSON settings;
    };
  };
}
