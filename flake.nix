{
  description = "OmniOS - AI Native OS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk.url = "github:nix-community/naersk/master";
  };

  outputs = { self, nixpkgs, nixos-generators, naersk, ... }: 
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
    naersk-lib = pkgs.callPackage naersk { };
    
  in 
  {
    packages.x86_64-linux = {
      # Wirtualna Maszyna do testów
      run-vm = nixos-generators.nixosGenerate {
        system = system;
        format = "vm";
        modules = [
          ./configuration.nix
        ];
      };

      # Obraz ISO do instalacji
      install-iso = nixos-generators.nixosGenerate {
        system = system;
        format = "install-iso";
        modules = [
          ./configuration.nix
        ];
      };
    };
  };
}