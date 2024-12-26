{
  lib,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  fetchpatch,
  cmake,
  gitMinimal,
  pkg-config,
  avahi,
  protobuf,
  boost,
  jsoncpp,
  withWeb ? true,
}:

let
  # update comments too
  hassAddonsHash = "91160e1b5d00e13091b0537d85a3b3112e4a3f60";
in
# TO RUN: https://github.com/home-assistant/addons/blob/91160e1b5d00e13091b0537d85a3b3112e4a3f60/openthread_border_router/rootfs/etc/s6-overlay/s6-rc.d/otbr-agent/run#L120
# backbone will be "br0"
# sudo result/bin/otbr-agent -I wpan0 -B br0 --rest-listen-address "::" -d7 -v 'spinel+hdlc+uart:///dev/serial/by-id/usb-Nabu_Casa_SkyConnect_v1.0_3c05fd8faf9ced1181a877faa7669f5d-if00-port0?uart-baudrate=460800' trel://br0
stdenv.mkDerivation rec {
  pname = "ot-br";
  version = "unstable-2024-12-22";

  src = fetchFromGitHub {
    owner = "openthread";
    repo = "ot-br-posix";
    # https://github.com/home-assistant/addons/blob/91160e1b5d00e13091b0537d85a3b3112e4a3f60/openthread_border_router/build.yaml#L6C17-L6C57
    rev = "b041fa52daaa4dfbf6aa4665d8925c1be0350ca5";
    fetchSubmodules = true;
    hash = "sha256-SVl7AKds7bPRRg6J5pLm6BBiM/vQOQ2+zBkdP7+sMSs=";
  };

  patches = [
    (fetchpatch rec {
      name = "0001-support-deleting-the-dataset.patch";
      url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
      hash = "sha256-f93R6fp/IrltkSmPkEjapkVKedoJrn/NyAoy5SGiDnM=";
    })
    (fetchpatch rec {
      name = "0002-set-netif-route-metric-lower.patch";
      url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
      hash = "sha256-d0901FWZhkOduG5oUU/LfcudCVpW8Mpgn6GG/90DURk=";
    })
  ];

  postPatch =
    let
      sumodulePatch = (
        fetchpatch rec {
          name = "0001-channel-monitor-disable-by-default.patch";
          url = "https://raw.githubusercontent.com/home-assistant/addons/${hassAddonsHash}/openthread_border_router/${name}";
          hash = "sha256-UFPly7yQPTnMcOx5FJAFXp3rb2IuhsJHK9M1K2Tip8s=";
        }
      );

      nodeModules = buildNpmPackage {
        inherit pname version;

        src = "${src}/src/web/web-service/frontend";

        dontNpmBuild = true;

        npmDepsHash = "sha256-7UVfPICyIbHEClpr3p7eDR46OUzS8mVf6P7phnDpVLk=";

        installPhase = ''
          mkdir -p $out/share/${pname}
          cp -r node_modules $out/share/${pname}
        '';
      };
    in
    ''
      git -C third_party/openthread/repo apply ${sumodulePatch}

      substituteInPlace src/web/CMakeLists.txt \
        --replace-fail "Boost_USE_STATIC_LIBS ON" "Boost_USE_STATIC_LIBS OFF"

      substituteInPlace src/web/web-service/frontend/CMakeLists.txt \
        --replace-fail "npm install" "echo nop"
    ''
    + lib.optionalString withWeb ''
      substituteInPlace src/web/web-service/frontend/CMakeLists.txt \
        --replace-fail ' ''${CMAKE_CURRENT_BINARY_DIR}' " ${nodeModules}/share/${pname}"
    '';

  nativeBuildInputs = [
    cmake
    gitMinimal
    pkg-config
  ];

  buildInputs =
    [
      avahi
      protobuf
    ]
    ++ lib.optionals withWeb [
      boost
      jsoncpp
    ];

  # https://github.com/home-assistant/addons/blob/91160e1b5d00e13091b0537d85a3b3112e4a3f60/openthread_border_router/Dockerfile#L67
  cmakeFlags = [
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "OTBR_FEATURE_FLAGS" true)
    (lib.cmakeBool "OTBR_DNSSD_DISCOVERY_PROXY" true)
    (lib.cmakeBool "OTBR_SRP_ADVERTISING_PROXY" true)
    (lib.cmakeFeature "OTBR_MDNS" "avahi")
    (lib.cmakeFeature "OTBR_VERSION" "")
    (lib.cmakeFeature "OT_PACKAGE_VERSION" "")
    (lib.cmakeBool "OTBR_DBUS" false)
    (lib.cmakeBool "OT_POSIX_RCP_BUS_UART" true)
    (lib.cmakeFeature "OT_LINK_RAW" "1")
    (lib.cmakeFeature "OTBR_VENDOR_NAME" "HomeAssistant")
    (lib.cmakeFeature "OTBR_PRODUCT_NAME" "OpenThreadBorderRouter")
    (lib.cmakeBool "OTBR_WEB" withWeb)
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
