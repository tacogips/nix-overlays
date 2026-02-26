{
  lib,
  stdenv,
  buildNpmPackage,
  fetchzip,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  bubblewrap,
  procps,
  socat,
}:
buildNpmPackage (finalAttrs: {
  pname = "claude-code";
  version = "2.1.59";

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${finalAttrs.version}.tgz";
    hash = "sha256-Dam9aJ0qBdqU40ACfzGQHuytW6ur0fMLm8D5fIKd1TE=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-K+8xoBc3apvxQ9hCpYywqgBcfLxMWSxacgJcMH8mK7E=";

  strictDeps = true;

  dontNpmBuild = true;

  env.AUTHORIZED = "1";

  postInstall = ''
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --unset DEV \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            procps
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }
  '';

  nativeCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = lib.licenses.unfree;
  };
})
