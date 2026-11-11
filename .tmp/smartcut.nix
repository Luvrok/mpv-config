let
  pkgs = import <nixpkgs> { };
  av16 = pkgs.python3Packages.av.overridePythonAttrs (old: {
    version = "16.0.1";
    src = pkgs.fetchFromGitHub {
      owner = "PyAV-Org";
      repo = "PyAV";
      tag = "v16.0.1";
      hash = "sha256-iFKDDOJzCynaqwHIjykfh82diGiuOjWytwU3dq1J9PA=";
    };
    buildInputs = [ pkgs.ffmpeg_7-headless ];
    doCheck = false;
    preCheck = "";
  });
in
pkgs.python3Packages.buildPythonApplication {
  pname = "smartcut";
  version = "1.7";
  pyproject = true;
  src = /home/barnard/HOME/projects/smartcut;
  build-system = [ pkgs.python3Packages.setuptools ];
  dependencies = with pkgs.python3Packages; [ av16 tqdm numpy ];
  doCheck = false;
}
