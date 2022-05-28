{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, copyDesktopItems
, dpkg
, makeWrapper
, alsa-lib
, cairo
, cups
, gtk3
, libdrm
, libX11
, mesa
, nspr
, nss
, pango
, xorg
, zlib
}:

# run with:
# result/opt/Beam\ Studio/beam-studio --no-sandbox
stdenv.mkDerivation rec {
  pname = "beam-studio";
  version = "1.8.3";

  src = fetchurl {
    url = "https://beamstudio.s3-ap-northeast-1.amazonaws.com/linux-18.04/beam-studio_${version}_amd64.deb";
    sha256 = "sha256-30B2VoaLQUs14tkCrTkVI622yph7q+mBQ1kuyDi3Mqs=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    cairo
    cups
    gtk3
    libdrm
    libX11
    mesa
    nspr
    nss
    pango
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXrandr
    zlib
  ];

  dontBuild = true;
  dontConfigure = true;

  unpackPhase = ''
    dpkg-deb -x ${src} ./
  '';

  patchPhase = ''
    substituteInPlace usr/share/applications/beam-studio.desktop \
      --replace "/opt/Beam Studio/beam-studio" "$out/opt/Beam Studio/beam-studio"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt
    mv opt $out

    runHook postInstall
  '';

  postInstall = ''
    wrapProgram "$out/opt/Beam Studio/beam-studio" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath buildInputs}
  '';

  meta = with lib; {
    description = "Laser engraving for the beamo";
    homepage = "https://flux3dp.com";
    changelog = "https://support.flux3dp.com/hc/en-us/sections/360000421876-I-Beam-Studio";
    license = licenses.unfree;
    maintainers = with maintainers; [ newam ];
    platforms = [ "x86_64-linux" ];
  };
}
