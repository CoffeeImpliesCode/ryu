# Nix packages for the ryu SDK. package.nix is the derivation; this file names
# the variants, pins one nixpkgs revision and offers a tools-only shell.
#
# default is static: this SDK's existing policy, and upstream's CMake default.
# -Dgeneric128 is a build-graph option, not a packaging variant, so it has no
# flake attribute; pass it through `zig build -Dgeneric128=true`.
#
# No flake.lock: the lock is the workspace driver's. Without one a git flake has
# nothing to fetch, so use path:. until the tree is committed.

{
  description = "Ryu: shortest, fixed and scientific IEEE-754 to decimal conversion, as a Zig-buildable SDK";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
        "x86_64-windows"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs:
        # Nix cross-compilation is not supported: `zig build` runs without
        # -Dtarget, so a cross derivation would install the build machine's
        # native library under the host's name. Remote native builders stay
        # valid, which is why this compares the two platforms rather than
        # naming a system.
        assert pkgs.stdenv.hostPlatform.system == pkgs.stdenv.buildPlatform.system;
        # Guards the compiler this SDK is pinned to; `zig_0_16` could be
        # repointed by a future nixpkgs without the attribute name changing.
        assert pkgs.zig_0_16.version == "0.16.0";
        let
          mkRyu = linkage:
            pkgs.callPackage ./package.nix {
              inherit linkage;
              zig = pkgs.zig_0_16;
            };
        in
        {
          static = mkRyu "static";
          shared = mkRyu "dynamic";
          default = mkRyu "static";
        });

      # Tools only: entering a shell must not build the SDK.
      devShells = forAllSystems (pkgs:
        assert pkgs.zig_0_16.version == "0.16.0";
        {
          default = pkgs.mkShell {
            name = "ryu-sdk";

            packages = with pkgs; [ zig_0_16 pkg-config gnumake git ];

            shellHook = ''
              echo "ryu SDK development shell"
              echo "  compiler:   $(zig version)"
              echo "  build:      zig build | zig build test | zig build smoke | zig build check"
              echo "  matrix:     cross-test          (full published platform table)"
              echo "  linkage:    zig build -Dlinkage=static | -Dlinkage=dynamic"
              echo "  optional:   zig build -Dgeneric128=true"
              echo "  package:    nix build path:.#static | nix build path:.#shared"
            '';
          };
        });
    };
}
