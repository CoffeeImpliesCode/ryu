# Canonical development environment for the ryu SDK.
#
# packages: tools only. The SDK is not in the shell, because entering a shell
# must not build the library you came to work on.
#
# outputs: the same package.nix the flake builds, exposed lazily. Nothing is
# realised until `devenv build outputs.static` (or .shared) is run, so the
# shell stays cheap while the packaging route stays real.
#
# Every task below starts from this module's own directory, keeps its build
# cache and its one install prefix under the Zig cache location the caller's
# environment already names, and asks Zig for this workspace's eight jobs. No
# host path, account, mount or store path is written in this file, and no
# variable the caller exported is erased.

{ pkgs, lib, ... }:

let
  mkRyu = linkage:
    pkgs.callPackage ./package.nix {
      inherit linkage;
      zig = pkgs.zig_0_16;
    };

  # Read for its declared identity only; reading .version does not realise it.
  ryuStatic = mkRyu "static";

  # This module's own directory, and the shell-quoted form every task body
  # starts from.
  #
  # `./.` in an expression is relative to the file that contains it, so this is
  # the SDK root however devenv was invoked. It is `builtins.toString` and not
  # `"${./.}"` deliberately: interpolating a path copies it into the read-only
  # Nix store, which for this tree would be a second, frozen copy of the whole
  # SDK rather than the working tree the tasks build, install and matrix over.
  sdkRoot = builtins.toString ./.;
  sdkRootArg = lib.escapeShellArg sdkRoot;

  # The build cache and the one install prefix both sit beneath the Zig cache
  # the caller's environment already names, so a canonical run writes neither
  # `.zig-cache/` nor `zig-out/` into this repository. The path is assembled
  # here and expanded by the shell at run time, because the location is the
  # caller's rather than this file's.
  cacheDir = "$ZIG_LOCAL_CACHE_DIR/ryu";
  installPrefix = "$ZIG_LOCAL_CACHE_DIR/ryu-prefix";

  # The first lines of every task body: this SDK's own directory, then the
  # cache location the task's own `--cache-dir` is about to name.
  #
  # The fill is in the body and not only in `enterShell` because
  # `devenv tasks run --mode single` does not source the shell hook. A task that
  # reached the compiler with the variable unset would pass
  # `--cache-dir "/ryu"` — a location this file does not get to invent, and a
  # worse outcome than the SDK-local `.zig-cache` default it replaces.
  #
  # A value the caller exported is kept exactly as it is. A missing one is
  # derived from `$XDG_CACHE_HOME`, else `$TMPDIR`: where a cache belongs by the
  # Base Directory Specification, else the host's own scratch policy. With
  # neither exported the task names what is missing and stops before the
  # compiler runs. `/tmp`, `/var/tmp`, a store path and a host path are none of
  # the locations this file may supply.
  #
  # `|| exit 1` on the `cd` is not decoration: a body that continued after a
  # failed `cd` would build in, or matrix over, whatever directory the caller
  # happened to be standing in.
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
    # The global cache is the same pair and the same root. It is filled when
    # that root is known and is deliberately never a reason to stop a task over
    # a variable no command line in this file names.
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ] && [ -n "''${ryu_cache_root:-}" ]; then
      export ZIG_GLOBAL_CACHE_DIR="''${ryu_cache_root}/zig-global-cache"
      mkdir -p "$ZIG_GLOBAL_CACHE_DIR"
    fi
    unset ryu_cache_root
  '';
in
{
  # Tools only, and unconditional: the SDK package is never among them, so
  # entering the shell cannot build it. A caller who wants a different tool
  # list overrides `packages` in their own module.
  packages = [
    pkgs.zig_0_16
    pkgs.pkg-config
    pkgs.gnumake
    pkgs.git
  ];

  # `outputs`, `tasks` and `env` are top-level devenv options, so they are
  # declared at the top level too. Under a `lib.mkIf` guard they would all
  # vanish unless `devenv.yaml` set a flag, and `devenv build outputs.static`
  # would have nothing to build.
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
    # Approved local scratch, never the repository and never a small system
    # temporary filesystem. A value the caller already exported wins and is
    # never unset; only the directories this shell fills in itself are
    # created, from `$XDG_CACHE_HOME` else `$TMPDIR`, in the same order and to
    # the same sub-paths `taskPreamble` uses.
    #
    # This block is the interactive convenience, not the enforcement. It says
    # on stderr and continues when neither variable can be placed, because
    # refusing to open a shell is not this shell's decision to make;
    # `taskPreamble` is the copy that has to hold, because
    # `devenv tasks run --mode single` never reaches this block at all and the
    # command line it guards would otherwise read `--cache-dir "/ryu"`.
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

  # Namespaced: devenv puts task names on one list, and a bare `build` or
  # `test` would collide with the ordinary shell commands of the same name.
  #
  # Each body below opens with `taskPreamble`, because devenv runs a task as a
  # generated shell program that inherits the working directory of the project
  # the shell was entered from, and that project holds no `build.zig` and no
  # `cross-test.profile.sh`.
  #
  # Every real `zig build` body then carries the workspace's three flags:
  # `-j8`, an explicit `--cache-dir` outside this repository, and
  # `--summary all`. `--cache-dir` and `--prefix` keep what the run generates
  # under the local cache the caller's environment already named, so a run
  # writes neither `.zig-cache/` nor `zig-out/` here; `-j8` is this workspace's
  # job count, so a task does not silently drop to one; `--summary all` is
  # this workspace's recipe for a library build, not an optional extra.
  #
  # Only the two bodies that install anything carry `--prefix`: `build.zig:942`
  # attaches the artifact, `:957-960` the generated pkg-config file and licence
  # records and `:967` the smoke example to the install step, which is the
  # default step, so a bare `zig build` installs. `test`, `smoke` and `check`
  # depend on no install step (`build.zig:973-998`) and are given no prefix they
  # do not need. No body forwards `"$@"`: these commands never did, and a
  # devenv 2.4 task cannot receive an argument from `devenv tasks run` in any
  # case, so no forwarding is claimed here.
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
    # `cross-test` is the workspace's own tool and it owns every path it uses:
    # `cross-test.profile.sh` refuses to name a compiler cache or an output
    # directory, so this body passes it neither and only supplies a directory
    # to start from and the two job counts. `--jobs` and `--build-jobs` are
    # two separate flags with a value each, not one combined token.
    "sdk:matrix" = {
      description = "Run the full published platform matrix";
      exec = ''
        cd ${sdkRootArg} || exit 1
        cross-test --jobs 8 --build-jobs 8
      '';
    };
  };
}
