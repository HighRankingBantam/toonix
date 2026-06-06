{
  description = "NixOS VM running Omarchy v3.8.2";

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
    in
    {
      nixosConfigurations.toonix = nixpkgs.lib.nixosSystem {
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
        ];
      };

      # `nix flake check` builds the full system closure — i.e. a real
      # eval+build of the whole config (the validation I can't run in this
      # authoring environment; run it in CI or on any machine with Nix).
      checks.${system}.toonix =
        self.nixosConfigurations.toonix.config.system.build.toplevel;

      # `nix fmt` formats all .nix files (RFC 166 style).
      formatter.${system} = pkgs.nixfmt;

      # `nix develop` — tooling for hacking on this flake (formatter, Nix LSP,
      # linters, the `just` runner). Not needed to build/install the config.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [ just nixfmt nixd statix deadnix ];
      };
    };
}
