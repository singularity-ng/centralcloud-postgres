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
        # weekly CI chaos test. Day-to-day app dev should use the app repo's
        # own database workflow; this
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
        extensionRoot = postgres18.cnpgExtensionRoot pkgs "platform";
        cnpgImageConfig = {
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
        cnpgImage =
          n2c.buildImage {
            name = "registry.infra.centralcloud.com/centralcloud/centralcloud-postgres";
            tag = "18-cnpg-ext";
          }
          // cnpgImageConfig;
        cnpgImageGhcr =
          n2c.buildImage {
            name = "ghcr.io/singularity-ng/centralcloud-postgres";
            tag = "18-cnpg-ext";
          }
          // cnpgImageConfig;

        # VectorDrive owns the vector, graph, time-series, spatial, cache, and
        # metering SQL extension families. The generic VChord image remains a
        # separate product; only the non-vector shared-ops profile is shared.
        requiredVectordriveExtensions = [
          "vectordrive:vectordrive.so"
          "vectordrive_graph:vectordrive_graph.so"
          "vectordrive_timedrive:vectordrive_timedrive.so"
          "vectordrive_gis:vectordrive_gis.so"
          "cachedrive:cachedrive.so"
          "vectordrive_meter:vectordrive_meter.so"
        ];
        vectordriveCollisionControls = [
          "vector.control"
          "vchord.control"
          "vchord_bm25.control"
          "pg_tokenizer.control"
          "age.control"
          "timescaledb.control"
          "postgis.control"
        ];
        expectedSharedOpsControls = [
          "pg_cron.control"
          "pgmq.control"
          "pgaudit.control"
          "pg_repack.control"
          "pg_partman.control"
        ];
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
            for spec in ${pkgs.lib.escapeShellArgs requiredVectordriveExtensions}; do
              extension="''${spec%%:*}"
              library="''${spec#*:}"
              test -f "$src/lib/$library" || {
                echo "missing required VectorDrive library: $library" >&2
                exit 1
              }
              test -f "$src/share/extension/$extension.control" || {
                echo "missing required VectorDrive control: $extension.control" >&2
                exit 1
              }
              sql_found=
              for sql_file in "$src/share/extension/$extension"--*.sql; do
                if test -f "$sql_file"; then
                  sql_found=1
                  break
                fi
              done
              test -n "$sql_found" || {
                echo "missing required VectorDrive SQL: $extension--*.sql" >&2
                exit 1
              }
            done

            for control in ${pkgs.lib.escapeShellArgs vectordriveCollisionControls}; do
              test ! -e "$src/share/extension/$control" || {
                echo "VectorDrive extension payload duplicates excluded family: $control" >&2
                exit 1
              }
            done

            mkdir -p $out/usr/lib/postgresql/18/lib $out/usr/share/postgresql/18/extension
            cp -v $src/lib/*.so $out/usr/lib/postgresql/18/lib/
            cp -v $src/share/extension/* $out/usr/share/postgresql/18/extension/
          '';
        };
        sharedOpsRoot = assert pkgs.lib.assertMsg
        (postgres18.extensionProfileControls.shared-ops == expectedSharedOpsControls)
        "shared-ops must contain only the five approved non-vector operational extensions";
          postgres18.cnpgExtensionRoot pkgs "shared-ops";
        cnpgImageVd = n2c.buildImage {
          # vectordrive is a singularity-ng product; image is namespaced by the
          # product org (matches the cluster + the live registry repo), even
          # though it is built by centralcloud-postgres (a centralcloud-org repo).
          name = "registry.infra.centralcloud.com/singularity-ng/vectordrive-postgres";
          tag = "18-cnpg";
          fromImage = cnpgBase;
          inherit arch;
          maxLayers = 32;
          copyToRoot = [vectordriveExtension sharedOpsRoot];
          config = {
            User = "26";
            Cmd = ["bash"];
            Env = [
              "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/lib/postgresql/18/bin"
              "PIP_BREAK_SYSTEM_PACKAGES=1"
            ];
            Labels = {
              "org.opencontainers.image.title" = "VectorDrive PostgreSQL 18 (CNPG)";
              "org.opencontainers.image.description" = "CNPG PG18 with six VectorDrive-owned SQL extensions plus non-vector shared operations extensions; no VChord, pgvector, AGE, TimescaleDB, or PostGIS";
              "org.opencontainers.image.source" = "https://git.infra.centralcloud.com/singularity-ng/vectordrive";
              "org.opencontainers.image.licenses" = "MIT";
              "org.opencontainers.image.base.name" = "ghcr.io/cloudnative-pg/postgresql:18.4-system-trixie";
              "org.centralcloud.postgres.extension-profile" = "vectordrive+shared-ops";
            };
          };
        };
      in {
        postgresql-18-extension-bundle = postgres18.extensionBundle pkgs "platform";
        postgresql-18-extension-closure = postgres18.extensionClosure pkgs;
        postgresql-18-cnpg-image = cnpgImage;
        postgresql-18-cnpg-image-ghcr = cnpgImageGhcr;
        postgresql-18-cnpg-image-vd = cnpgImageVd;
        vectordrive-extension-layer = vectordriveExtension;
        centralcloud-postgres-dev-cluster = devCluster;
        default = postgres18.extensionBundle pkgs "platform";
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

        workflows = pkgs.runCommand "workflow-lint-check" {nativeBuildInputs = [pkgs.actionlint];} ''
          cp -R ${src} source
          chmod -R u+w source
          cd source
          shopt -s nullglob
          files=(.forgejo/workflows/*.{yml,yaml} .github/workflows/*.{yml,yaml})
          if [ "''${#files[@]}" -gt 0 ]; then
            actionlint -config-file .github/actionlint.yaml "''${files[@]}"
          fi
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
            pkgs.actionlint
            pkgs.alejandra
            pkgs.deadnix
            pkgs.just
            pkgs.jq
            pkgs.lefthook
            pkgs.nix
            pkgs.python3
            pkgs.shellcheck
            pkgs.statix
            devCluster
          ];

          shellHook = ''
            echo "CentralCloud Postgres dev shell (nixos-26.05)"
            echo "  just check         # nix flake check (format, lint, image)"
            echo "  just install-hooks # lefthook (also auto on first nix develop)"
            echo "  just cluster-up    # k3d + CNPG (same image digest as prod)"
            echo "  just cluster-down  # tear down"
            echo "  just cluster-chaos # boot + kill primary once ready"
            if [ -n "''${LEFTHOOK_AUTOINSTALL:-}" ] && [ "''$LEFTHOOK_AUTOINSTALL" = "0" ]; then
              :
            elif [ -d .git ] && [ -f lefthook.yml ] && [ ! -f .git/.lefthook-autoinstalled ] && [ -t 0 ]; then
              if lefthook install 2>/dev/null; then
                touch .git/.lefthook-autoinstalled
                echo "lefthook: git hooks installed (run \`lefthook run pre-commit\` to test)"
              fi
            fi
          '';
        };
      }
    );

    formatter = forAllSystems (system: (import nixpkgs {inherit system;}).alejandra);
  };
}
