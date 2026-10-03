{
  lib,
  stdenvNoCC,
  bashNonInteractive,
  borgbackup,
  btrbk,
  coreutils,
  gnugrep,
  installShellFiles,
  makeWrapper,
  scdoc,
  shellcheck,
  version ? "git",
  src ? lib.cleanSource ../.,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "btrborg";
  inherit version src;

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
    scdoc
    shellcheck
  ];

  buildPhase = ''
    runHook preBuild

    substituteInPlace bin/btrborg \
      --replace-fail "#!/usr/bin/env bash" "#!${lib.getExe bashNonInteractive}" \
      --replace-fail "@VERSION@" "${finalAttrs.version}"
    scdoc < doc/btrborg.1.scd > btrborg.1
    scdoc < doc/btrborg.conf.5.scd > btrborg.conf.5

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    shellcheck --shell=bash bin/btrborg
    shellcheck --shell=bash completions/btrborg.bash
    bash -n bin/btrborg

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/btrborg "$out/bin/btrborg"
    installManPage btrborg.1 btrborg.conf.5
    installShellCompletion --bash --name btrborg completions/btrborg.bash
    install -Dm644 doc/btrborg.conf.example "$out/share/doc/btrborg/btrborg.conf.example"

    wrapProgram "$out/bin/btrborg" \
      --prefix PATH : ${
        lib.makeBinPath [
          borgbackup
          btrbk
          coreutils
          gnugrep
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Back up the latest btrbk snapshots into borg repositories";
    longDescription = ''
      btrborg asks btrbk for the most recent snapshot of every configured
      subvolume and stores it in a borg repository of the same name. It can
      initialise the repositories, create, inspect and verify archives, and
      apply a retention policy.
    '';
    homepage = "https://github.com/FlorianFranzen/btrborg";
    changelog = "https://github.com/FlorianFranzen/btrborg/blob/main/CHANGELOG.md";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "btrborg";
  };
})
