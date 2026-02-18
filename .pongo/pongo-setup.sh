#!/usr/bin/env bash
set -euo pipefail

cd /kong-plugin || { echo "Failure to enter /kong-plugin"; exit 1; }

while IFS= read -r -d '' rockspec; do
  luarocks install --only-deps "$rockspec"
done < <(find /kong-plugin -maxdepth 1 -type f -name '*.rockspec' -print0)

latest_rockspec=$(ls -1 /kong-plugin/kong-plugin-version-gate-*.rockspec | sort -V | tail -1)
luarocks remove --force kong-plugin-version-gate >/dev/null 2>&1 || true
luarocks make "$latest_rockspec"
