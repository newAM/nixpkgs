{ lib
, stdenv
, buildFHSUserEnv
, fetchurl
, sd
, busybox
, bash
, gzip
, dbus
, libuuid
}:

stdenv.mkDerivation rec {
  pname = "fvp";
  version = "11.15.24";

  src = fetchurl {
    url = "https://developer.arm.com/-/media/Arm%20Developer%20Community/Downloads/OSS/FVP/Corstone-300/FVP_Corstone_SSE-300_11.15_24.tgz";
    sha256 = "1lz9hnxkpvv49kv92df66cmsylyh5rgbmwwf30h372fb510c6dlb";
  };

  unpackPhase = ''
    tar xzf $src
  '';

  # installer relies upon the exact position of bytes within the shell script
  # skip patching to preserve the shell script
  dontPatch = true;

  # allows executing the installer shell script without modifying paths
  installEnv = buildFHSUserEnv {
    name = "${pname}-installEnv";
    targetPkgs = pkgs: (with pkgs;
    [
      gzip
      busybox
    ]);
    runScript = ''
      ./FVP_Corstone_SSE-300.sh \
        --i-agree-to-the-contained-eula \
        --nointeractive \
        --tar ${busybox}/bin/tar \
        --gunzip ${gzip}/bin/gunzip \
        --show-files \
        --destination $out \
        -v -v -v -v -v
    '';
  };

  installPhase = ''
    ${installEnv}/bin/${installEnv.name}
    # disable analytics
    # rm $out/models/Linux64_GCC-6.4/libarmfastmodelsanalytics.1.1.1.so
  '';

  preFixup = let
    libPath = lib.makeLibraryPath [
      stdenv.cc.cc.lib  # libstdc++.so.6
      libuuid  # libuuid.so.1
    ];
  in ''
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/FVP_Corstone_SSE-300_Ethos-U55
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/FVP_Corstone_SSE-300_Ethos-U65
    patchelf \
      --add-needed "${dbus.lib}/lib/libdbus-1.so.3" \
      $out/models/Linux64_GCC-6.4/libSDL2-2.0.so.0.10.0
    patchelf \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/libMAXCOREInitSimulationEngine.3.so
    patchelf \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/libarmctmodel.so
    patchelf \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/libethosu.so
    patchelf \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/librui_5.2.0.x64.so
    patchelf \
      --set-rpath "${libPath}" \
      $out/models/Linux64_GCC-6.4/libarmfastmodelsanalytics.1.1.1.so
  '';

  # LD_LIBRARY_PATH="/nix/store/50msfhkz5wbyk8i78pjv3y9lxdrp7dlm-gcc-10.3.0-lib/lib:/home/alex/git/nixpkgs/result/models/Linux64_GCC-6.4:$LD_LIBRARY_PATH" ./result/models/Linux64_GCC-6.4/FVP_Corstone_SSE-300_Ethos-U55

  meta = with lib; {
    description = "ARM ecosystem fixed virtual platforms";
    homepage = "https://developer.arm.com/tools-and-software/open-source-software/arm-platforms-software/arm-ecosystem-fvps";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ newam ];
  };
}
