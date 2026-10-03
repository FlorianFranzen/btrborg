{
  description = "Back up the latest btrbk snapshots into borg repositories";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # btrfs is Linux only, and so is btrbk.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      version = lib.removeSuffix "\n" (builtins.readFile ./VERSION);
      # Mark builds from a dirty or unknown tree, like `nix build` does for
      # package versions elsewhere.
      fullVersion = if self ? rev then version else "${version}-dirty";

      mkPackage =
        pkgs:
        pkgs.callPackage ./nix/package.nix {
          version = fullVersion;
          src = self;
        };
    in
    {
      overlays.default = final: _prev: { btrborg = mkPackage final; };

      packages = forAllSystems (pkgs: {
        btrborg = mkPackage pkgs;
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.btrborg;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.btrborg;
          meta.description = "Back up the latest btrbk snapshots into borg repositories";
        };
      });

      nixosModules = {
        btrborg =
          { pkgs, ... }:
          {
            imports = [ ./nix/module.nix ];
            services.btrborg.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.btrborg;
          };
        default = self.nixosModules.btrborg;
      };

      checks = forAllSystems (pkgs: {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.btrborg;

        # Full end-to-end test in a VM: btrfs volume, btrbk snapshots, borg
        # repositories, the NixOS module and its timer.
        nixos = pkgs.testers.runNixOSTest (
          import ./nix/test.nix { btrborgModule = self.nixosModules.btrborg; }
        );

        format = pkgs.runCommand "btrborg-format-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          nixfmt --check ${self}/flake.nix ${self}/nix/*.nix
          touch "$out"
        '';
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.btrborg ];
          packages = with pkgs; [
            borgbackup
            btrbk
            nixfmt
            shellcheck
          ];
        };
      });
    };
}
