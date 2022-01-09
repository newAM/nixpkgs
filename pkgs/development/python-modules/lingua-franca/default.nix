{ lib
, buildPythonPackage
, fetchFromGitHub
, python-dateutil
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "lingua-franca";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "lingua-franca";
    rev = "release/v${version}";
    sha256 = "1wx1c8a2k9155z74113yn1xcs6y0zljbgan2pbbmzsvki8m0z6jn";
  };

  prePatch = ''
    substituteInPlace requirements.txt --replace "==" ">="
  '';

  propagatedBuildInputs = [ python-dateutil ];

  checkInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "lingua_franca" ];

  meta = with lib; {
    description = "Mycroft's multilingual text parsing and formatting library";
    homepage = "https://github.com/MycroftAI/lingua-franca";
    changelog = "https://github.com/MycroftAI/lingua-franca/releases";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
