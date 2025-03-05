{
  description = "Common VM profile for NixOS systems";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }: {
    nixosModules = {
      default = import ./vm-profile.nix;
    };
  };
}
