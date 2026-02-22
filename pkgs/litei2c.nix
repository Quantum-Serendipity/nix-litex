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

  buildInputs = [
    litex
    migen
  ];

  doCheck = true;
}
