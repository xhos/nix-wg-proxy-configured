{
  description = "VPS Proxy";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    disko,
    ...
  }: {
    nixosConfigurations.vps-proxy = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        ./configuration.nix
        ./hardware-configuration.nix # comment out if using nixos-anywhere
        # ./disko.nix # un-comment if using nixos-anywhere
      ];
    };
  };
}
