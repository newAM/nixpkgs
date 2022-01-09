{ lib
, buildPythonPackage
, pythonOlder
, fetchFromGitHub
# https://github.com/MycroftAI/mycroft-core/blob/release/v21.2.2/requirements/requirements.txt
, requests
, gtts
, pyaudio
, pyee
, speechrecognition
, tornado
, websocket-client
, requests-futures
, pyserial
, psutil
, pocketsphinx
, inflection
, pillow
, python-dateutil
, fasteners
, pyyaml
, lingua-franca
, mycroft-skills-manager
, mycroft-messagebus-client
, adapt-parser
, padatious
, fann2
, padaos
, pyxdg
, PyChromecast
, python-vlc
, pytestCheckHook
}:

buildPythonPackage rec {
  pname = "mycroft-core";
  version = "21.2.2";

  # disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "MycroftAI";
    repo = "mycroft-core";
    rev = "release/v${version}";
    sha256 = "02r0vxw0hsihnvviwn4fyspwky3kwq42f9z455q1s70k0snzhb28";
  };

  # TODO: missing deps
  prePatch = ''
    substituteInPlace requirements/requirements.txt \
      --replace "requests>=2.20.0,<2.26.0" "requests" \
      --replace "msk==0.3.16" "" \
      --replace "padatious==0.4.8" "" \
      --replace "precise-runner==0.2.1" "" \
      --replace "petact==0.1.2" "" \
      --replace "==" ">="

    substituteInPlace mycroft/client/speech/hotword_factory.py \
      --replace "from petact import install_package" ""
  '';

  propagatedBuildInputs = [
    requests
    pyaudio
    gtts
    pyee
    speechrecognition
    tornado
    websocket-client
    requests-futures
    pyserial
    psutil
    pocketsphinx
    inflection
    pillow
    python-dateutil
    fasteners
    pyyaml

    lingua-franca
    mycroft-skills-manager
    # msk
    mycroft-messagebus-client
    adapt-parser
    padatious
    fann2
    padaos

    pyxdg

    # audio backends
    PyChromecast
    python-vlc
  ];

  checkInputs = [ pytestCheckHook ];

  disabledTests = [
    "test_is_paired_error_remote"
    "testInvalid"
    "testListenerConfig"
    "test_cps_play"
    "test_handle_start_playback"
    "test_lifecycle"
    "test_stop"
    "test_handle_play_query_no_match"
    "test_play_query_match"
    "test_common_test_skill_action"
    "test_lifecycle"
    "test_failing_match_query_phrase"
    "test_successful_match_query_phrase"
    "test_successful_visual_match_query_phrase"
    "test_add_remove"
    "test_create"
    "test_save"
    "test_send_event"
    "test_life_cycle"
    "test_manual_removal"
    "test_get_intent"
    "test_get_intent_manifest"
    "test_get_intent_no_match"
    "test_add_event"
    "test_add_scheduled_event"
    "test_enable_disable_intent"
    "test_enable_disable_intent_handlers"
    "test_failing_remove_context"
    "test_failing_set_context"
    "test_register_decorators"
    "test_register_intent"
    "test_register_intent_file"
    "test_register_intent_intent_file"
    "test_register_vocab"
    "test_remove_context"
    "test_remove_event"
    "test_remove_scheduled_event"
    "test_run_scheduled_event"
    "test_set_context"
    "test_skill_location"
    "test_speak_dialog_render_not_initialized"
    "test_translate_locations"
    "test_voc_match"
    "test_voc_match_exact"
    "test_wait"
    "test_wait_cancel"
    "test_get_response"
    "test_get_response_no_dialog"
    "test_get_response_text"
    "test_get_response_validator"
    "test_ask_yesno_german"
    "test_ask_yesno_no"
    "test_ask_yesno_other"
    "test_ask_yesno_yes"
    "test_selection_last"
    "test_selection_name"
    "test_selection_number"
    "test_public_api"
    "test_public_api_event"
    "test_public_api_method"
    "test_public_api_request"
    "test_call_api_method"
    "test_create_api_object"
    "test_installed_skills_path_not_virtual_env"
    "test_update_download_time"
    "test_load "
    "test_default_config_succeeds"
    "test_secondary_dns_succeeds"
    "test_default_timezone"
    "test_now_local"
    "test_get_version"
    "test_version_manager_get"
    "test_version_manager_get_no_file"
  ];

  meta = with lib; {
    description = "Mycroft Core, the Mycroft Artificial Intelligence platform.";
    homepage = "https://mycroft.ai";
    changelog = "https://github.com/MycroftAI/mycroft-core/releases";
    license = licenses.mit;
    maintainers = with maintainers; [ newam ];
  };
}
