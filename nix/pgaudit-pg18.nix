{
  fetchFromGitHub,
  lib,
  libkrb5,
  openssl,
  postgresql,
  postgresqlBuildExtension,
}:
postgresqlBuildExtension {
  pname = "pgaudit";
  version = "18.0";

  src = fetchFromGitHub {
    owner = "pgaudit";
    repo = "pgaudit";
    tag = "18.0";
    hash = "sha256-+1YKJxMFkok7MsYeA9GRkc2FLxuBGRLpC+JzdK/xqoM=";
  };

  buildInputs = [
    libkrb5
    openssl
  ];

  makeFlags = ["USE_PGXS=1"];

  enableUpdateScript = false;

  meta = {
    description = "Open Source PostgreSQL Audit Logging";
    homepage = "https://github.com/pgaudit/pgaudit";
    changelog = "https://github.com/pgaudit/pgaudit/releases/tag/18.0";
    inherit (postgresql.meta) platforms;
    license = lib.licenses.postgresql;
  };
}
