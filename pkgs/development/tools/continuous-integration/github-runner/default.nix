{ autoSignDarwinBinariesHook
, buildDotnetModule
, dotnetCorePackages
, fetchFromGitHub
, fetchpatch
, git
, glibc
, glibcLocales
, lib
, nixosTests
, stdenv
, which
, buildPackages
, runtimeShell
  # List of Node.js runtimes the package should support
, nodeRuntimes ? [ "node20" ]
, nodejs_20
}:

# Node.js runtimes supported by upstream
assert builtins.all (x: builtins.elem x [ "node20" ]) nodeRuntimes;

buildDotnetModule rec {
  pname = "github-runner";
  version = "2.318.0";

  src = fetchFromGitHub {
    owner = "actions";
    repo = "runner";
    rev = "v${version}";
    hash = "sha256-jlUAtv5vrxJoHkN7HHvHum69ytcYmWJtMbmX2rhs1AU=";
    leaveDotGit = true;
    postFetch = ''
      git -C $out rev-parse --short HEAD > $out/.git-revision
      rm -rf $out/.git
    '';
  };

  # The git commit is read during the build and some tests depend on a git repo to be present
  # https://github.com/actions/runner/blob/22d1938ac420a4cb9e3255e47a91c2e43c38db29/src/dir.proj#L5
  unpackPhase = ''
    cp -r $src $TMPDIR/src
    chmod -R +w $TMPDIR/src
    cd $TMPDIR/src
    (
      export PATH=${buildPackages.git}/bin:$PATH
      git init
      git config user.email "root@localhost"
      git config user.name "root"
      git add .
      git commit -m "Initial commit"
      git checkout -b v${version}
    )
    mkdir -p $TMPDIR/bin
    cat > $TMPDIR/bin/git <<EOF
    #!${runtimeShell}
    if [ \$# -eq 1 ] && [ "\$1" = "rev-parse" ]; then
      echo $(cat $TMPDIR/src/.git-revision)
      exit 0
    fi
    exec ${buildPackages.git}/bin/git "\$@"
    EOF
    chmod +x $TMPDIR/bin/git
    export PATH=$TMPDIR/bin:$PATH
  '';

  patches = [
    # Replace some paths that originally point to Nix's read-only store
    ./patches/host-context-dirs.patch
    # Use GetDirectory() to obtain "diag" dir
    ./patches/use-get-directory-for-diag.patch
    # Don't try to install service
    ./patches/dont-install-service.patch
    # Access `.env` and `.path` relative to `$RUNNER_ROOT`, if set
    ./patches/env-sh-use-runner-root.patch
    # Fix FHS path: https://github.com/actions/runner/pull/2464
    (fetchpatch {
      name = "ln-fhs.patch";
      url = "https://github.com/actions/runner/commit/5ff0ce1.patch";
      hash = "sha256-2Vg3cKZK3cE/OcPDZkdN2Ro2WgvduYTTwvNGxwCfXas=";
    })
  ] ++ lib.optionals (nodeRuntimes == [ "node20" ]) [
    # If the package is built without Node 16, make Node 20 the default internal version
    # https://github.com/actions/runner/pull/2844
    (fetchpatch {
      name = "internal-node-20.patch";
      url = "https://github.com/actions/runner/commit/acdc6ed.patch";
      hash = "sha256-3/6yhhJPr9OMWBFc5/NU/DRtn76aTYvjsjQo2u9ZqnU=";
    })
  ];

  postPatch = ''
    # Ignore changes to src/Runner.Sdk/BuildConstants.cs
    substituteInPlace src/dir.proj \
      --replace 'git update-index --assume-unchanged ./Runner.Sdk/BuildConstants.cs' \
                'true'
  '';

  DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = isNull glibcLocales;
  LOCALE_ARCHIVE = lib.optionalString (!DOTNET_SYSTEM_GLOBALIZATION_INVARIANT) "${glibcLocales}/lib/locale/locale-archive";

  postConfigure = ''
    # Generate src/Runner.Sdk/BuildConstants.cs
    dotnet msbuild \
      -t:GenerateConstant \
      -p:ContinuousIntegrationBuild=true \
      -p:Deterministic=true \
      -p:PackageRuntime="${dotnetCorePackages.systemToDotnetRid stdenv.hostPlatform.system}" \
      -p:RunnerVersion="${version}" \
      src/dir.proj
  '';

  nativeBuildInputs = [
    which
    git
  ] ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
    autoSignDarwinBinariesHook
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;

  dotnetFlags = [ "-p:PackageRuntime=${dotnetCorePackages.systemToDotnetRid stdenv.hostPlatform.system}" ];

  # As given here: https://github.com/actions/runner/blob/0befa62/src/dir.proj#L33-L41
  projectFile = [
    "src/Sdk/Sdk.csproj"
    "src/Runner.Common/Runner.Common.csproj"
    "src/Runner.Listener/Runner.Listener.csproj"
    "src/Runner.Worker/Runner.Worker.csproj"
    "src/Runner.PluginHost/Runner.PluginHost.csproj"
    "src/Runner.Sdk/Runner.Sdk.csproj"
    "src/Runner.Plugins/Runner.Plugins.csproj"
  ];
  nugetDeps = ./deps.nix;

  doCheck = true;

  __darwinAllowLocalNetworking = true;

  # Fully qualified name of disabled tests
  disabledTests =
    [
      "GitHub.Runner.Common.Tests.Listener.SelfUpdaterL0.TestSelfUpdateAsync"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.OomScoreAdjIsInherited"
    ]
    ++ map (x: "GitHub.Runner.Common.Tests.Listener.SelfUpdaterL0.TestSelfUpdateAsync_${x}") [
      "Cancel_CloneHashTask_WhenNotNeeded"
      "CloneHash_RuntimeAndExternals"
      "DownloadRetry"
      "FallbackToFullPackage"
      "NoUpdateOnOldVersion"
      "NotUseExternalsRuntimeTrimmedPackageOnHashMismatch"
      "UseExternalsRuntimeTrimmedPackage"
      "UseExternalsTrimmedPackage"
      "ValidateHash"
    ]
    ++ map (x: "GitHub.Runner.Common.Tests.Listener.SelfUpdaterV2L0.${x}") [
      "TestSelfUpdateAsync_DownloadRetry"
      "TestSelfUpdateAsync_ValidateHash"
      "TestSelfUpdateAsync"
    ]
    ++ map (x: "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_${x}") [
      "CompositeActionWithActionfile_CompositeContainerNested"
      "CompositeActionWithActionfile_CompositePrestepNested"
      "CompositeActionWithActionfile_MaxLimit"
      "CompositeActionWithActionfile_Node"
      "DownloadActionFromGraph"
      "NotPullOrBuildImagesMultipleTimes"
      "RepositoryActionWithActionYamlFile_DockerHubImage"
      "RepositoryActionWithActionfileAndDockerfile"
      "RepositoryActionWithActionfile_DockerHubImage"
      "RepositoryActionWithActionfile_Dockerfile"
      "RepositoryActionWithActionfile_DockerfileRelativePath"
      "RepositoryActionWithActionfile_Node"
      "RepositoryActionWithDockerfile"
      "RepositoryActionWithDockerfileInRelativePath"
      "RepositoryActionWithDockerfilePrepareActions_Repository"
      "RepositoryActionWithInvalidWrapperActionfile_Node"
      "RepositoryActionWithWrapperActionfile_PreSteps"
    ]
    ++ map (x: "GitHub.Runner.Common.Tests.DotnetsdkDownloadScriptL0.${x}") [
      "EnsureDotnetsdkBashDownloadScriptUpToDate"
      "EnsureDotnetsdkPowershellDownloadScriptUpToDate"
    ]
    ++ [ "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestRunOnceHandleUpdateMessage" ]
    # Tests for trimmed runner packages which aim at reducing the update size. Not relevant for Nix.
    ++ map (x: "GitHub.Runner.Common.Tests.PackagesTrimL0.${x}") [
      "RunnerLayoutParts_CheckExternalsHash"
      "RunnerLayoutParts_CheckDotnetRuntimeHash"
    ]
    ++ lib.optionals (stdenv.hostPlatform.system == "aarch64-linux") [
      # "JavaScript Actions in Alpine containers are only supported on x64 Linux runners. Detected Linux Arm64"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNodeRuntimeVersionInAlpineContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNode20RuntimeVersionInAlpineContainerAsync"
    ]
    ++ lib.optionals DOTNET_SYSTEM_GLOBALIZATION_INVARIANT [
      "GitHub.Runner.Common.Tests.ProcessExtensionL0.SuccessReadProcessEnv"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.FormatUsesInvariantCulture"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_SetsOrdinalIgnoreCaseComparer"
      "GitHub.Runner.Common.Tests.Worker.WorkerL0.DispatchCancellation"
      "GitHub.Runner.Common.Tests.Worker.WorkerL0.DispatchRunNewJob"
    ]
    ++ lib.optionals (!lib.elem "node16" nodeRuntimes) [
      "GitHub.Runner.Common.Tests.ProcessExtensionL0.SuccessReadProcessEnv"
    ] ++ [
      "GitHub.Runner.Common.Tests.CommandLineParserL0.CanConstruct"
      "GitHub.Runner.Common.Tests.CommandLineParserL0.MasksSecretArgs"
      "GitHub.Runner.Common.Tests.CommandLineParserL0.ParsesArgs"
      "GitHub.Runner.Common.Tests.CommandLineParserL0.ParsesCommands"
      "GitHub.Runner.Common.Tests.CommandLineParserL0.ParsesFlags"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsArgSecretFromEnvVar"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsCommandConfigure"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsCommandRun"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsCommandUnconfigure"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagCommit"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagHelp"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagReplace"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagRunAsService"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagUnattended"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagUnattendedFromEnvVar"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsFlagVersion"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsNameArg"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.GetsNameArgFromEnvVar"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PassesUnattendedToReadBool"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PassesUnattendedToReadValue"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForAuth"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForReplace"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForRunAsService"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForRunnerDeletionToken"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForRunnerName"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForRunnerRegisterToken"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForToken"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForUrl"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsForWork"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsWhenEmpty"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.PromptsWhenInvalid"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateCommands"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateGoodArgCommandCombination"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateGoodCommandline"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateGoodFlagCommandCombination"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateInvalidArgCommandCombination"
      "GitHub.Runner.Common.Tests.CommandSettingsL0.ValidateInvalidFlagCommandCombination"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_Deserialization_LeanTimelineRecord"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_Deserialization_VariablesDictionaryIsCaseInsensitive"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_AttemptCannotBeLessThan1"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_DuplicateVariableKeysThrowsException"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_HandleLegacyNullsGracefully"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_HandleMissingCountsGracefully"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_NonNullCollections"
      "GitHub.Runner.Common.Tests.DistributedTask.TimelineRecordL0.VerifyTimelineRecord_DeserializationEdgeCase_NonZeroCounts"
      "GitHub.Runner.Common.Tests.ExtensionManagerL0.LoadsTypeFromString"
      "GitHub.Runner.Common.Tests.ExtensionManagerL0.LoadsTypes"
      "GitHub.Runner.Common.Tests.Listener.BrokerMessageListenerL0.CreatesSession"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ArgumentValidatorTestsL0.AuthSchemeValidator"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ArgumentValidatorTestsL0.NonEmptyValidator"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ArgumentValidatorTestsL0.ServerUrlValidator"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.CanEnsureConfigure"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.ConfigureDefaultLabelsDisabledWithCustomLabels"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.ConfigureErrorDefaultLabelsDisabledWithNoCustomLabels"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.ConfigureErrorOnMissingRunnerGroup"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.ConfigureRunnerServiceCreatesService"
      "GitHub.Runner.Common.Tests.Listener.Configuration.ConfigurationManagerL0.ConfigureRunnerServiceFailsOnUnconfiguredRunners"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.FallsBackToDefault"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.FallsBackToDefaultWhenTrimmed"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.FallsBackToDefaultWhenUnattended"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.Prompts"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.PromptsAgainWhenEmpty"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.PromptsAgainWhenFailsValidation"
      "GitHub.Runner.Common.Tests.Listener.Configuration.PromptManagerTestsL0.ThrowsWhenUnattended"
      "GitHub.Runner.Common.Tests.Listener.ErrorThrottlerL0.TestIncrementAndWait"
      "GitHub.Runner.Common.Tests.Listener.ErrorThrottlerL0.TestReceivesCancellationToken"
      "GitHub.Runner.Common.Tests.Listener.ErrorThrottlerL0.TestReceivesSender"
      "GitHub.Runner.Common.Tests.Listener.ErrorThrottlerL0.TestReset"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobOnRunServiceStopOnJobNotFoundExceptions"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequest"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequestFirstRenewRetrySixTimes"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequestRecoverFromExceptions"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequestStopOnExpiredRequest"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequestStopOnJobNotFoundExceptions"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatcherRenewJobRequestStopOnJobTokenExpiredExceptions"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatchesJobRequest"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.DispatchesOneTimeJobRequest"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.RenewJobRequestNewAgentNameUpdatesSettings"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.RenewJobRequestNullAgentNameIgnored"
      "GitHub.Runner.Common.Tests.Listener.JobDispatcherL0.RenewJobRequestSameAgentNameIgnored"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.CreateSessionWithOriginalCredential"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.CreatesSession"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.CreatesSessionWithBrokerMigration"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.DeleteSession"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.DeleteSessionWithBrokerMigration"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.GetNextMessage"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.GetNextMessageWithBrokerMigration"
      "GitHub.Runner.Common.Tests.Listener.MessageListenerL0.SkipDeleteSession_WhenGetNextMessageGetTaskAgentAccessTokenExpiredException"
      "GitHub.Runner.Common.Tests.Listener.PagingLoggerL0.ShipEmptyLog"
      "GitHub.Runner.Common.Tests.Listener.PagingLoggerL0.WriteAndShipLog"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestExecuteCommandForRunAsService"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestMachineProvisionerCLI"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestRemoveLocalRunnerConfig"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestRunAsync"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestRunOnce"
      "GitHub.Runner.Common.Tests.Listener.RunnerL0.TestRunOnceOnlyTakeOneJobMessage"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.KeepExistingCIEnv"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.OomScoreAdjIsWriten_Default"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.OomScoreAdjIsWriten_FromEnv"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.RedirectSTDINCloseStream"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.RedirectSTDINKeepStreamOpen"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.SetCIEnv"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.SuccessExitsWithCodeZero"
      "GitHub.Runner.Common.Tests.ProcessInvokerL0.TestCancel"
      "GitHub.Runner.Common.Tests.RunnerWebProxyL0.IsNotUseRawHttpClient"
      "GitHub.Runner.Common.Tests.RunnerWebProxyL0.IsNotUseRawHttpClientHandler"
      "GitHub.Runner.Common.Tests.ServiceControlManagerL0.CalculateServiceName"
      "GitHub.Runner.Common.Tests.ServiceControlManagerL0.CalculateServiceName80Chars"
      "GitHub.Runner.Common.Tests.ServiceControlManagerL0.CalculateServiceNameLimitsServiceNameTo150Chars"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_MatchesObjectEquality"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_MatchesReferenceEquality"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_MatchesStructEquality"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_ThrowsWhenActualObjectIsNull"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_ThrowsWhenExpectedObjectIsNull"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_ThrowsWhenObjectsAreNotEqual"
      "GitHub.Runner.Common.Tests.Util.ArgUtilL0.Equal_ThrowsWhenStructsAreNotEqual"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.Delete_DeletesDirectory"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.Delete_DeletesFile"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesDirectoriesRecursively"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesDirectoryReparsePointChain"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesDirectoryReparsePointsBeforeDirectories"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesFilesRecursively"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesReadOnlyDirectories"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesReadOnlyFiles"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DeletesReadOnlyRootDirectory"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DoesNotFollowDirectoryReparsePoint"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DoesNotFollowNestLevel1DirectoryReparsePoint"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_DoesNotFollowNestLevel2DirectoryReparsePoint"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteDirectory_IgnoresFile"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteFile_DeletesFile"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteFile_DeletesReadOnlyFile"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.DeleteFile_IgnoresDirectory"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.GetRelativePath"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.LoadObject_ThrowsOnRequiredLoadObject"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.ResolvePath"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.ValidateExecutePermission_DoesNotExceedFailsafe"
      "GitHub.Runner.Common.Tests.Util.IOUtilL0.ValidateExecutePermission_ExceedsFailsafe"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.ConvertNullOrEmptryStringToBool"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.ConvertNullOrEmptryStringToDefaultBool"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.ConvertStringToBool"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.FormatAlwaysCallsFormat"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.FormatHandlesFormatException"
      "GitHub.Runner.Common.Tests.Util.StringUtilL0.FormatUsesInvariantCulture"
      "GitHub.Runner.Common.Tests.Util.TaskResultUtilL0.TaskResultReturnCodeTranslate"
      "GitHub.Runner.Common.Tests.Util.TaskResultUtilL0.TaskResultsMerge"
      "GitHub.Runner.Common.Tests.Util.VssUtilL0.VerifyOverwriteVssConnectionSetting"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.UseWhichFindGit"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichHandleFullyQualifiedPath"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichHandlesSymlinkToTargetFullPath"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichHandlesSymlinkToTargetRelativePath"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichReturnsNullWhenNotFound"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichThrowsWhenRequireAndNotFound"
      "GitHub.Runner.Common.Tests.Util.WhichUtilL0.WhichThrowsWhenSymlinkBroken"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.AddMaskWithMultilineValue"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.AddMatcherTranslatesFilePath"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.DisablePluginInternalCommand"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.EchoProcessCommand"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.EchoProcessCommandDebugOn"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.EchoProcessCommandInvalid"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.EnablePluginInternalCommand"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.IssueCommandInvalidColumns"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.StopProcessCommand__AllowsInvalidStopTokens__IfEnvVarIsSet"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.StopProcessCommand__FailOnInvalidStopTokens"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.StopProcessCommand"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.StopProcessCommandAcceptsValidToken"
      "GitHub.Runner.Common.Tests.Worker.ActionCommandManagerL0.StopProcessCommandMasksValidTokenForEntireRun"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerActionDefinitionDockerfile_Cleanup"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerActionDefinitionDockerfile_SelfRepo"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerActionDefinitionDockerfile"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerActionDefinitionRegistry_SelfRepo"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerActionDefinitionRegistry"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsContainerRegistryActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNode12ActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNode16ActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNode20ActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNodeActionDefinition_Cleanup"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNodeActionDefinition_SelfRepo"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsNodeActionDefinitionYaml"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsPluginActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.LoadsScriptActionDefinition"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_AlwaysClearActionsCache"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_DownloadActionFromDotCom_OnPremises_Legacy"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_DownloadActionFromDotCom_ZipFileError"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_DownloadActionFromGraph_UseCache"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_DownloadUnknownActionFromGraph_OnPremises_Legacy"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_PullImageFromDockerHub"
      "GitHub.Runner.Common.Tests.Worker.ActionManagerL0.PrepareActions_SkipDownloadActionForSelfRepo"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Evaluate_ContainerAction_Args"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Evaluate_ContainerAction_Env"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Evaluate_Default_Input"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_CompositeActionNoUsing"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ConditionalCompositeAction"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile_Expression"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile_Post_DefaultCondition"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile_Post"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile_Pre_DefaultCondition"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile_Pre"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_Dockerfile"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_DockerHub"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_ContainerAction_NoArgsNoEnv"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_Node16Action"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_Node20Action"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_NodeAction_Cleanup_DefaultCondition"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_NodeAction_Cleanup"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_NodeAction_Init_DefaultCondition"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_NodeAction_Pre"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_NodeAction"
      "GitHub.Runner.Common.Tests.Worker.ActionManifestManagerL0.Load_PluginAction"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.EvaluateDisplayNameWithoutContext"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.EvaluateExpansionOfContainerDisplayName"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.EvaluateExpansionOfDisplayNameToken"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.EvaluateExpansionOfScriptDisplayName"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.EvaluateLegacyDisplayName"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.IgnoreDisplayNameTokenWhenDisplayNameIsExplicitlySet"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.MergeDefaultInputs"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.SetGitHubContextActionRepoRef"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.WarnInvalidInputs"
      "GitHub.Runner.Common.Tests.Worker.ActionRunnerL0.WriteEventPayload"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.InitializeWithCorrectManager"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.RunServiceContainersHealthcheck_healthyServiceContainer_AssertSucceededTask"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.RunServiceContainersHealthcheck_healthyServiceContainerWithoutHealthcheck_AssertSucceededTask"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.RunServiceContainersHealthcheck_UnhealthyServiceContainer_Asserask"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.RunServiceContainersHealthcheck_UnhealthyServiceContainer_AssertExceptionThrown"
      "GitHub.Runner.Common.Tests.Worker.ContainerOperationProviderL0.RunServiceContainersHealthcheck_UnhealthyServiceContainer_AssertFailedTask"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_DirectoryNotFound"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_EmptyFile"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_FileNotFound"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_FileNull"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_LargeFile"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_ScrubSecrets"
      "GitHub.Runner.Common.Tests.Worker.CreateStepSummaryCommandL0.CreateStepSummaryCommand_Simple"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.ActionResult_Lowercase"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.ActionVariables_AddedToVarsContext"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.ActionVariables_DebugUsingVars"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.ActionVariables_SecretsPrecedenceForDebugUsingVars"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.AddIssue_AddStepAndLineNumberInformation"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.AddIssue_CountWarningsErrors"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.AddIssue_OverrideLogMessage"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.AddIssue_TrimMessageSize"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.ApplyContinueOnError_CheckResultAndOutcome"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.Debug_Multilines"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.GetExpressionValues_ContainerStepHost"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.PublishStepResult_EmbeddedStep"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.PublishStepTelemetry_EmbeddedStep"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.PublishStepTelemetry_RegularStep_NoOpt"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.PublishStepTelemetry_RegularStep"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.RegisterPostJobAction_NotRegisterPostTwice"
      "GitHub.Runner.Common.Tests.Worker.ExecutionContextL0.RegisterPostJobAction_ShareState"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.AlwaysFunction"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.CancelledFunction"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.FailureFunction"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.FailureFunctionComposite"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.SuccessFunction"
      "GitHub.Runner.Common.Tests.Worker.Expressions.ConditionFunctionsL0.SuccessFunctionComposite"
      "GitHub.Runner.Common.Tests.Worker.HandlerFactoryL0.IsNodeVersionUpgraded"
      "GitHub.Runner.Common.Tests.Worker.HandlerL0.PrepareExecution_PopulateTelemetry_DockerActions"
      "GitHub.Runner.Common.Tests.Worker.HandlerL0.PrepareExecution_PopulateTelemetry_RepoActions"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.DontUploadDiagnosticLogIfEnvironmentVariableFalse"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.DontUploadDiagnosticLogIfEnvironmentVariableMissing"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureFinalizeJobHandlesNullEnvironment"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureFinalizeJobHandlesNullEnvironmentUrl"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureFinalizeJobRunsIfMessageHasNoEnvironmentUrl"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureNoPreAndPostHookSteps"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureNoSnapshotPostJobStep"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsurePreAndPostHookStepsIfEnvExists"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureSnapshotPostJobStepForMappingToken"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.EnsureSnapshotPostJobStepForStringToken"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.JobExtensionBuildFailsWithoutContainerIfRequired"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.JobExtensionBuildPreStepsList"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.JobExtensionBuildStepsList"
      "GitHub.Runner.Common.Tests.Worker.JobExtensionL0.UploadDiganosticLogIfEnvironmentVariableSet"
      "GitHub.Runner.Common.Tests.Worker.JobRunnerL0.JobExtensionInitializeCancelled"
      "GitHub.Runner.Common.Tests.Worker.JobRunnerL0.JobExtensionInitializeFailure"
      "GitHub.Runner.Common.Tests.Worker.JobRunnerL0.WorksWithRunnerJobRequestMessageType"
      "GitHub.Runner.Common.Tests.Worker.LoggingCommandL0.CommandParserTest"
      "GitHub.Runner.Common.Tests.Worker.LoggingCommandL0.CommandParserV2Test"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.AddMatcher_Clobber"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.AddMatcher_Prepend"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.CaptureTelemetryForGitUnsafeRepository"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.DoesNotResetMatchingMatcher"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.InitialMatchers"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherCode"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherDoesNotReceiveCommand"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherFile_JobContainer"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherFile_StepContainer"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherFile"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherFromPath"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherLineColumn"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherRemoveColorCodes"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherSeverity"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.MatcherTimeout"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.RemoveMatcher"
      "GitHub.Runner.Common.Tests.Worker.OutputManagerL0.ResetsOtherMatchers"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.CreatesPipelineDirectories"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.DeletesNonResourceDirectoryWhenCleanIsOutputs"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.DeletesResourceDirectoryWhenCleanIsResources"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.RecreatesPipelinesDirectoryWhenCleanIsAll"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.UpdatesExistingConfig"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.UpdatesRepositoryDirectoryNoneWorkspaceRepo"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.UpdatesRepositoryDirectoryThrowOnInvalidPath"
      "GitHub.Runner.Common.Tests.Worker.PipelineDirectoryManagerL0.UpdatesRepositoryDirectoryWorkspaceRepo"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_DirectoryNotFound"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_EmptyFile"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc_MissingNewLine"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc_MissingNewLineMultipleLines"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Heredoc"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_NotFound"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Simple_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Simple_MultipleValues"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Simple_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Simple_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SaveStateFileCommandL0.SaveStateFileCommand_Simple"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_BlockListItemsFiltered_Heredoc"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_BlockListItemsFiltered"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_DirectoryNotFound"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_EmptyFile"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc_MissingNewLine"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc_MissingNewLineMultipleLinesEnv"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Heredoc"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_NotFound"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Simple_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Simple_MultipleValues"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Simple_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Simple_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SetEnvFileCommandL0.SetEnvFileCommand_Simple"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_DirectoryNotFound"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_EmptyFile"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc_MissingNewLine"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc_MissingNewLineMultipleLines"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Heredoc"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_NotFound"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Simple_EmptyValue"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Simple_MultipleValues"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Simple_SkipEmptyLines"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Simple_SpecialCharacters"
      "GitHub.Runner.Common.Tests.Worker.SetOutputFileCommandL0.SetOutputFileCommand_Simple"
      "GitHub.Runner.Common.Tests.Worker.SnapshotOperationProviderL0.CreateSnapshotRequestAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNode20RuntimeVersionInAlpineContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNode20RuntimeVersionInUnknowContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNodeRuntimeVersionInAlpineContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNodeRuntimeVersionInContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepHostL0.DetermineNodeRuntimeVersionInUnknowContainerAsync"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.AlwaysMeansAlways"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.PopulateEnvContextAfterSetupStepsContext"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.PopulateEnvContextForEachStep"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.RunNormalStepsAllStepPass"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.RunNormalStepsContinueOnError"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.RunsAfterFailureBasedOnCondition"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.RunsAlwaysSteps"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.SetsJobResultCorrectly"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.SkipsAfterFailureOnlyBaseOnCondition"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.StepContextConclusion"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.StepContextOutcome"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.StepEnvOverrideJobEnvContext"
      "GitHub.Runner.Common.Tests.Worker.StepsRunnerL0.TreatsConditionErrorAsFailure"
      "GitHub.Runner.Common.Tests.Worker.TrackingManagerL0.CreatesTrackingConfig"
      "GitHub.Runner.Common.Tests.Worker.TrackingManagerL0.LoadsTrackingConfig_NotExists"
      "GitHub.Runner.Common.Tests.Worker.TrackingManagerL0.LoadsTrackingConfig"
      "GitHub.Runner.Common.Tests.Worker.TrackingManagerL0.UpdatesTrackingConfigJobRunProperties"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_AppliesMaskHints"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_HandlesNullValue"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_SetsNullAsEmpty"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_SetsOrdinalIgnoreCaseComparer"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Constructor_SkipVariableWithEmptyName"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.Get_ReturnsNullIfNotFound"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.GetBoolean_DoesNotThrowWhenNull"
      "GitHub.Runner.Common.Tests.Worker.VariablesL0.GetEnum_DoesNotThrowWhenNull"
      "GitHub.Runner.Common.Tests.Worker.WorkerL0.DispatchCancellation"
      "GitHub.Runner.Common.Tests.Worker.WorkerL0.DispatchRunNewJob"
    ];

  testProjectFile = [ "src/Test/Test.csproj" ];

  preCheck = ''
    mkdir -p _layout/externals
  '' + lib.optionalString (lib.elem "node20" nodeRuntimes) ''
    ln -s ${nodejs_20} _layout/externals/node20
  '';

  postInstall = ''
    mkdir -p $out/bin

    install -m755 src/Misc/layoutbin/runsvc.sh                 $out/lib/github-runner
    install -m755 src/Misc/layoutbin/RunnerService.js          $out/lib/github-runner
    install -m755 src/Misc/layoutroot/run.sh                   $out/lib/github-runner
    install -m755 src/Misc/layoutroot/run-helper.sh.template   $out/lib/github-runner/run-helper.sh
    install -m755 src/Misc/layoutroot/config.sh                $out/lib/github-runner
    install -m755 src/Misc/layoutroot/env.sh                   $out/lib/github-runner

    # env.sh is patched to not require any wrapping
    ln -sr "$out/lib/github-runner/env.sh" "$out/bin/"

    substituteInPlace $out/lib/github-runner/config.sh \
      --replace './bin/Runner.Listener' "$out/bin/Runner.Listener"
  '' + lib.optionalString stdenv.isLinux ''
    substituteInPlace $out/lib/github-runner/config.sh \
      --replace 'command -v ldd' 'command -v ${glibc.bin}/bin/ldd' \
      --replace 'ldd ./bin' '${glibc.bin}/bin/ldd ${dotnet-runtime}/shared/Microsoft.NETCore.App/${dotnet-runtime.version}/' \
      --replace '/sbin/ldconfig' '${glibc.bin}/bin/ldconfig'
  '' + ''
    # Remove uneeded copy for run-helper template
    substituteInPlace $out/lib/github-runner/run.sh --replace 'cp -f "$DIR"/run-helper.sh.template "$DIR"/run-helper.sh' ' '
    substituteInPlace $out/lib/github-runner/run-helper.sh --replace '"$DIR"/bin/' '"$DIR"/'

    # Make paths absolute
    substituteInPlace $out/lib/github-runner/runsvc.sh \
      --replace './externals' "$out/lib/externals" \
      --replace './bin/RunnerService.js' "$out/lib/github-runner/RunnerService.js"

    # The upstream package includes Node and expects it at the path
    # externals/node$version. As opposed to the official releases, we don't
    # link the Alpine Node flavors.
    mkdir -p $out/lib/externals
  '' + lib.optionalString (lib.elem "node20" nodeRuntimes) ''
    ln -s ${nodejs_20} $out/lib/externals/node20
  '' + ''
    # Install Nodejs scripts called from workflows
    install -D src/Misc/layoutbin/hashFiles/index.js $out/lib/github-runner/hashFiles/index.js
    mkdir -p $out/lib/github-runner/checkScripts
    install src/Misc/layoutbin/checkScripts/* $out/lib/github-runner/checkScripts/
  '' + lib.optionalString stdenv.isLinux ''
    # Wrap explicitly to, e.g., prevent extra entries for LD_LIBRARY_PATH
    makeWrapperArgs=()

    # We don't wrap with libicu
    substituteInPlace $out/lib/github-runner/config.sh \
      --replace '$LDCONFIG_COMMAND -NXv ''${libpath//:/ }' 'echo libicu'
  '' + ''
    # XXX: Using the corresponding Nix argument does not work as expected:
    #      https://github.com/NixOS/nixpkgs/issues/218449
    # Common wrapper args for `executables`
    makeWrapperArgs+=(
      --run 'export RUNNER_ROOT="''${RUNNER_ROOT:-"$HOME/.github-runner"}"'
      --run 'mkdir -p "$RUNNER_ROOT"'
      --chdir "$out"
    )
  '';

  # List of files to wrap
  executables = [
    "config.sh"
    "Runner.Listener"
    "Runner.PluginHost"
    "Runner.Worker"
    "run.sh"
    "runsvc.sh"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export RUNNER_ROOT="$TMPDIR"

    $out/bin/config.sh --help >/dev/null
    $out/bin/Runner.Listener --help >/dev/null

    version=$($out/bin/Runner.Listener --version)
    if [[ "$version" != "${version}" ]]; then
      printf 'Unexpected version %s' "$version"
      exit 1
    fi

    commit=$($out/bin/Runner.Listener --commit)
    if [[ "$commit" != "$(git rev-parse HEAD)" ]]; then
      printf 'Unexpected commit %s' "$commit"
      exit 1
    fi

    runHook postInstallCheck
  '';

  passthru = {
    tests.smoke-test = nixosTests.github-runner;
    updateScript = ./update.sh;
  };

  meta = with lib; {
    changelog = "https://github.com/actions/runner/releases/tag/v${version}";
    description = "Self-hosted runner for GitHub Actions";
    homepage = "https://github.com/actions/runner";
    license = licenses.mit;
    maintainers = with maintainers; [ veehaitch newam kfollesdal aanderse zimbatm ];
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
