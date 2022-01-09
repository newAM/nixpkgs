{ lib
, buildPythonPackage
, fetchFromGitHub
, six
, pytest
}:

buildPythonPackage rec {
  pname = "adapt-parser";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "adapt";
    rev = "release/v${version}";
    sha256 = "16wasl59ai7szcf1czi19i958sy6qncjjc4cmj9p6zz0r22xa46l";
  };

  propagatedBuildInputs = [ six ];

  checkInputs = [ pytest ];

  checkPhase = "pytest test/*";

  pythonImportsCheck = [ "adapt" ];

  meta = with lib; {
    description = "Adapt Intent Parser";
    homepage = "https://github.com/MycroftAI/adapt";
    changelog = "https://github.com/MycroftAI/adapt/releases";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
