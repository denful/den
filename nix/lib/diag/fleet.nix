# Fleet-level data capture.
#
# Produces a compact record describing all hosts/users in a den flake,
# suitable for rendering as a C4 Context diagram. Unlike per-host tracing
# (capture.nix), this iterates a host registry and does not resolve aspects
# per-host (except lazily for provider sub-aspects).
#
# Output shape:
#
#   { flakeName, hosts, users, relations, providerSubAspects }
#     where:
#       hosts     = [ { name, description } ]
#       users     = [ { name } ]
#       relations = [ { from, to, label } ]   # user->host (class) edges
{
  den,
  lib,
  capture,
  ...
}:
let

  # Flatten a `den.hosts`-shaped attrset to a list of
  # { name, system, host, users : [ { name, classes } ] }.
  flattenHosts =
    hostsAttr:
    lib.concatMap (
      system:
      lib.mapAttrsToList (hostName: hostObj: {
        name = hostName;
        inherit system;
        host = hostObj;
        users = lib.mapAttrsToList (userName: user: {
          name = userName;
          classes = user.classes or [ ];
        }) (hostObj.users or { });
      }) (hostsAttr.${system} or { })
    ) (builtins.attrNames hostsAttr);

  # Per-host: capture structured trace and extract provider sub-aspects.
  providerSubAspectsOf =
    hostInfo:
    let
      hostAspect = den.lib.resolveEntity "host" { host = hostInfo.host; };
      entries = capture.capture "nixos" hostAspect;
      meaningful =
        name: name != "<anon>" && name != "<function body>" && !(lib.hasPrefix "[definition " name);
      providerEntries = builtins.filter (e: (e.provider or [ ]) != [ ] && meaningful e.name) entries;
    in
    map (e: {
      provider = builtins.head e.provider;
      subAspect = lib.concatStringsSep "/" (e.provider ++ [ e.name ]);
      hostName = hostInfo.name;
    }) providerEntries;

  fleetGraph =
    {
      # Host registry. Defaults to den.hosts but callers can override
      # with a filtered subset or hosts from a different flake.
      hosts ? den.hosts or { },
      flakeName ? "den flake",
    }:
    let
      allHosts = flattenHosts hosts;

      hostRecords = map (h: {
        inherit (h) name;
        description = h.system;
      }) allHosts;

      users = lib.unique (lib.concatMap (h: map (u: { inherit (u) name; }) h.users) allHosts);

      relations = lib.concatMap (
        h:
        map (u: {
          from = u.name;
          to = h.name;
          label = if u.classes == [ ] then "uses" else lib.concatStringsSep "+" u.classes;
        }) h.users
      ) allHosts;

      # Lazy: only forced if a renderer reads this attribute.
      providerSubAspects = lib.concatMap providerSubAspectsOf allHosts;
    in
    {
      inherit flakeName relations providerSubAspects;
      hosts = hostRecords;
      inherit users;
    };
in
{
  inherit fleetGraph;
}
