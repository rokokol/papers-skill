{
  lib,
  python3Packages,
  fetchPypi,
  fetchpatch,
}:

# paper-search-mcp from its PyPI release, built against nixpkgs' mcp 1.x. Upstream leaves
# the mcp dependency unbounded and imports the 1.x FastMCP module, so a resolver that picks
# mcp 2.x breaks the server at import time; nixpkgs pins the SDK, so the pin is the lock,
# not a constraint file. The fastmcp requirement is dropped: nothing in the package imports
# it, only the metadata names it
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
