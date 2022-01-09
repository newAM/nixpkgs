{ lib
, buildPythonPackage
, fetchFromGitHub
, fann2
, xxhash
, padaos
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "padatious";
  version = "0.4.8";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "padatious";
    rev = "v${version}";
    sha256 = "0267kngyb31gnwm4psldy21ccc006k4li2g4g7zwza6j419zzyfn";
  };

  propagatedBuildInputs = [
    fann2
    xxhash
    padaos
  ];

  checkInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ pname ];

  meta = with lib; {
    description = "A neural network intent parser";
    homepage = "https://github.com/MycroftAI/padatious";
    changelog = "https://github.com/MycroftAI/padatious/releases";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
