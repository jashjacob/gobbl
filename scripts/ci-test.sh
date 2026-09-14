#!/bin/bash
# Run the GobblCore test suites.
set -euo pipefail
cd "$(dirname "$0")/../Packages/GobblCore"
swift test
