{ lib
, buildPythonPackage
, pythonOlder
, fetchFromGitHub
, pyee
, websocket-client
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "mycroft-messagebus-client";
  version = "0.9.5";

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "mycroft-messagebus-client";
    rev = "release/v${version}";
    sha256 = "0mly17k56dbvrns1vjixh7sw5sn9mvnzrbgxicjy7p919lvx9zr1";
  };

  prePatch = ''
    substituteInPlace requirements.txt --replace "pyee==" "pyee>="
  '';

  propagatedBuildInputs = [
    pyee
    websocket-client
  ];

  checkInputs = [ pytestCheckHook ];

  pythonImportsCheck = [ "mycroft_bus_client" ];

  meta = with lib; {
    description = "Python module for connecting to the mycroft messagebus";
    homepage = "https://github.com/MycroftAI/mycroft-messagebus-client";
    changelog = "https://github.com/MycroftAI/mycroft-messagebus-client/releases";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
