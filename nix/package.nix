{
  lib,
  python3Packages,
  fetchPypi,
  fetchpatch,
}:

# The server imports the SDK 1 FastMCP module, which SDK 2 removes
let
  mcp = python3Packages.mcp_1 or python3Packages.mcp;
in
python3Packages.buildPythonApplication rec {
  pname = "paper-search-mcp";
  version = "0.1.4";
  pyproject = true;

  src = fetchPypi {
    pname = "paper_search_mcp";
    inherit version;
    hash = "sha256-NQGmJYQMqzQQ6ZDi8t9RvULKcwCHJFi/1Ev2vx8RiPg=";
  };

  # A stopgap until a release carries it; see WORKAROUNDS.md for what it fixes and when it goes
  patches = [
    (fetchpatch {
      url = "https://github.com/openags/paper-search-mcp/commit/f298a3c679d34d498f3cd6c567cc9b3202c28ef4.patch";
      includes = [ "paper_search_mcp/*" ];
      hash = "sha256-WAe058TzuaVWrf/QAb3yZDorpVOHgNuT2jt2ZkontSI=";
    })
  ];

  build-system = [ python3Packages.hatchling ];

  # The server imports FastMCP from the SDK, not from the separate fastmcp distribution
  pythonRemoveDeps = [ "fastmcp" ];

  dependencies =
    with python3Packages;
    [
      beautifulsoup4
      feedparser
      httpx
      lxml
      mcp
      pypdf
      requests
      socksio
    ]
    ++ (mcp.optional-dependencies.cli or [ ]);

  # The suite talks to the live services; a build must not depend on their availability
  doCheck = false;

  pythonImportsCheck = [
    "paper_search_mcp"
    "paper_search_mcp.cli"
    "paper_search_mcp.server"
  ];

  meta = {
    description = "Search, download and read academic papers from 20+ sources, as an MCP server and a CLI";
    homepage = "https://github.com/openags/paper-search-mcp";
    license = lib.licenses.mit;
    mainProgram = "paper-search";
    platforms = lib.platforms.all;
  };
}
