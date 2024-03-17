import ./make-test-python.nix ({ pkgs, lib, ... }: {
  name = "llama-cpp";
  meta = with lib; {
    maintainers = with maintainers; [ newam ];
  };

  nodes.machine = { pkgs, ... }: {
    services.llama-cpp = {
      enable = true;
      # create a dummy GGUF file for testing
      # https://github.com/ggerganov/llama.cpp/discussions/5038#discussioncomment-8181056
      model = pkgs.stdenvNoCC.mkDerivation {
        name = "dummy.gguf";

        nativeBuildInputs = [ pkgs.llama-cpp ];

        buildPhase = "gguf $out w";

        dontUnpack = true;
        dontInstall = true;
        dontFixup = true;
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("llama-cpp.service")
    machine.wait_for_open_port(8080)
    machine.succeed("curl -L http://localhost:8080")
  '';
})
