{ lib
, buildPythonPackage
, fetchFromGitHub
, swig
, pkgs
}:

buildPythonPackage rec {
  pname = "fann2";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "FutureLinkCorporation";
    repo = "fann2";
    rev = version;
    sha256 = "131h5948bsghqn1d4qhhiyg434q4kn6s091zh9vimkywgnxh911z";
  };

  prePatch = ''
    substituteInPlace setup.py --replace "    find_fann()" ""
  '';

  nativeBuildInputs = [ swig ];

  propagatedBuildInputs = [ pkgs.libfann ];

  pythonImportsCheck = [ pname ];

  meta = with lib; {
    description = "Python bindings for Fast Artificial Neural Networks";
    homepage = "https://github.com/FutureLinkCorporation/fann2";
    changelog = "https://github.com/FutureLinkCorporation/fann2/blob/${version}/ChangeLog";
    license = licenses.gpl2;
    maintainers = with maintainers; [ newam ];
  };
}
