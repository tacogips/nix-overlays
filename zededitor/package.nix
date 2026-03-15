{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
}:
let
  version = "0.227.1";
  x86_64Hash = "sha256-IHS6EUaTaMaZGbuQmD6ppRXG1H6fDQIm5JUGbjmxBSQ=";
  aarch64Hash = "sha256-VLV8m0BHwCLHDTzjb3KqRf74Pa66jLF8qCR2WFOh0xc=";

  sources = {
    x86_64-linux = {
      system = "x86_64";
      hash = x86_64Hash;
    };
    aarch64-linux = {
      system = "aarch64";
      hash = aarch64Hash;
    };
  };

  sourceInfo =
    sources.${stdenv.hostPlatform.system}
      or (throw "zededitor is only supported on Linux for x86_64-linux and aarch64-linux");
in
stdenv.mkDerivation {
  pname = "zed-editor";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zed-industries/zed/releases/download/v${version}/zed-linux-${sourceInfo.system}.tar.gz";
    hash = sourceInfo.hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    stdenv.cc.cc.lib
  ];

  dontBuild = true;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share
    tar -xzf $src
    cp -r zed.app $out/lib/

    ln -s $out/lib/zed.app/share/applications $out/share/applications
    ln -s $out/lib/zed.app/share/icons $out/share/icons

    makeWrapper $out/lib/zed.app/bin/zed $out/bin/zed \
      --set-default ZED_UPDATE_EXPLANATION "Zed has been installed using Nix. Auto-updates have been disabled."

    runHook postInstall
  '';

  meta = {
    description = "High-performance multiplayer code editor";
    homepage = "https://zed.dev";
    changelog = "https://github.com/zed-industries/zed/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "zed";
    platforms = builtins.attrNames sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
