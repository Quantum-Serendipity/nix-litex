pkgMeta:
{ buildPythonPackage }:

buildPythonPackage rec {
  pname = "pythondata-cpu-vexiiriscv";
  version = pkgMeta.git_revision;
  format = "setuptools";

  src = builtins.fetchGit {
    url = "https://github.com/${pkgMeta.github_user}/${pkgMeta.github_repo}";
    ref = "refs/heads/${pkgMeta.git_branch}";
    rev = pkgMeta.git_revision;
  };

  doCheck = false;
}
