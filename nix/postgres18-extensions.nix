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
  in
    pkgs.runCommand "postgresql-18-cnpg-extension-root" {} ''
      mkdir -p "$out/usr/lib/postgresql/18/lib" "$out/usr/share/postgresql/18/extension"
      cp -R --no-preserve=mode,ownership "${bundle}/lib/." \
        "$out/usr/lib/postgresql/18/lib/"
      cp -R --no-preserve=mode,ownership "${bundle}/share/postgresql/extension/." \
        "$out/usr/share/postgresql/18/extension/"
      cp "${bundle}/extensions.json" \
        "$out/usr/share/postgresql/18/extension/centralcloud-extensions.json"
    '';

  extensionClosure = pkgs:
    pkgs.buildEnv {
      name = "postgresql-18-extension-closure";
      paths = [pkgs.postgresql_18] ++ extensionPackages pkgs;
    };
}
