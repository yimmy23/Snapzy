#!/bin/bash
set -e

# Get the script directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$DIR/.."

cd "$ROOT_DIR"

if which swiftformat >/dev/null; then
  echo "Formatting codebase..."
  swiftformat .
else
  echo "error: SwiftFormat is not installed. Run 'brew install swiftformat' first."
  exit 1
fi
