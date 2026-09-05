#!/usr/bin/env bash
# Fail-closed pre-publish check on the LOCALLY built nix2container image JSON.
#
# Purpose: refuse to publish an image that cannot run. A zero-layer manifest
# (layers: null/[]) reached production twice - 2026-07 and 2026-08-08 - and
# silently killed backup verification for 15 days, because the only check ran
# AFTER the push and skipped itself when the image carried no labels.
# Consumer: build-postgres18-cnpg-image.sh, before any skopeo copy.
# Contract: exit 0 only when the artifact has a non-empty layer set and a usable
# runtime config. Any other outcome exits non-zero with the reason on stderr.
# Failure modes: a base-image pull that resolves to an empty manifest; a
# copyToRoot that produced nothing; a truncated or unparseable image JSON.
# Evidence: nix2container image JSON keys are arch, created, image-config,
# layers, version; a healthy image of this shape carries 32 layers.
# Falsifier: publishing an image whose `layers` is empty and having this exit 0.
set -euo pipefail

image_json="${1:?usage: verify-image-artifact.sh <image.json>}"

if [[ ! -s "$image_json" ]]; then
  echo "verify-image-artifact: image JSON is missing or empty: $image_json" >&2
  exit 1
fi

if ! layer_count="$(jq -e '.layers | length' "$image_json" 2>/dev/null)"; then
  echo "verify-image-artifact: image JSON has no .layers array: $image_json" >&2
  echo "verify-image-artifact: refusing to publish an image with no filesystem" >&2
  exit 1
fi

if [[ "$layer_count" -lt 1 ]]; then
  echo "verify-image-artifact: image has $layer_count layers - nothing would run" >&2
  echo "verify-image-artifact: this is the zero-layer manifest failure mode" >&2
  exit 1
fi

if ! jq -e '."image-config" | objects | has("Cmd") or has("Entrypoint")' "$image_json" >/dev/null 2>&1; then
  echo "verify-image-artifact: image-config has neither Cmd nor Entrypoint" >&2
  exit 1
fi

echo "verify-image-artifact: ok layers=$layer_count $image_json"
