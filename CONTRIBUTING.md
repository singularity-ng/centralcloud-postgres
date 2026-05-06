# Contributing

This repo keeps PostgreSQL packaging reproducible and reviewable. Changes should
be small, pinned, and easy to audit.

## Requirements

- Nix with flakes enabled.
- Docker or Podman only when loading/running the OCI image locally.

Enter the dev shell:

```sh
nix develop
```

Run the full local check:

```sh
just check
```

Install local hooks:

```sh
just install-hooks
```

## Packaging Rules

- Pin upstream source versions and hashes.
- Do not use unpinned moving tags for extension sources.
- Do not enable extensions globally just because they are present in the image.
- Keep CloudNativePG base images pinned by manifest.
- Do not require private SSH builders. Public builds must work with local Nix
  builders and public caches.

## Release Checklist

1. Run `just check`.
2. Run `just build-image`.
3. Load and smoke test locally with `just build-cnpg-image`.
4. Generate an SBOM with `just sbom`.
5. Push with `PUSH=1 just build-cnpg-image`.
6. Tag the repo with the PostgreSQL major and extension set.
