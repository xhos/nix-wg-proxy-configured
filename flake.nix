{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forEachSystem = nixpkgs.lib.genAttrs systems;

    commonConfig = import ./config.nix;

    mkHost = hostName:
      nixpkgs.lib.nixosSystem {
        specialArgs = {
          hostConfig = commonConfig // (import ./hosts/${hostName}/configuration.nix);
        };
        modules = [
          ./proxy.nix
          ./hosts/${hostName}/hardware-configuration.nix
        ];
      };
  in {
    formatter = forEachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    nixosConfigurations = {
      proxy-1 = mkHost "proxy-1";
      proxy-2 = mkHost "proxy-2";
    };
  };
}
