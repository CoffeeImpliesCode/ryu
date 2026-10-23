
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
        # Build natively; build.zig receives no cross-target override.
        assert pkgs.stdenv.hostPlatform.system == pkgs.stdenv.buildPlatform.system;
        # Keep the selected compiler at Zig 0.16.0.
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
