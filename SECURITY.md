# Security

Report security issues privately to the maintainers before opening a public
issue.

## Scope

Security-sensitive areas include:

- PostgreSQL base image pinning.
- Extension source hashes and binary release hashes.
- Runtime libraries copied into the image.
- GHCR publishing and provenance.
- Default PostgreSQL configuration examples.

## Defaults

The image makes extension files available but does not create extensions inside
databases and does not force preload settings. Operators must choose the minimum
extension set needed by each cluster.

