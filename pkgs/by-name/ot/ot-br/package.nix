{ lib
, stdenv
, fetchFromGitHub
, buildNpmPackage
, fetchNpmDeps
, fetchpatch
, cmake
, gitMinimal
, pkg-config
, avahi
, boost
, jsoncpp
, protobuf
}:

let
  # update comments too
  hassAddonsHash = "d8e2216ef532e21948678720140a45a3b4fa6f3f";
in
# TO RUN: https://github.com/home-assistant/addons/blob/d8e2216ef532e21948678720140a45a3b4fa6f3f/openthread_border_router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/run#L120
# backbone will be "br0"
# result/bin/otbr-agent -I $THREAD_NET_IF -B $BACKBONE_NET_IF --rest-listen-address "::" -d7 -v spinel+hdlc+uart:///dev/serial/by-id/usb-Nabu_Casa_SkyConnect_v1.0_3c05fd8faf9ced1181a877faa7669f5d-if00-port0?uart-baudrate=460800 trel://$BACKBONE_NET_IF
stdenv.mkDerivation rec {
  pname = "ot-br";
  version = "unstable-2024-05-28";

  src = fetchFromGitHub {
    owner = "openthread";
    repo = "ot-br-posix";
    # https://github.com/home-assistant/addons/blob/d8e2216ef532e21948678720140a45a3b4fa6f3f/openthread_border_router/build.yaml#L6C17-L6C57
    rev = "2279c02f3c3373f074899fc8d993b8ddb72910a2";
    fetchSubmodules = true;
    hash = "sha256-MsQRue7gg5U0n/nbIYzSMNVB17iIFeGfc3sl6LcKI9U=";
  };

  nodeModules = buildNpmPackage rec {
    inherit pname version src;

    dontNpmBuild = true;

    npmRoot = "src/web/web-service/frontend";

    npmDeps = fetchNpmDeps {
      hash = "sha256-7UVfPICyIbHEClpr3p7eDR46OUzS8mVf6P7phnDpVLk=";
    };

    installPhase = ''
      mkdir -p $out/share/${pname}
      cp -r ${npmRoot}/node_modules/ $out/share/${pname}
    '';
  };

  patches = [
    (fetchpatch rec{
      name = "0001-Avoid-writing-to-system-console.patch";
      url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
      hash = "sha256-oFva9WQi9x3RDnipFx+ACJGD/bdXI0Z+pu3VJr1vTnk=";
    })
    (fetchpatch rec {
      name = "0002-rest-support-deleting-the-dataset.patch";
      url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
      hash = "sha256-f93R6fp/IrltkSmPkEjapkVKedoJrn/NyAoy5SGiDnM=";
    })
    (fetchpatch rec {
      name = "0003-openthread-set-netif-route-metric-lower.patch";
      url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
      hash = "sha256-MvV/NThlQ3NG1ezv9AZ7zW/GjFXPzJykRThZhzlSqcc=";
    })
  ];

  postPatch =
    let
      sumodulePatch = (fetchpatch rec {
        name = "0001-channel-monitor-disable-by-default.patch";
        url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
        hash = "sha256-UFPly7yQPTnMcOx5FJAFXp3rb2IuhsJHK9M1K2Tip8s=";
      });
    in
    ''
      git -C third_party/openthread/repo apply ${sumodulePatch}

      substituteInPlace src/web/CMakeLists.txt \
        --replace-fail "Boost_USE_STATIC_LIBS ON" "Boost_USE_STATIC_LIBS OFF"

      substituteInPlace src/web/web-service/frontend/CMakeLists.txt \
        --replace-fail "npm install" "echo nop"

      substituteInPlace src/web/web-service/frontend/CMakeLists.txt \
        --replace-fail ' ''${CMAKE_CURRENT_BINARY_DIR}' " ${nodeModules}/share/${pname}"
    '';

  nativeBuildInputs = [
    cmake
    gitMinimal
    pkg-config
  ];

  buildInputs = [
    avahi
    boost # web
    jsoncpp # web
    protobuf
  ];

  # https://github.com/home-assistant/addons/blob/d8e2216ef532e21948678720140a45a3b4fa6f3f/openthread_border_router/Dockerfile#L67
  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "OTBR_FEATURE_FLAGS" true)
    (lib.cmakeBool "OTBR_DNSSD_DISCOVERY_PROXY" true)
    (lib.cmakeBool "OTBR_SRP_ADVERTISING_PROXY" true)
    # https://github.com/openthread/ot-br-posix/blob/140247aae3c44cb1f9550cc96e39169c05621034/CMakeLists.txt#L45C56-L45C69
    # (lib.cmakeFeature "OTBR_MDNS" "mDNSResponder")
    (lib.cmakeFeature "OTBR_VERSION" "")
    (lib.cmakeFeature "OT_PACKAGE_VERSION" "")
    (lib.cmakeBool "OTBR_DBUS" false)
    (lib.cmakeBool "OT_POSIX_RCP_BUS_UART" true)
    (lib.cmakeFeature "OT_LINK_RAW" "1")
    (lib.cmakeFeature "OTBR_VENDOR_NAME" "HomeAssistant")
    (lib.cmakeFeature "OTBR_PRODUCT_NAME" "OpenThreadBorderRouter")
    (lib.cmakeBool "OTBR_WEB" true)
    (lib.cmakeBool "OTBR_BORDER_ROUTING" true)
    (lib.cmakeBool "OTBR_REST" true)
    (lib.cmakeBool "OTBR_BACKBONE_ROUTER" true)
    (lib.cmakeBool "OTBR_TREL" true)
    (lib.cmakeBool "OTBR_NAT64" true)
    (lib.cmakeFeature "OT_POSIX_NAT64_CIDR" "192.168.255.0/24")
    (lib.cmakeBool "OTBR_DNS_UPSTREAM_QUERY" true)
    (lib.cmakeBool "OT_CHANNEL_MONITOR" true)
    (lib.cmakeBool "OT_COAP" false)
    (lib.cmakeBool "OT_COAPS" false)
    # misc
    (lib.cmakeFeature "CMAKE_CXX_STANDARD" "17")
  ];

  meta = with lib; {
    homepage = "https://openthread.io";
    license = licenses.bsd3;
    description = "OpenThread Border Router";
    maintainers = with maintainers; [ newam ];
  };
}
