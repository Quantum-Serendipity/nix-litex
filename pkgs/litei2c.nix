pkgMeta:
{ lib
, buildPythonPackage
, litex
, migen
}:

buildPythonPackage rec {
  pname = "litei2c";
  version = pkgMeta.git_revision;

  src = builtins.fetchGit {
    url = "https://github.com/${pkgMeta.github_user}/${pkgMeta.github_repo}";
    ref = "refs/heads/${pkgMeta.git_branch}";
    rev = pkgMeta.git_revision;
  };

  # Upstream is missing __init__.py in core/ and phy/ subdirectories,
  # so setuptools' find_packages() skips them.
  postPatch = ''
    touch litei2c/core/__init__.py
    touch litei2c/phy/__init__.py
  '';

  buildInputs = [
    litex
    migen
  ];

  doCheck = true;
}
