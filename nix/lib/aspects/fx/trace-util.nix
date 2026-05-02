# Tiered tracing utility for the fx pipeline.
#
# Summary traces (always-on): pipeline-level counts and structure.
#   - Scope inventory, module counts per class, route/provide/instantiate summaries
#   - Useful for quick sanity checks without noise
#
# Detail traces (DEN_TRACE=1): per-aspect, per-handler granularity.
#   - aspectToEffect calls, emit-class, check-dedup, ctx-seen, installPolicies
#   - Useful for debugging specific resolution/identity issues
#
# Usage:
#   inherit (den.lib.aspects.fx.traceUtil) traceSummary traceDetail;
#   traceSummary "scopes = [${...}]" value   # always fires
#   traceDetail "emit-class ..." value        # only when DEN_TRACE=1
{ lib, ... }:
let
  detailEnabled = builtins.getEnv "DEN_TRACE" == "1";

  # Always-on: pipeline structure and counts.
  traceSummary = msg: builtins.trace "den: ${msg}";

  # Gated: per-aspect/handler detail.
  traceDetail = msg: if detailEnabled then builtins.trace "den:detail: ${msg}" else lib.id;
in
{
  inherit traceSummary traceDetail;
}
