{
  description = "NixOS VM running Omarchy v3.8.2";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.nixos-vm = nixpkgs.lib.nixosSystem {
        inherit system;
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
      checks.${system}.nixos-vm =
        self.nixosConfigurations.nixos-vm.config.system.build.toplevel;

      # `nix fmt` formats all .nix files (RFC 166 style).
      formatter.${system} = pkgs.nixfmt-rfc-style;

      # `nix develop` — tooling for hacking on this flake (formatter, Nix LSP,
      # linters, the `just` runner). Not needed to build/install the config.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [ just nixfmt-rfc-style nixd statix deadnix ];
      };
    };
}
