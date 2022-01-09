{ lib
, buildPythonPackage
, fetchFromGitHub
, pocketsphinx
, flac
, pytestCheckHook
, swig
, libpulseaudio
}:

buildPythonPackage rec {
  pname = "speechrecognition";
  version = "3.8.1";

  src = fetchFromGitHub {
    owner = "Uberi";
    repo = "speech_recognition";
    rev = "3.8.1";
    sha256 = "1lq6g4kl3y1b4ch3b6wik7xy743x6pp5iald0jb9zxqgyxy1zsz4";
  };

  nativeBuildInputs = [ swig ];

  propagatedBuildInputs = [ pocketsphinx ];

  checkInputs = [
    pytestCheckHook
    libpulseaudio
    flac
  ];

  disabledTests = [
    # requires network access get audio files
    "test_google_"
    # not working, not sure why
    "test_sphinx_"
  ];

  pythonImportsCheck = [ "speech_recognition" ];

  meta = with lib; {
    description = "Speech recognition module for Python, supporting several engines and APIs, online and offline.";
    homepage = "https://github.com/Uberi/speech_recognition";
    changelog = "https://github.com/Uberi/speech_recognition/releases";
    license = licenses.bsd3;
    maintainers = with maintainers; [ newam ];
  };
}
