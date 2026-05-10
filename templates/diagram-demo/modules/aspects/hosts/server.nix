# Server host: relay role with compound constraint composition.
#
# Demonstrates three constraint patterns in one host:
#   1. exclude — remove a specific provider sub-aspect (nginx-exporter)
#   2. filterBy — remove all aspects from a provider prefix (monitoring.*)
#   3. composition — multiple constraints via handleWith list
#
# The relay role includes server + mail, and server includes monitoring
# with sub-providers (node-exporter, nginx-exporter, alerting). The
# constraints prune monitoring providers from the resolution tree.
{ den, lib, ... }:
{
  den.aspects.server-host = {
    includes = with den.aspects; [ relay ];
    meta.handleWith = [
      # Remove nginx-exporter specifically (single provider exclusion)
      (den.lib.aspects.fx.constraints.exclude den.aspects.monitoring.nginx-exporter)
      # Remove all aspects whose provider chain starts with "monitoring" (prefix filter)
      (den.lib.aspects.fx.constraints.filterBy (
        a: lib.take 1 (a.meta.provider or [ ]) != [ "monitoring" ]
      ))
    ];
  };
}
