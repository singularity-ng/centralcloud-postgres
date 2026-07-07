# Contributing

This repo keeps PostgreSQL packaging reproducible and reviewable. Changes should
be small, pinned, and easy to audit.

## Requirements

- Nix with flakes enabled (nixos-26.05 / `nix develop`).
- Image publish uses **nix2container** + host **skopeo** — no docker client in the dev shell.
- Remote registry smoke (`just smoke-image` after push) uses **skopeo on the CI runner** only.

Enter the dev shell:

```sh
nix develop
```

Run the full local check:

```sh
just check   # nix flake check (format, statix, deadnix, workflows, image)
just lint    # fast: extension docs + actionlint + shellcheck only
just fmt     # nix fmt (alejandra via flake formatter)
```

Install local hooks (also auto-installed on first `nix develop`):

```sh
just install-hooks
```

Lefthook runs on pre-commit (staged Nix/workflows/shell) and pre-push (`just check`).
Nix lint trio: **alejandra** (format), **statix** (anti-patterns), **deadnix** (unused bindings).
Also: actionlint, shellcheck. k3d/kubectl live in the dev-cluster package only; syft is pulled on demand for `just sbom`.

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
3. Build without publishing with `just build-cnpg-image`.
4. Push with `PUSH=1 just build-cnpg-image`.
5. Smoke the published image with `just smoke-image`.
6. Generate an SBOM with `just sbom`.
7. Tag the repo with the PostgreSQL major and extension set.
