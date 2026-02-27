{
  lib,
  makeBinaryWrapper,
  symlinkJoin,
  zed-editor,
}:
symlinkJoin {
  name = "zededitor-${zed-editor.version}";
  paths = [ zed-editor ];
  nativeBuildInputs = [ makeBinaryWrapper ];
  postBuild = ''
    makeWrapper ${lib.getExe zed-editor} $out/bin/zededitor
  '';

  meta = zed-editor.meta // {
    mainProgram = "zededitor";
  };
}
