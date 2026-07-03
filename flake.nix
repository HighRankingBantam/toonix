{
  description = "NixOS + Omarchy v3.8.2 — QEMU VM (toonix) + Intel baremetal (toonix-baremetal)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-preview-share-picker = {
      url = "git+https://github.com/WhySoBad/hyprland-preview-share-picker.git?rev=344394a8669fb82ff2744d2780327dd402ffb76a&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, hyprland-preview-share-picker, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Shared base (the Omarchy port + hardware template + Home-Manager); each
      # host layers its own graphics/guest module on top via extraModules.
      mkToonix = extraModules: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit hyprland-preview-share-picker;
        };
        modules = [
          ./configuration.nix
          ./hardware-configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "hm-bak";
            home-manager.users.bantam = import ./home.nix;
          }
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = {
        # QEMU/KVM guest (virtio-gpu, software rendering) — the default target.
        toonix = mkToonix [ ];
        # Real Intel-graphics laptop — strips the VM tuning, adds Intel VAAPI so
        # GTK4 clients (walker → the Omarchy menu/launcher) render on real GPU.
        toonix-baremetal = mkToonix [ ./modules/baremetal-intel.nix ];
      };

      # `nix flake check` builds each full system closure — the validation that
      # can't run in an authoring environment. Run in CI or on any machine with Nix.
      checks.${system} = {
        toonix = self.nixosConfigurations.toonix.config.system.build.toplevel;
        toonix-baremetal =
          self.nixosConfigurations.toonix-baremetal.config.system.build.toplevel;
      };

      # `nix fmt` formats all .nix files (RFC 166 style).
      formatter.${system} = pkgs.nixfmt;

      # `nix develop` — tooling for hacking on this flake (formatter, Nix LSP,
      # linters, the `just` runner). Not needed to build/install the config.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [ just nixfmt nixd statix deadnix ];
      };
    };
}
