#!/usr/bin/env bash
#
# Extract a simple utilization/timing summary from nextpnr's JSON report.
# Usage: ./util_report.sh build/hardware.rpt > summary.txt

set -euo pipefail

report="${1:-hardware.rpt}"

if [[ ! -f "$report" ]]; then
  echo "Report file not found: $report" >&2
  exit 1
fi

# nextpnr JSON report contains fmax and utilization. Use jq if available.
if command -v jq >/dev/null 2>&1; then
  jq -r '
    {
      fmax_mhz: (.fmax."clk$SB_IO_IN_$glb_clk".achieved // .fmax[]?.achieved),
      lc_used:   .utilization["ICESTORM_LC"].used,
      lc_avail:  .utilization["ICESTORM_LC"].available,
      io_used:   .utilization["SB_IO"].used,
      io_avail:  .utilization["SB_IO"].available,
      bram_used: .utilization["ICESTORM_RAM"].used,
      bram_avail:.utilization["ICESTORM_RAM"].available
    }' "$report"
else
  echo "jq not found; printing top of report:" >&2
  head -n 40 "$report"
fi
