{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  poetry-core,
  aiohttp,
  aiohttp-client-cache,
  pydantic,
  requests,
  requests-cache,
  simplejson,
  pytestCheckHook,
  pytest-asyncio,
}:

buildPythonPackage rec {
  pname = "homeassistant-api";
  version = "4.2.2.post2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "GrandMoff100";
    repo = "HomeAssistantAPI";
    rev = "refs/tags/v${version}";
    hash = "sha256-iZDl9ZkdxDWQBg1EsR1Pthwhmumh+EZcy2IJuHrlAVk=";
  };

  build-system = [ poetry-core ];

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'pydantic = ">=2.0,<2.9"' 'pydantic = "*"' \
      --replace-fail 'requests-cache = "^0.9.2"' 'requests-cache = "*"'
  '';

  dependencies = [
    aiohttp
    aiohttp-client-cache
    pydantic
    requests
    requests-cache
    simplejson
  ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
  ];

  pythonImportsCheck = [ "homeassistant_api" ];

  meta = {
    description = "Python Wrapper for Homeassistant's REST API";
    homepage = "https://github.com/GrandMoff100/HomeAssistantAPI";
    changelog = "https://github.com/GrandMoff100/HomeAssistantAPI/releases/tag/v${version}";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ newam ];
  };
}
