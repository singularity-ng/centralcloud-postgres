_: let
  extensionOverlay = _final: prev: {
    postgresql_18 = prev.postgresql_18.overrideAttrs (oldAttrs: {
      passthru =
        oldAttrs.passthru
        // {
          pkgs =
            oldAttrs.passthru.pkgs
            // {
              age = prev.postgresql_18.pkgs.age.overrideAttrs (ageOld: {
                version = "1.7.0-rc0";
                src = prev.fetchFromGitHub {
                  owner = "apache";
                  repo = "age";
                  tag = "PG18/v1.7.0-rc0";
                  hash = "sha256-Hqjg62YLTLEa6wRA5S4MAIED7Hobtiih4E55cSzVTqE=";
                };
                meta =
                  ageOld.meta
                  // {
                    broken = false;
                  };
              });

              "vchord-bm25" = prev.stdenv.mkDerivation {
                pname = "vchord-bm25";
                version = "0.3.0";

                src = prev.fetchurl {
                  url = "https://github.com/tensorchord/VectorChord-bm25/releases/download/0.3.0/postgresql-18-vchord-bm25_0.3.0_x86_64-linux-gnu.zip";
                  sha256 = "532a2f9cd197281cf12252314154bb99d9e23c83069a54239f30a2ea61aef57d";
                };

                nativeBuildInputs = [prev.unzip];

                unpackPhase = ''
                  unzip $src
                '';

                installPhase = ''
                  mkdir -p $out/lib $out/share/postgresql/extension
                  install -m 755 vchord_bm25.so $out/lib/
                  install -m 644 vchord_bm25.control $out/share/postgresql/extension/
                  install -m 644 *.sql $out/share/postgresql/extension/
                '';

                meta = {
                  description = "BM25 ranking for PostgreSQL via VectorChord";
                  homepage = "https://github.com/tensorchord/VectorChord-bm25";
                  license = prev.lib.licenses.agpl3Only;
                  platforms = ["x86_64-linux"];
                };
              };

              "pg-tokenizer" = prev.stdenv.mkDerivation {
                pname = "pg-tokenizer";
                version = "0.1.1";

                src = prev.fetchurl {
                  url = "https://github.com/tensorchord/pg_tokenizer.rs/releases/download/0.1.1/postgresql-18-pg-tokenizer_0.1.1_x86_64-linux-gnu.zip";
                  sha256 = "42bccb95b46933c060861e7f3b371ed4c6dc3ec3b454c72fbea85c3e1aaf5d52";
                };

                nativeBuildInputs = [prev.unzip prev.autoPatchelfHook];
                buildInputs = [prev.stdenv.cc.cc.lib];

                unpackPhase = ''
                  unzip $src
                '';

                installPhase = ''
                  mkdir -p $out/lib $out/share/postgresql/extension
                  install -m 755 pg_tokenizer.so $out/lib/
                  install -m 644 pg_tokenizer.control $out/share/postgresql/extension/
                  install -m 644 *.sql $out/share/postgresql/extension/
                '';

                meta = {
                  description = "Tokenization for PostgreSQL BM25";
                  homepage = "https://github.com/tensorchord/pg_tokenizer.rs";
                  license = prev.lib.licenses.agpl3Only;
                  platforms = ["x86_64-linux"];
                };
              };

              pgaudit = oldAttrs.passthru.pkgs.callPackage ./pgaudit-pg18.nix {};
            };
        };
    });
  };

  extensionPackages = pkgs:
    with pkgs.postgresql_18.pkgs; [
      timescaledb
      pgvector
      vectorchord
      vchord-bm25
      pg-tokenizer
      age
      pgmq
      pg_cron
      pg_repack
      pg_partman
      hypopg
      pg_hint_plan
      plpgsql_check
      rum
      pgaudit
    ];
  extensionBundle = pkgs:
    pkgs.runCommand "postgresql-18-extension-bundle" {
      nativeBuildInputs = [pkgs.coreutils];
    } ''
      mkdir -p "$out/lib" "$out/share/postgresql/extension"

      for pkg in ${pkgs.lib.escapeShellArgs (extensionPackages pkgs)}; do
        if [ -d "$pkg/lib" ]; then
          cp -R --no-preserve=mode,ownership "$pkg/lib/." "$out/lib/"
        fi
        if [ -d "$pkg/share/postgresql/extension" ]; then
          cp -R --no-preserve=mode,ownership "$pkg/share/postgresql/extension/." "$out/share/postgresql/extension/"
        fi
      done

      cp ${../extensions.json} "$out/extensions.json"
    '';
in {
  overlay = extensionOverlay;

  inherit extensionPackages extensionBundle;

  cnpgExtensionRoot = pkgs: let
    bundle = extensionBundle pkgs;
    deb = url: hash:
      pkgs.fetchurl {
        inherit url hash;
      };
    debianPlpythonPackages = [
      (deb
        "https://apt.postgresql.org/pub/repos/apt/pool/main/p/postgresql-18/postgresql-plpython3-18_18.4-1.pgdg13%2b1_amd64.deb"
        "sha256-SAOk+0OCbQFa9QnDttIIuo9YS+eiwV8Ej96pLRZNieo=")
      (deb
        "http://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13_3.13.5-2%2bdeb13u2_amd64.deb"
        "sha256-eS0OXipxP/TRXWWOYurPNJ7AhU7TKc7LFYRYttNEm2s=")
      (deb
        "http://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13-stdlib_3.13.5-2%2bdeb13u2_amd64.deb"
        "sha256-V/91n9rYxaocyb/dJfa9eGLg5YVMl+c5EFB0p7x6vCM=")
      (deb
        "http://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13-minimal_3.13.5-2%2bdeb13u2_amd64.deb"
        "sha256-8ZZDOk7vbX9OcNRXYcWOxqWeeYK59oPUUtxoOAI1UcU=")
      (deb
        "http://deb.debian.org/debian/pool/main/p/python3.13/python3.13_3.13.5-2%2bdeb13u2_amd64.deb"
        "sha256-iC5Cj6EI335I7Wfu0If2W2A8VMC6mdCaIwc5ZvR8O4s=")
      (deb
        "http://deb.debian.org/debian/pool/main/p/python3.13/python3.13-minimal_3.13.5-2%2bdeb13u2_amd64.deb"
        "sha256-9ZXsiiST4V6s8N0VAgV3gs570cw0Rkc9vMicNCgkYtY=")
    ];
  in
    pkgs.runCommand "postgresql-18-cnpg-extension-root" {
      nativeBuildInputs = [pkgs.dpkg pkgs.patchelf];
    } ''
      mkdir -p "$out/usr/lib/postgresql/18/lib" "$out/usr/share/postgresql/18/extension"
      cp -R --no-preserve=mode,ownership "${bundle}/lib/." \
        "$out/usr/lib/postgresql/18/lib/"
      cp -R --no-preserve=mode,ownership "${bundle}/share/postgresql/extension/." \
        "$out/usr/share/postgresql/18/extension/"
      cp "${bundle}/extensions.json" \
        "$out/usr/share/postgresql/18/extension/centralcloud-extensions.json"

      for deb in ${pkgs.lib.escapeShellArgs debianPlpythonPackages}; do
        dpkg-deb -x "$deb" "$out"
      done

      # The CNPG base image already ships PostgreSQL and libpq. Extensions
      # copied from Nix must not keep Nix-store RPATHs to libpq/glibc, or the
      # Debian runtime can fail loading them when glibc versions diverge.
      for so in "$out"/usr/lib/postgresql/18/lib/*.so; do
        if patchelf --print-rpath "$so" >/dev/null 2>&1; then
          patchelf --remove-rpath "$so" || true
        fi
      done
    '';

  extensionClosure = pkgs:
    pkgs.buildEnv {
      name = "postgresql-18-extension-closure";
      paths = [pkgs.postgresql_18] ++ extensionPackages pkgs;
    };
}
