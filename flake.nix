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
    # Align with /srv/infra hosts pinned to nixos-26.05. Stable channel gets
    # CVE backports; matches OS-level glibc/toolchain on the cluster nodes
    # this image runs on (cc-de-fsn-core-01, cc-fi-hel-core-01).
    # Previously nixos-unstable — bumped 2026-05-25 for fleet consistency.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
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
        # Local CNPG dev cluster (k3d + CNPG operator). Source of truth
        # for the cluster spec, image digest, and operator version.
        # Used by centralcloud-ops dev shell (delegates here) and by the
        # weekly CI chaos test. Day-to-day dev uses plain docker; this
        # is opt-in for replication/failover work.
        devCluster = pkgs.writeShellApplication {
          name = "centralcloud-postgres-dev-cluster";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            gnused
            gawk
            k3d
            kubectl
            kubernetes-helm
          ];
          text = builtins.readFile ./scripts/dev-cluster.sh;
        };
        arch =
          if system == "aarch64-linux"
          then "arm64"
          else "amd64";
        cnpgBase = n2c.pullImageFromManifest {
          imageName = "cloudnative-pg/postgresql";
          imageTag = "18.4-system-trixie";
          imageManifest = ./images/postgres18-cnpg/cnpg-postgresql-18.4-amd64-manifest.json;
          registryUrl = "ghcr.io";
          os = "linux";
          inherit arch;
        };
        extensionRoot = postgres18.cnpgExtensionRoot pkgs;
        cnpgImage = n2c.buildImage {
          name = "registry.infra.centralcloud.com/centralcloud/centralcloud-postgres";
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
              "org.opencontainers.image.source" = "https://git.infra.centralcloud.com/centralcloud/centralcloud-postgres";
              "org.opencontainers.image.licenses" = "MIT";
              "org.opencontainers.image.base.name" = "ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie";
            };
          };
        };

        # VectorDrive extension layer.
        # Reads pre-built pgrx outputs from VECTORDRIVE_EXT_PATH. Producing
        # these outputs is a separate step: `nix develop` inside the
        # vectordrive repo, then
        # `cd crates/postgres/core && cargo pgrx install
        # --features pg18,default-profiles,routing --release` and copy the
        # resulting .so/.control/.sql files into a path passed via
        # VECTORDRIVE_EXT_PATH. Without that override, pure flake checks use
        # an empty local placeholder so this optional image remains evaluable.
        vectordriveExtPath = let
          envPath = builtins.getEnv "VECTORDRIVE_EXT_PATH";
        in
          if envPath != ""
          then envPath
          else toString ./nix/vectordrive-ext-placeholder;
        vectordriveExtension = pkgs.stdenv.mkDerivation {
          pname = "vectordrive-postgres-extension";
          version = "1.1.0";
          src = builtins.path {
            path = /. + vectordriveExtPath;
            filter = _path: _type: true;
          };
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/usr/lib/postgresql/18/lib $out/usr/share/postgresql/18/extension
            for so in $src/lib/*.so; do
              [ -e "$so" ] && cp -v "$so" $out/usr/lib/postgresql/18/lib/
            done
            for f in $src/share/extension/*; do
              [ -e "$f" ] && cp -v "$f" $out/usr/share/postgresql/18/extension/
            done
          '';
        };
        # Slim CNPG image with ONLY the VectorDrive pgrx extension layered on
        # top of the bare upstream CNPG base. Skips timescaledb / vchord /
        # vchord_bm25 / pg_tokenizer / age / pgmq / etc — VectorDrive supplies
        # its own vector + sparse types via pgrx (sparsevec_in_wrapper etc).
        # Add to `extraExtensionLayers` below if a deployment turns out to need
        # a specific extra extension; do not blanket-include the full bundle.
        extraExtensionLayers = [];
        cnpgImageVd = n2c.buildImage {
          # vectordrive is a singularity-ng product; image is namespaced by the
          # product org (matches the cluster + the live registry repo), even
          # though it is built by centralcloud-postgres (a centralcloud-org repo).
          name = "registry.infra.centralcloud.com/singularity-ng/vectordrive-postgres";
          tag = "18-cnpg";
          fromImage = cnpgBase;
          inherit arch;
          maxLayers = 32;
          copyToRoot = [vectordriveExtension] ++ extraExtensionLayers;
          config = {
            User = "26";
            Cmd = ["bash"];
            Env = [
              "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/18/bin"
              "PIP_BREAK_SYSTEM_PACKAGES=1"
            ];
            Labels = {
              "org.opencontainers.image.title" = "VectorDrive PostgreSQL 18 (CNPG)";
              "org.opencontainers.image.description" = "Slim CNPG PG18 + VectorDrive pgrx extension (vectordrive_code_search + 377 SQL functions, own halfvec/sparsevec, no vchord/timescaledb)";
              "org.opencontainers.image.source" = "https://git.infra.centralcloud.com/singularity-ng/vectordrive";
              "org.opencontainers.image.licenses" = "MIT";
              "org.opencontainers.image.base.name" = "ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie";
            };
          };
        };
      in {
        postgresql-18-extension-bundle = postgres18.extensionBundle pkgs;
        postgresql-18-extension-closure = postgres18.extensionClosure pkgs;
        postgresql-18-cnpg-image = cnpgImage;
        postgresql-18-cnpg-image-vd = cnpgImageVd;
        vectordrive-extension-layer = vectordriveExtension;
        centralcloud-postgres-dev-cluster = devCluster;
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
        devCluster = self.packages.${system}.centralcloud-postgres-dev-cluster;
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
            pkgs.k3d
            pkgs.kubectl
            devCluster
          ];

          shellHook = ''
            echo "CentralCloud Postgres dev shell"
            echo "  just cluster-up    # k3d + CNPG (same image digest as prod)"
            echo "  just cluster-down  # tear down"
            echo "  just cluster-chaos # boot + kill primary once ready"
          '';
        };
      }
    );
  };
}
