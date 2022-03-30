{ lib
, rustPlatform
, fetchFromGitHub
}:

rustPlatform.buildRustPackage rec {
  pname = "helix";
  version = "22.03";

  src = fetchFromGitHub {
    owner = "helix-editor";
    repo = pname;
    rev = version;
    sha256 = "sha256-anUYKgr61QQmdraSYpvFY/2sG5hkN3a2MwplNZMEyfI=";
  };

  cargoSha256 = "sha256-zJQ+KvO+6iUIb0eJ+LnMbitxaqTxfqgu7XXj3j0GiX4=";

  HELIX_DISABLE_AUTO_GRAMMAR_BUILD = "";

  meta = with lib; {
    description = "A post-modern modal text editor";
    homepage = "https://helix-editor.com";
    license = licenses.mpl20;
    mainProgram = "hx";
    maintainers = with maintainers; [ yusdacra ];
  };
}
