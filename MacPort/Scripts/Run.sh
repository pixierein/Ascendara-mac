#!/bin/bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
"$Root/Scripts/Build.sh" debug
open "$Root/Build/Ascendara.app"
