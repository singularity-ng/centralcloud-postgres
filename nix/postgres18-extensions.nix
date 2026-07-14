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

              pg_duckdb = prev.stdenv.mkDerivation {
                pname = "pg_duckdb";
                version = "1.1.1";

                src = prev.fetchFromGitHub {
                  owner = "duckdb";
                  repo = "pg_duckdb";
                  tag = "v1.1.1";
                  hash = "sha256-0cNfDZkd6x45xpWyPMfFoYAklE+4lAjO02SjV+V/dxU=";
                };

                nativeBuildInputs = [
                  prev.clang
                  prev.cmake
                  prev.pkg-config
                ];

                buildInputs = [
                  prev.postgresql_18
                  prev.curl
                  prev.duckdb
                  prev.lz4
                  prev.openssl
                  prev.zlib
                ];

                dontConfigure = true;

                postPatch = ''
                  rm -rf third_party/duckdb
                  cp -R ${prev.duckdb.src} third_party/duckdb
                  chmod -R u+w third_party/duckdb
                  mkdir -p .git/modules/third_party/duckdb third_party/duckdb/build/release/src
                  touch .git/modules/third_party/duckdb/HEAD
                  ln -s ${prev.duckdb}/lib/libduckdb.so third_party/duckdb/build/release/src/libduckdb.so
                  substituteInPlace Makefile \
                    --replace-fail '$(shlib): $(FULL_DUCKDB_LIB) $(OBJS)' '$(shlib): $(OBJS)' \
                    --replace-fail 'install-duckdb: $(FULL_DUCKDB_LIB) $(shlib)' 'install-duckdb: $(shlib)'
                  sed -i '/#include "duckdb.hpp"/a #include "duckdb/main/extension_callback_manager.hpp"' src/pgduckdb_duckdb.cpp
                  substituteInPlace src/pgduckdb_duckdb.cpp \
                    --replace-fail 'config.options.ddb_option_name = duckdb_##ddb_option_name;' 'config.SetOptionByName(#ddb_option_name, duckdb_##ddb_option_name);' \
                    --replace-fail 'dbconfig.storage_extensions["pgduckdb"] = duckdb::make_uniq<PostgresStorageExtension>();' 'duckdb::StorageExtension::Register(dbconfig, "pgduckdb", duckdb::make_shared_ptr<PostgresStorageExtension>());' \
                    --replace-fail 'dbconfig.optimizer_extensions.push_back(UnsupportedTypeOptimizer::GetOptimizerExtension());' 'duckdb::OptimizerExtension::Register(dbconfig, UnsupportedTypeOptimizer::GetOptimizerExtension());'
                '';

                buildPhase = ''
                  runHook preBuild
                  make PG_CONFIG=${prev.postgresql_18.pg_config}/bin/pg_config DUCKDB_BUILD=Release
                  runHook postBuild
                '';

                makeFlags = [
                  "PG_CONFIG=${prev.postgresql_18.pg_config}/bin/pg_config"
                  "DUCKDB_BUILD=Release"
                ];

                installPhase = ''
                  mkdir -p $out/lib $out/share/postgresql/extension
                  install -m 755 pg_duckdb.so $out/lib/
                  install -m 644 pg_duckdb.control $out/share/postgresql/extension/
                  install -m 644 sql/pg_duckdb--*.sql $out/share/postgresql/extension/
                '';

                meta = {
                  description = "DuckDB-powered PostgreSQL for high-performance OLAP analytics in-process";
                  homepage = "https://github.com/duckdb/pg_duckdb";
                  license = prev.lib.licenses.mit;
                  platforms = ["x86_64-linux" "aarch64-linux"];
                };
              };

              wrappers = let
                arch =
                  if prev.stdenv.hostPlatform.isAarch64
                  then "arm64"
                  else "amd64";
                hashes = {
                  amd64 = "0fxyszn1q4ih0iqmv3yzlnp4aga8j9yhrsmymh170niryjj67pcf";
                  arm64 = "1bmj1zdffg0sz7l4w1hj4s4cvrr4pn7kgqjk75wp7dn5m7l0fzgx";
                };
              in
                prev.stdenv.mkDerivation {
                  pname = "wrappers";
                  version = "0.6.2";

                  src = prev.fetchurl {
                    url = "https://github.com/supabase/wrappers/releases/download/v0.6.2/wrappers-v0.6.2-pg18-${arch}-linux-gnu.deb";
                    sha256 = hashes.${arch};
                  };

                  nativeBuildInputs = [prev.dpkg prev.autoPatchelfHook];
                  buildInputs = [prev.stdenv.cc.cc.lib prev.openssl];

                  unpackPhase = "dpkg-deb -x $src .";

                  installPhase = ''
                    mkdir -p $out/lib $out/share/postgresql/extension
                    cp -rL usr/lib/postgresql/18/lib/. $out/lib/ 2>/dev/null || true
                    cp -rL usr/share/postgresql/18/extension/. $out/share/postgresql/extension/ 2>/dev/null || true
                  '';

                  meta = {
                    description = "Supabase FDW wrappers — S3, Stripe, Firebase, Airtable, BigQuery and more as foreign tables";
                    homepage = "https://github.com/supabase/wrappers";
                    license = prev.lib.licenses.asl20;
                    platforms = ["x86_64-linux" "aarch64-linux"];
                  };
                };
            };
        };
    });
  };

  extensionPackageProfiles = pkgs:
    with pkgs.postgresql_18.pkgs; {
      platform = [
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
        pg_ivm
        pg_duckdb
        wrappers
        hypopg
        pg_hint_plan
        plpgsql_check
        rum
        pgaudit
      ];
      search = [
        pgvector
        vectorchord
        vchord-bm25
        pg-tokenizer
        rum
      ];
      federation = [
        wrappers
      ];
      python = [];
      analytics = [
        pg_ivm
        wrappers
        hypopg
        pg_hint_plan
        plpgsql_check
        rum
      ];
      # Non-vector operational extensions shared by both fleet images.
      shared-ops = [
        pg_cron
        pgmq
        pgaudit
        pg_repack
        pg_partman
      ];
      experimental = [
        pg_duckdb
      ];
    };
  extensionProfileControls = {
    platform = [
      "timescaledb.control"
      "vector.control"
      "vchord.control"
      "vchord_bm25.control"
      "pg_tokenizer.control"
      "age.control"
      "pgmq.control"
      "pg_cron.control"
      "pg_repack.control"
      "pg_partman.control"
      "pg_ivm.control"
      "pg_duckdb.control"
      "wrappers.control"
      "hypopg.control"
      "pg_hint_plan.control"
      "plpgsql_check.control"
      "rum.control"
      "pgaudit.control"
      "plpython3u.control"
    ];
    search = [
      "vector.control"
      "vchord.control"
      "vchord_bm25.control"
      "pg_tokenizer.control"
      "rum.control"
    ];
    analytics = [
      "pg_ivm.control"
      "wrappers.control"
      "hypopg.control"
      "pg_hint_plan.control"
      "plpgsql_check.control"
      "rum.control"
    ];
    shared-ops = [
      "pg_cron.control"
      "pgmq.control"
      "pgaudit.control"
      "pg_repack.control"
      "pg_partman.control"
    ];
    federation = [
      "wrappers.control"
    ];
    python = [
      "plpython3u.control"
    ];
  };
  extensionPackages = pkgs: (extensionPackageProfiles pkgs).platform;
  extensionBundle = pkgs: profile:
    pkgs.runCommand "postgresql-18-extension-bundle" {
      nativeBuildInputs = [pkgs.coreutils];
    } ''
      mkdir -p "$out/lib" "$out/share/postgresql/extension"

      for pkg in ${pkgs.lib.escapeShellArgs (extensionPackageProfiles pkgs).${profile}}; do
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

  inherit extensionPackageProfiles extensionProfileControls extensionPackages extensionBundle;

  cnpgExtensionRoot = pkgs: profile: let
    bundle = extensionBundle pkgs profile;
    deb = url: hash:
      pkgs.fetchurl {
        inherit url hash;
      };
    debianPlpythonPackages = [
      (deb
        "https://apt.postgresql.org/pub/repos/apt/pool/main/p/postgresql-18/postgresql-plpython3-18_18.4-1.pgdg13%2b1_amd64.deb"
        "sha256-SAOk+0OCbQFa9QnDttIIuo9YS+eiwV8Ej96pLRZNieo=")
      (deb
        "https://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13_3.13.5-2%2bdeb13u3_amd64.deb"
        "sha256-Dfel2aHE1YNKq3WU867pb/gKF+gREDcKc+f4BKCtF0c=")
      (deb
        "https://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13-stdlib_3.13.5-2%2bdeb13u3_amd64.deb"
        "sha256-9OdZ26xJ2xbE8cNgFoSpIRoq8yEaP3vcBP/yY68Ipes=")
      (deb
        "https://deb.debian.org/debian/pool/main/p/python3.13/libpython3.13-minimal_3.13.5-2%2bdeb13u3_amd64.deb"
        "sha256-m+mk5Z1DrW4jc0m++9DRMeDPeYEjI7WsZCcFHO5+fKk=")
      (deb
        "https://deb.debian.org/debian/pool/main/p/python3.13/python3.13_3.13.5-2%2bdeb13u3_amd64.deb"
        "sha256-ZpM1mG/WQdb2xTj1WPx1KiDB2BaIVvkLfjSnYVSE3NI=")
      (deb
        "https://deb.debian.org/debian/pool/main/p/python3.13/python3.13-minimal_3.13.5-2%2bdeb13u3_amd64.deb"
        "sha256-O6+xvxZ0psj8UiluGxe1S2ZkAPxG9rHQ70wkuuvIg7s=")
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

      # Restored clusters can have a TimescaleDB catalog pinned to the
      # previous shared-library name even when the new image carries the SQL
      # update path. Keep the old loader names available so operators can
      # connect and run `ALTER EXTENSION timescaledb UPDATE`.
      if [ -e "$out/usr/lib/postgresql/18/lib/timescaledb-2.27.1.so" ]; then
        ln -s timescaledb-2.27.1.so \
          "$out/usr/lib/postgresql/18/lib/timescaledb-2.26.4.so"
      fi
      if [ -e "$out/usr/lib/postgresql/18/lib/timescaledb-tsl-2.27.1.so" ]; then
        ln -s timescaledb-tsl-2.27.1.so \
          "$out/usr/lib/postgresql/18/lib/timescaledb-tsl-2.26.4.so"
      fi

      if [ "${profile}" = "platform" ] || [ "${profile}" = "python" ]; then
        for deb in ${pkgs.lib.escapeShellArgs debianPlpythonPackages}; do
          dpkg-deb -x "$deb" "$out"
        done
      fi
      if [ "${profile}" = "platform" ] || [ "${profile}" = "experimental" ]; then
        install -m 755 ${pkgs.lib.getLib pkgs.duckdb}/lib/libduckdb.so \
          "$out/usr/lib/postgresql/18/lib/libduckdb.so"
        install -m 755 ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 \
          "$out/usr/lib/postgresql/18/lib/libstdc++.so.6"
        install -m 755 ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 \
          "$out/usr/lib/postgresql/18/lib/libgcc_s.so.1"
        install -m 755 ${pkgs.lib.getLib pkgs.lz4}/lib/liblz4.so.1 \
          "$out/usr/lib/postgresql/18/lib/liblz4.so.1"
      fi

      # The CNPG base image already ships PostgreSQL and libpq. Extensions
      # copied from Nix must not keep Nix-store RPATHs to libpq/glibc, or the
      # Debian runtime can fail loading them when glibc versions diverge.
      for so in "$out"/usr/lib/postgresql/18/lib/*.so; do
        if patchelf --print-rpath "$so" >/dev/null 2>&1; then
          patchelf --remove-rpath "$so" || true
        fi
      done
      if [ -e "$out/usr/lib/postgresql/18/lib/pg_duckdb.so" ]; then
        patchelf --set-rpath '$ORIGIN' \
          "$out/usr/lib/postgresql/18/lib/pg_duckdb.so"
        patchelf --set-rpath '$ORIGIN' \
          "$out/usr/lib/postgresql/18/lib/libduckdb.so"
      fi
    '';

  extensionClosure = pkgs:
    pkgs.buildEnv {
      name = "postgresql-18-extension-closure";
      paths = [pkgs.postgresql_18] ++ extensionPackages pkgs;
    };
}
