{
  description = "CentralCloud PostgreSQL extension packaging and CNPG image inputs";

  nixConfig = {
    extra-substituters = [
      "https://cache.centralcloud.com/default"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "default:ywfU21WX06iOn2Ec2lae1jYh4w8LO4IQkmp06vJzsk8="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nix2container,
    ...
  }: let
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems f;
    postgres18 = import ./nix/postgres18-extensions.nix {};
    src = ./.;
  in {
    overlays.default = postgres18.overlay;

    packages = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [postgres18.overlay];
          config.allowUnfree = true;
        };
        n2c = nix2container.packages.${system}.nix2container;
        arch =
          if system == "aarch64-linux"
          then "arm64"
          else "amd64";
        cnpgBase = n2c.pullImageFromManifest {
          imageName = "cloudnative-pg/postgresql";
          imageTag = "18.3-system-trixie";
          imageManifest = ./images/postgres18-cnpg/cnpg-postgresql-18.3-amd64-manifest.json;
          registryUrl = "ghcr.io";
          os = "linux";
          inherit arch;
        };
        extensionRoot = postgres18.cnpgExtensionRoot pkgs;
        cnpgImage = n2c.buildImage {
          name = "ghcr.io/singularity-ng/centralcloud-postgres";
          tag = "18-cnpg-ext";
          fromImage = cnpgBase;
          inherit arch;
          maxLayers = 32;
          copyToRoot = [extensionRoot];
          config = {
            User = "26";
            Cmd = ["bash"];
            Env = [
              "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/18/bin"
              "PIP_BREAK_SYSTEM_PACKAGES=1"
            ];
            Labels = {
              "org.opencontainers.image.title" = "CentralCloud PostgreSQL 18 CNPG Extensions";
              "org.opencontainers.image.description" = "CloudNativePG PostgreSQL 18 image with TimescaleDB, vector, BM25, AGE, and operations extensions";
              "org.opencontainers.image.source" = "https://github.com/singularity-ng/centralcloud-postgres";
              "org.opencontainers.image.licenses" = "MIT";
              "org.opencontainers.image.base.name" = "ghcr.io/cloudnative-pg/postgresql:18.3-system-trixie";
            };
          };
        };
      in {
        postgresql-18-extension-bundle = postgres18.extensionBundle pkgs;
        postgresql-18-extension-closure = postgres18.extensionClosure pkgs;
        postgresql-18-cnpg-image = cnpgImage;
        default = postgres18.extensionBundle pkgs;
      }
    );

    checks = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [postgres18.overlay];
          config.allowUnfree = true;
        };
        packages = self.packages.${system};
      in {
        format = pkgs.runCommand "format-check" {nativeBuildInputs = [pkgs.alejandra];} ''
          cp -R ${src} source
          chmod -R u+w source
          cd source
          alejandra --check flake.nix nix
          touch "$out"
        '';

        lint = pkgs.runCommand "lint-check" {nativeBuildInputs = [pkgs.deadnix pkgs.statix];} ''
          cp -R ${src} source
          chmod -R u+w source
          cd source
          statix check .
          deadnix flake.nix nix
          touch "$out"
        '';

        generated-docs = pkgs.runCommand "generated-docs-check" {nativeBuildInputs = [pkgs.python3];} ''
          cp -R ${src} source
          chmod -R u+w source
          cd source
          python scripts/generate-extension-docs.py --check
          touch "$out"
        '';

        extension-bundle = packages.postgresql-18-extension-bundle;
        cnpg-image = packages.postgresql-18-cnpg-image;
      }
    );

    devShells = forAllSystems (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [postgres18.overlay];
          config.allowUnfree = true;
        };
      in {
        default = pkgs.mkShell {
          packages = [
            pkgs.alejandra
            pkgs.deadnix
            pkgs.just
            pkgs.lefthook
            pkgs.nix
            pkgs.docker-client
            pkgs.syft
            pkgs.statix
          ];
        };
      }
    );
  };
}
