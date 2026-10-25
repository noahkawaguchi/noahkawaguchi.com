#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail

#
# mdBook preprocessor to rename `rss.xml` to `feed.xml`, including the self link
# contained in the file
#

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
  # Rewrite the self link to the new file name in the XML itself
  sed 's|/rss\.xml"|/feed.xml"|' "$rss" >"$tmp"

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
