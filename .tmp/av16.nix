let
  pkgs = import <nixpkgs> { };
in
pkgs.python3Packages.av.overridePythonAttrs (old: {
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
})
