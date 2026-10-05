# Source-only Nix derivation for the ryu SDK.
#
# One derivation; `linkage` selects the variant. flake.nix and devenv.nix both
# reach this through pkgs.callPackage. No sibling import, no fetch, no host path,
# no builtins.getEnv.
#
# The build graph owns C flags, source lists, headers and every installed file;
# this file only calls `zig build install` and checks the result. It does not
# place include/ or lib/ by hand and does not duplicate a .pc or a licence file
# the graph installs.
#
#   linkage     "static" (default) or "dynamic". Static is this SDK's existing
#               policy (build.zig) and upstream's CMake default (BUILD_SHARED_LIBS
#               defaults OFF).
#   generic128  false (default). Upstream's experimental generic 128-bit
#               converter; needs __uint128_t and a working long double
#               (ryu/BUILD:38-49 tags it nowindows), so it is never on by
#               default and never in a matrix run.

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

  # One writer per path: the build graph installs these. This list is the
  # contract installCheckPhase enforces, not a second copy of it.
  installedFiles = [
    "include/ryu/ryu.h"
    "include/ryu/ryu_parse.h"
    "include/translate.h"
    "lib/pkgconfig/ryu.pc"
  ] ++ lib.optional generic128 "include/ryu/ryu_generic_128.h";

  # One optimize selection, one CPU baseline, one linkage. Optional native
  # dependency settings are never enabled implicitly. A let binding and not an
  # attribute of the derivation: installPhase is an interpolated string, and a
  # derivation attribute set is not recursive.
  zigBuildFlags = [
    "-Doptimize=ReleaseSafe"
    "-Dcpu=baseline"
    "-Dlinkage=${linkage}"
  ] ++ lib.optional generic128 "-Dgeneric128=true";

  # meta.licenseFiles and the installed licence record are the same list.
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

  # The artifact's name and directory are the compiler's own rules, not this
  # file's guesses: std/zig.zig:binNameAlloc spells a coff target `ryu.lib` or
  # `ryu.dll`, an elf one `libryu.a` or `libryu.so`, a macho one `libryu.a` or
  # `libryu.dylib`, and std/Build/Step/InstallArtifact.zig:61-67 installs a DLL
  # under bin/ and every other library under lib/.
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

  # Build output, version-control metadata and development state. Everything
  # else, including every source, header, test, fixture and licence file, stays.
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

  # All of the Zig setup hook's phases are replaced by installPhase and
  # installCheckPhase below, so none of its builds can run. dontConfigure also
  # keeps the global Zig cache out of the unpacked source tree.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  dontSetZigDefaultFlags = true;
  dontAddPrefix = true;

  installPhase = ''
    runHook preInstall

    # Both caches live in the sandbox TMPDIR, outside the source tree.
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

  # A partial install must fail here rather than publish an output missing a
  # public header, the link metadata or a licence text.
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

    # Resolve the metadata the graph wrote rather than trusting it.
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
    # Apache-2.0 is this tree's primary term; the native core's alternative
    # offer, BSL-1.0, is installed beside it. NOTICE.md is the inventory.
    license = lib.licenses.asl20;
    licenseFiles = licenseFiles;
    platforms = lib.platforms.all;
    # No `mainProgram`: the graph installs libryu, its public headers, its .pc
    # and its licence records, and no executable.
  };
}
