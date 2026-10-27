#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

################################################################################
#
# mdBook preprocessor that:
#
# - Renames `rss.xml` to `feed.xml`, including the self link contained in the
#   file
# - Cleans up item URLs by removing trailing `index.html` (matching the clean
#   URLs from `theme/script.js`)
#
################################################################################

# Answer `feed-rename.sh supports html` with a 0 for yes (this script doesn't
# touch the HTML but just needs to run)
if [[ "${1:-}" == "supports" ]]; then exit 0; fi

# Find the source directory
input=$(cat)
root=$(jq -r '.[0].root' <<<"$input")
src=$(jq -r '.[0].config.book.src // "src"' <<<"$input")

rss="$root/$src/rss.xml"
feed="$root/$src/feed.xml"

if [[ -f "$rss" ]]; then
  tmp=$(mktemp)

  # Rewrite the self link to the new file name and strip trailing `index.html`
  # from `<link>` and `<guid>` only (not post content, which may link
  # elsewhere). The `g` flag is needed because the whole feed is written on one
  # line.
  sed \
    -e 's|/rss\.xml"|/feed.xml"|' \
    -e 's|/index\.html</link>|/</link>|g' \
    -e 's|/index\.html</guid>|/</guid>|g' \
    "$rss" >"$tmp"

  # Only write when something changed
  if cmp -s "$tmp" "$feed"; then
    rm "$tmp"
  else
    mv "$tmp" "$feed"
  fi

  # Remove the original `rss.xml` file so only `feed.xml` is served
  rm "$rss"
fi

# A preprocessor must print the book to stdout
jq '.[1]' <<<"$input"
