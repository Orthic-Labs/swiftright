#!/bin/sh
# Fetch pinned MarkdownUI 2.4.1, swift-cmark 0.5.0, NetworkImage 6.0.0 sources into ./vendor (gitignored).
set -e
cd "$(dirname "$0")"
mkdir -p vendor
get() { # name url commit
  if [ ! -d "vendor/$1" ]; then
    git init -q "vendor/$1"
    git -C "vendor/$1" fetch -q --depth 1 "$2" "$3"
    git -C "vendor/$1" checkout -q FETCH_HEAD
  fi
}
get swift-markdown-ui https://github.com/gonzalezreal/swift-markdown-ui.git 5f613358148239d0292c0cef674a3c2314737f9e
get swift-cmark https://github.com/swiftlang/swift-cmark.git 3ccff77b2dc5b96b77db3da0d68d28068593fa53
# SwiftRight patches (Windows has neither UIKit nor AppKit), applied once.
for p in patches/*.patch; do git -C vendor/swift-markdown-ui apply --check "../../$p" 2>/dev/null && git -C vendor/swift-markdown-ui apply "../../$p"; done
echo fetched
