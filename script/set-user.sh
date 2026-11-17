#!/usr/bin/env bash
# Point the module at your mooncakes / GitHub account before publishing.
#
#   script/set-user.sh <username>
#
# Why this exists: mooncakes requires the module name to be
# `<username>/<module>` and to match the publishing account, while local
# development is happiest with a short name. The module name is also the import
# prefix of every package, so this touches moon.mod plus every moon.pkg — ten
# files, which is exactly the kind of edit that should never be done by hand.
set -euo pipefail

user="${1:-}"
if [ -z "$user" ]; then
  echo "usage: script/set-user.sh <username>" >&2
  exit 2
fi

cd "$(dirname "$0")/.."

# 1. imports: "moonsting/core" -> "<user>/moonsting/core"
find . -name '*.pkg' -not -path './_build/*' -print0 | while IFS= read -r -d '' f; do
  if grep -q '"moonsting/' "$f"; then
    sed -i.bak "s|\"moonsting/|\"$user/moonsting/|g" "$f"
    rm -f "$f.bak"
    echo "patched $f"
  fi
done

# 2. module name + repository
sed -i.bak "s|^name = .*|name = \"$user/moonsting\"|" moon.mod
rm -f moon.mod.bak
if grep -q '^repository = ' moon.mod; then
  sed -i.bak "s|^repository = .*|repository = \"https://github.com/$user/moonsting\"|" moon.mod
  rm -f moon.mod.bak
else
  printf 'repository = "https://github.com/%s/moonsting"\n' "$user" >> moon.mod
fi

echo
echo "module is now $user/moonsting"
echo "verify with:"
echo "  moon check --target wasm-gc --deny-warn"
echo "  moon test  --target native"
echo "  moon package --list"
echo "then: moon publish"
