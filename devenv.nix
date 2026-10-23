
{ pkgs, lib, ... }:

let
  mkRyu = linkage:
    pkgs.callPackage ./package.nix {
      inherit linkage;
      zig = pkgs.zig_0_17;
    };

  # Read the package version without realizing its derivation.
  ryuStatic = mkRyu "static";

  # Keep the path relative to this file; interpolation would copy the SDK into the store.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # Place build output and install prefix under the caller's Zig cache.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/ryu";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/ryu-prefix";

  # Set the package cwd and derive cache paths only from caller-provided roots.
  # Preserve exported cache variables; fail before building if no local cache root exists.
  # A failed `cd` must stop the task before it builds from another directory.
  taskPreamble = ''
    cd ${sdkRootArg} || exit 1
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ryu_cache_root="''${XDG_CACHE_HOME}"
      elif [ -n "''${TMPDIR:-}" ]; then
        ryu_cache_root="''${TMPDIR}"
      else
        echo "ryu devenv: no Zig cache location is known here. Export" >&2
        echo "ZIG_LOCAL_CACHE_DIR, or XDG_CACHE_HOME, or TMPDIR, at an approved" >&2
        echo "mount and run this task again; no location is chosen here." >&2
        exit 1
      fi
      export ZIG_LOCAL_CACHE_DIR="''${ryu_cache_root}/zig-local-cache"
      mkdir -p "$ZIG_LOCAL_CACHE_DIR"
    fi
    # Fill the global cache when its root is known; it is optional.
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] && [ -n "''${ryu_cache_root:-}" ]; then
      export ZIG_GLOBAL_CACHE_DIR="''${ryu_cache_root}/zig-global-cache"
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
    unset ryu_cache_root
  '';
in
{
  # Tools only; entering the shell must not build the SDK.
  packages = [
    pkgs.zig_0_17
    pkgs.pkg-config
    pkgs.gnumake
    pkgs.git
  ];

  # Declare devenv options at top level so they remain available.
  outputs = {
    static = ryuStatic;
    shared = mkRyu "dynamic";
    default = ryuStatic;
  };

  env = {
    RYU_SDK_NAME = "ryu";
    RYU_SDK_VERSION = ryuStatic.version;
  };

  enterShell = ''
    # Interactive cache setup is optional; tasks enforce their own setup.
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ryu_cache_root="''${XDG_CACHE_HOME}"
      elif [ -n "''${TMPDIR:-}" ]; then
        ryu_cache_root="''${TMPDIR}"
      else
        echo "ryu devenv: XDG_CACHE_HOME and TMPDIR are both unset, so no Zig" >&2
        echo "cache location is chosen here. Export ZIG_LOCAL_CACHE_DIR and" >&2
        echo "ZIG_GLOBAL_CACHE_DIR at an approved mount." >&2
        ryu_cache_root=
      fi
      if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] && [ -n "''${ryu_cache_root}" ]; then
        ZIG_LOCAL_CACHE_DIR="''${ryu_cache_root}/zig-local-cache"
        export ZIG_LOCAL_CACHE_DIR
        mkdir -p "$ZIG_LOCAL_CACHE_DIR"
      fi
      if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] && [ -n "''${ryu_cache_root}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${ryu_cache_root}/zig-global-cache"
        export ZIG_GLOBAL_CACHE_DIR
        mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
      fi
      unset ryu_cache_root
    fi

    echo "ryu SDK development environment"
    echo "  sdk:       $RYU_SDK_NAME $RYU_SDK_VERSION"
    echo "  compiler:  $(zig version)"
    echo "  licence:   Apache-2.0 OR BSL-1.0 native core, Apache-2.0 fork files (NOTICE.md, FORK-LICENSE.md)"
    echo "  build:     zig build | zig build test | zig build smoke | zig build check"
    echo "  matrix:    cross-test --jobs 8 --build-jobs 8"
    echo "  linkage:   zig build -Dlinkage=static | -Dlinkage=dynamic"
    echo "  optional:  zig build -Dgeneric128=true"
    echo "  package:   devenv build outputs.static | devenv build outputs.shared"
    echo "  tasks:     devenv tasks run sdk:build | sdk:test | sdk:smoke | sdk:check"
    echo "             sdk:install | sdk:matrix"
    echo "  cache:     ZIG_LOCAL_CACHE_DIR/ryu, ZIG_LOCAL_CACHE_DIR/ryu-prefix"
  '';

  # Namespace tasks to avoid shell-command collisions.
  # Each task starts at the package root; only build/install tasks pass a prefix.
  tasks = {
    "sdk:build" = {
      description = "Build the C library and compile the smoke example under $ZIG_LOCAL_CACHE_DIR";
      exec = ''
        ${taskPreamble}
        zig build --cache-dir "${cacheDir}" --prefix "${installPrefix}" -j8 --summary all
      '';
    };
    "sdk:test" = {
      description = "Run the behavioural tests";
      exec = ''
        ${taskPreamble}
        zig build test --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };
    "sdk:smoke" = {
      description = "Run the deterministic smoke example";
      exec = ''
        ${taskPreamble}
        zig build smoke --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };
    "sdk:check" = {
      description = "Compile for the six-target matrix, running nothing";
      exec = ''
        ${taskPreamble}
        zig build check --cache-dir "${cacheDir}" -j8 --summary all
      '';
    };
    "sdk:install" = {
      description = "Install the library and public headers under $ZIG_LOCAL_CACHE_DIR";
      exec = ''
        ${taskPreamble}
        zig build install --cache-dir "${cacheDir}" --prefix "${installPrefix}" -j8 --summary all
      '';
    };
    "sdk:matrix" = {
      description = "Run the full published platform matrix";
      exec = ''
        cd ${sdkRootArg} || exit 1
        cross-test --jobs 8 --build-jobs 8
      '';
    };
  };
}
