# glualint (FPtje/GLuaFixer) from its release binaries; nothing is built from source (TASKS.md, "Toolchain").
# The "OSX-x86_64" asset of 1.30.0 is in fact an arm64 Mach-O binary, so only aarch64-darwin is supported on macOS.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  autoPatchelfHook,
}:
let
  version = "1.30.0";
  base = "https://github.com/FPtje/GLuaFixer/releases/download/${version}";
  sources = {
    aarch64-darwin = fetchurl {
      url = "${base}/glualint-${version}-OSX-x86_64.tar.gz";
      hash = "sha256-PsoUeg1o1jk7mV87VKbInq/Mg+iZ8QF6ijD+Qms57dc=";
    };
    x86_64-linux = fetchurl {
      url = "${base}/glualint-${version}-x86_64-linux.zip";
      hash = "sha256-3c62nJSaignTILT4EOG6rhtG8O+neqMcoyahTcT2GTo=";
    };
    # Upstream names this asset "1.3.0"; it is the aarch64 build of the 1.30.0 release.
    aarch64-linux = fetchurl {
      url = "${base}/glualint-1.3.0-linux-aarch64.zip";
      hash = "sha256-h4b80kuYMAIzokuGBKbIyHj/+GXIGtrHbBmzQlnhGag=";
    };
  };
  system = stdenvNoCC.hostPlatform.system;
in
stdenvNoCC.mkDerivation {
  pname = "glualint-bin";
  inherit version;
  src = sources.${system} or (throw "glualint-bin: no release binary for ${system}");
  sourceRoot = ".";
  nativeBuildInputs = [ unzip ] ++ lib.optional stdenvNoCC.hostPlatform.isLinux autoPatchelfHook;
  installPhase = ''
    runHook preInstall
    install -D --mode=0755 glualint $out/bin/glualint
    runHook postInstall
  '';
  meta = {
    description = "Linter and pretty printer for Garry's Mod Lua (release binary)";
    homepage = "https://github.com/FPtje/GLuaFixer";
    license = lib.licenses.lgpl21Only;
    mainProgram = "glualint";
    platforms = builtins.attrNames sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
