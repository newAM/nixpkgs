{ lib
, buildPythonPackage
, fetchFromGitHub
, GitPython
, fasteners
, lazy
, pyxdg
, pyyaml
, requests
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "msm";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "mycroft-skills-manager";
    rev = "release/v${version}";
    sha256 = "0n2x3qkzbgk6ycgj5fl3f99dyvk33c85mnjlxbl0p8djrqkwg78l";
  };

  prePatch = ''
    substituteInPlace requirements/requirements.txt --replace "pako" ""
    substituteInPlace msm/skill_entry.py --replace "from pako import PakoManager" ""
  '';

  propagatedBuildInputs = [
    GitPython
    fasteners
    lazy
    pyxdg
    pyyaml
    requests
  ];

  checkInputs = [ pytestCheckHook ];

  preCheck = "HOME=$(mktemp -d)";

  # requires network access
  disabledTests = [
    "TestSkillRepo"
    "TestMain"
  ];

  pythonImportsCheck = [ "msm" ];

  meta = with lib; {
    description = "Mycroft Skills Manager";
    homepage = "https://github.com/MycroftAI/mycroft-skills-manager";
    changelog = "https://github.com/MycroftAI/mycroft-skills-manager/releases";
    license = licenses.asl20;
    maintainers = with maintainers; [ newam ];
  };
}
