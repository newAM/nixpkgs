{ lib
, buildPythonPackage
, fetchFromGitHub
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "padaos";
  version = "0.1.10";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "padaos";
    rev = "v${version}";
    sha256 = "04qgclfsxh5das7qf8dksji9qipz1i9zq7n7dxwqv5i81p19wckz";
  };

  checkInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ pname ];

  meta = with lib; {
    description = "A rigid, lightweight, dead-simple intent parser";
    homepage = "https://github.com/MycroftAI/padaos";
    license = licenses.mit;
    maintainers = with maintainers; [ newam ];
  };
}
