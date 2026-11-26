# In-context `<entity>.hasAspect X` is true exactly when content of X, or of an
# aspect X includes, lands in that entity's own evaluation in that entity's
# class, whichever scope or class asks.
#
# The oracle derives every expectation from where X's markers actually land
# in the same evaluation, never from a written-down truth: X writes a marker in
# each class, and each reader's answer must equal its entity's marker.
{ denTest, lib, ... }:
let
  b = v: if v then "T" else "f";

  # One delivery path for X.
  paths = {
    p1-host-includes =
      { den, ... }:
      {
        den.aspects.igloo.includes = [ den.aspects.probeX ];
      };
    p2-host-provides-to-users =
      { den, ... }:
      {
        den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
      };
    p3-host-provides-tux =
      { den, ... }:
      {
        den.aspects.igloo.provides.tux.includes = [ den.aspects.probeX ];
      };
    p4-user-includes =
      { den, ... }:
      {
        den.aspects.tux.includes = [ den.aspects.probeX ];
      };
    p5-user-at-host =
      { den, ... }:
      {
        den.aspects."tux@igloo".includes = [ den.aspects.probeX ];
      };
    p6-nested-host-key =
      { den, ... }:
      {
        den.aspects.igloo.tux.includes = [ den.aspects.probeX ];
      };
    p7-host-includes-tux-host-aspects =
      { den, ... }:
      {
        den.aspects.igloo.includes = [ den.aspects.probeX ];
        den.aspects.tux.includes = [ den.batteries.host-aspects ];
      };
    p8-default-includes =
      { den, ... }:
      {
        den.default.includes = [ den.aspects.probeX ];
      };
    p9-schema-user-includes =
      { den, ... }:
      {
        den.schema.user.includes = [ den.aspects.probeX ];
      };
  };

  # `transition`: the #694 transition defaults, really on (denTest turns them
  # off for the whole suite).
  fixture =
    transition: path:
    { den, ... }:
    {
      imports = [ path ];
      den.internal.transitionDefaults = lib.mkForce transition;
      den.aspects.probeX = {
        nixos.environment.etc."mark-x".text = "x";
        homeManager.home.file."mark-x".text = "x";
      };
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [
        den._.define-user
        {
          nixos =
            { host, ... }:
            {
              environment.etc."r-host".text = b (host.hasAspect den.aspects.probeX);
            };
          homeManager =
            { host, user, ... }:
            {
              home.file."r-host".text = b (host.hasAspect den.aspects.probeX);
              home.file."r-user".text = b (user.hasAspect den.aspects.probeX);
            };
        }
      ];
      den.schema.user.classes = [ "homeManager" ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
    };

  # Each reader against its entity's marker: the host's nixos for
  # `host.hasAspect`, that user's homeManager for `user.hasAspect`.
  readings =
    igloo:
    let
      hm = u: igloo.home-manager.users.${u}.home.file;
      read = u: k: (hm u).${k}.text or "-";
      landsHost = b (igloo.environment.etc ? "mark-x");
      landsUser = u: b ((hm u) ? "mark-x");
    in
    {
      # With the transition default on, the reader also fires in each user
      # scope and those copies reach the host too: every copy must agree.
      hostScope_host = {
        got = lib.concatStringsSep "," (
          lib.unique (lib.splitString "\n" (igloo.environment.etc."r-host".text or "-"))
        );
        want = landsHost;
      };
      tux_host = {
        got = read "tux" "r-host";
        want = landsHost;
      };
      tux_user = {
        got = read "tux" "r-user";
        want = landsUser "tux";
      };
      pingu_host = {
        got = read "pingu" "r-host";
        want = landsHost;
      };
      pingu_user = {
        got = read "pingu" "r-user";
        want = landsUser "pingu";
      };
    };
  wrong = rs: builtins.attrNames (lib.filterAttrs (_: r: r.got != r.want) rs);

  cell =
    transition: path:
    denTest (
      { igloo, ... }:
      {
        imports = [ (fixture transition path) ];
        expr = wrong (readings igloo);
        expected = [ ];
      }
    );
in
{
  flake.tests.hasaspect-lands-in-class =
    lib.mapAttrs' (n: p: lib.nameValuePair "test-end-state-${n}" (cell false p)) paths
    // lib.mapAttrs' (n: p: lib.nameValuePair "test-transition-${n}" (cell true p)) paths;
}
