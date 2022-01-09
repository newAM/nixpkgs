{ lib
, buildPythonPackage
, fetchFromGitHub
, swig
, pkgs
, libpulseaudio
, alsa-lib
}:

buildPythonPackage rec {
  pname = "pocketsphinx";
  version = "0.1.15";

  src = fetchFromGitHub {
    owner = "bambocher";
    repo = "pocketsphinx-python";
    rev = "v${version}";
    sha256 = "18i1jw9138ldxigfcjz6rk9z2c2wc2ng2zdnkzippv45d5izkdz8";
    fetchSubmodules = true;
  };

  nativeBuildInputs = [ swig ];

  propagatedBuildInputs = [
    pkgs.pocketsphinx
    libpulseaudio
    alsa-lib
  ];

  pythonImportsCheck = [ pname ];

  meta = with lib; {
    description = "Python interface to CMU Sphinxbase and Pocketsphinx libraries";
    homepage = "https://github.com/bambocher/pocketsphinx-python";
    license = licenses.bsd2;
    maintainers = with maintainers; [ newam ];
  };
}
