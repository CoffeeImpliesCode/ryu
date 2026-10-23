
{ lib
, stdenv
, zig
, pkg-config
, linkage ? "static"
, generic128 ? false
}:

assert lib.elem linkage [ "static" "dynamic" ];
assert builtins.isBool generic128;

let
  version = "2.0.0-dev.4c0618b";

  # Files installed by build.zig; checked after installation.
  installedFiles = [
    "include/ryu/ryu.h"
    "include/ryu/ryu_parse.h"
    "include/translate.h"
    "lib/pkgconfig/ryu.pc"
  ] ++ lib.optional generic128 "include/ryu/ryu_generic_128.h";

  zigBuildFlags = [
    "-Doptimize=ReleaseSafe"
    "-Dcpu=baseline"
    "-Dlinkage=${linkage}"
  ] ++ lib.optional generic128 "-Dgeneric128=true";

  # Keep the Nix licence metadata and installed records in sync.
  licenseFiles = [
    "LICENSE-Apache2"
    "LICENSE-Boost"
    "CONTRIBUTORS"
    "NOTICE.md"
    "FORK-LICENSE.md"
    "UPSTREAM.md"
    "README.upstream.md"
    "third_party/gtest/LICENSE"
    "third_party/junit/LICENSE"
    "third_party/mersenne/LICENSE"
    "third_party/jaffer/LICENSE"
    "third_party/double-conversion/LICENSE"
    "third_party/double-conversion/COPYING"
  ];

  # Match Zig's target-specific library names and install locations.
  libraryFile =
    if stdenv.hostPlatform.isWindows
    then if linkage == "static" then "lib/ryu.lib" else "bin/ryu.dll"
    else if linkage == "static" then "lib/libryu.a"
    else if stdenv.hostPlatform.isDarwin then "lib/libryu.dylib"
    else "lib/libryu.so";
in
stdenv.mkDerivation {
  pname = "ryu";
  inherit version;

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: _type:
      let name = baseNameOf (toString path);
      in !(builtins.elem name [
        ".git" ".hg" ".svn" ".bzr"
        ".zig-cache" "zig-cache" "zig-out" "zig-pkg"
        ".devenv" ".devenv.flake.nix" ".direnv"
        "result"
      ] || lib.hasPrefix "result-" name);
  };

  strictDeps = true;
  nativeBuildInputs = [ zig pkg-config ];

  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches outside the source tree.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"

    zig build install \
      --prefix "$out" \
      --cache-dir "$TMPDIR/zig-local-cache" \
      -j"''${NIX_BUILD_CORES:-1}" \
      --summary all \
      --color off \
      ${lib.concatStringsSep " " zigBuildFlags}

    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck

    for path in "$out/${libraryFile}" ${lib.concatMapStringsSep " " (p: ''"$out/${p}"'') installedFiles}; do
      if [ ! -s "$path" ]; then
        echo "package.nix: expected install output missing or empty: $path" >&2
        exit 1
      fi
    done

    for path in ${lib.concatMapStringsSep " " (p: ''"$out/share/licenses/ryu/${p}"'') licenseFiles}; do
      if [ ! -s "$path" ]; then
        echo "package.nix: licence material missing or empty: $path" >&2
        exit 1
      fi
    done

    # Query the pkg-config metadata installed by the build graph.
    export PKG_CONFIG_PATH="$out/lib/pkgconfig"
    pkg-config --exists ryu \
      || { echo "package.nix: ryu.pc does not resolve" >&2; exit 1; }
    pkg-config --cflags ryu
    pkg-config --libs ryu
    pkg-config --libs --static ryu

    runHook postInstallCheck
  '';

  passthru = {
    inherit linkage generic128 installedFiles licenseFiles;
    upstreamReadme = "README.upstream.md";
  };

  meta = {
    description = "Shortest, fixed and scientific IEEE-754 to decimal conversion";
    longDescription = ''
      Ryu converts IEEE-754 binary floating point to decimal in shortest
      round-trip-safe form and in fixed and scientific form. This package builds
      upstream's C from this repository with the SDK's own Zig build graph and
      installs it as a native library with its public headers, link metadata and
      licence record. No digit is produced by this package.

      The native core is Apache-2.0 OR BSL-1.0: upstream grants Apache-2.0
      outside ryu/ and offers Boost-1.0 for the files in ryu/, and both texts are
      installed. Fork-authored files are Apache-2.0 (FORK-LICENSE.md). Vendored
      third_party/ corpora keep their own terms and ship with the output.
    '';
    homepage = "https://github.com/ulfjack/ryu";
    license = lib.licenses.asl20;
    licenseFiles = licenseFiles;
    platforms = lib.platforms.all;
  };
}
