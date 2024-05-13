{ lib
, buildPythonPackage
, pythonOlder
, fetchPypi
# from setup.py
, tqdm
, rotary-embedding-torch
, inflect
, progressbar
, einops
, unidecode
, scipy
, librosa
, transformers
, tokenizers
# from requirements.txt
, torchaudio
}:

buildPythonPackage rec {
  pname = "tortoise-tts";
  version = "3.0.0";

  disabled = pythonOlder "3.9";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-hoSqwjl2/6mBOk7AdLa/8KNIzoKhkjSD5X1dTifdIdY=";
  };

  postPatch = ''
    substituteInPlace setup.cfg --replace description-file description_file

    substituteInPlace setup.py --replace transformers==4.31.0 transformers
  '';

  propagatedBuildInputs = [
    tqdm
    rotary-embedding-torch
    inflect
    progressbar
    einops
    unidecode
    scipy
    librosa
    transformers
    tokenizers

    torchaudio
  ];

  doCheck = false;

  meta = with lib; {
    description = "A high quality multi-voice text-to-speech library";
    homepage = "https://github.com/neonbjb/tortoise-tts";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
