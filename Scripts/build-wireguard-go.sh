#!/usr/bin/env bash
#
# Build WireGuardKitGo for the WireGuardGoBridge legacy target.
#
# This exists because the checkout cannot be reached by a fixed path. The
# target used to point Xcode straight at
#
#   $(BUILD_DIR)/../../SourcePackages/checkouts/wireguard-apple/...
#
# which is correct for `xcodebuild build` and wrong for `xcodebuild archive`:
#
#   build    BUILD_DIR=<derived>/Build/Products                      -> ../..
#   archive  BUILD_DIR=<derived>/Build/Intermediates.noindex/\
#              ArchiveIntermediates/<scheme>/BuildProductsPath       -> ../../../../..
#
# An archive therefore resolved the working directory to a path that has never
# existed, and Xcode reported that as `unable to spawn process '/usr/bin/env'
# (No such file or directory)` — posix_spawn returns ENOENT for a missing cwd
# just as it does for a missing binary, so the message names the wrong file.
#
# Walking up from BUILD_DIR finds the checkout in both layouts, and keeps
# working if a future Xcode moves the archive intermediates again or the build
# runs from Xcode's shared DerivedData rather than `-derivedDataPath`.
#
# Invoked by the WireGuardGoBridge target with `passSettings: true`, so
# BUILD_DIR and ACTION arrive as environment variables.
set -euo pipefail

: "${BUILD_DIR:?must be run from the WireGuardGoBridge target (BUILD_DIR unset)}"

readonly REL="SourcePackages/checkouts/wireguard-apple/Sources/WireGuardKitGo"

dir="$BUILD_DIR"
while [ "$dir" != "/" ]; do
  if [ -d "$dir/$REL" ]; then
    cd "$dir/$REL"
    # ACTION is empty for a plain `xcodebuild` with no action word; the
    # Makefile's default goal is not the library, so name `build` explicitly.
    exec make "${ACTION:-build}"
  fi
  dir="$(dirname "$dir")"
done

echo "error: no $REL found in any parent of $BUILD_DIR" >&2
echo "hint: resolve the package graph first (xcodebuild -resolvePackageDependencies)" >&2
exit 1
