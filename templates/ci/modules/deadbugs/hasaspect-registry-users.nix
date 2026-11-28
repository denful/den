# A user defined only in `den.users`, reaching hosts through its `hosts`
# list, answers `hasAspect` from what lands, as a user declared on the host
# does. Expectations come from the markers that land.
{ denTest, lib, ... }:
let
  b = v: if v then "T" else "f";
  one = s: lib.concatStringsSep "," (lib.unique (lib.splitString "\n" s));

  base =
    transition:
    { den, ... }:
    {
      den.internal.transitionDefaults = lib.mkForce transition;
      den.schema.user.classes = [ "homeManager" ];
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
      den.aspects.probeX = {
        nixos.environment.etc."mark-x".text = "x";
        homeManager.home.file."mark-x".text = "x";
      };
      den.hosts.x86_64-linux = {
        igloo = { };
        iceberg = { };
      };
    };

  # Every reader against where X lands, on `host` for user `u`.
  check =
    den: config: host: u:
    let
      cfg = config.flake.nixosConfigurations.${host}.config;
      etc = cfg.environment.etc;
      hm = cfg.home-manager.users.${u}.home.file;
      h = den.hosts.x86_64-linux.${host};
      lh = b (etc ? "mark-x");
      lu = b (hm ? "mark-x");
      got = {
        hostFromHost = one (etc."r-host".text or "-");
        hostFromUser = hm."r-host".text or "-";
        userFromUser = hm."r-user".text or "-";
        lateHost = b (den.lib.__hasLandedAspect { entity = h; } den.aspects.probeX);
        lateUser = b (
          den.lib.__hasLandedAspect {
            entity = h.users.${u};
            within.host = h;
          } den.aspects.probeX
        );
      };
      want = {
        hostFromHost = lh;
        hostFromUser = lh;
        userFromUser = lu;
        lateHost = lh;
        lateUser = lu;
      };
    in
    {
      lands = [
        lh
        lu
      ];
      wrong = builtins.attrNames (lib.filterAttrs (k: v: got.${k} != v) want);
    };

  both = name: mk: {
    "test-end-state-${name}" = mk false;
    "test-transition-${name}" = mk true;
  };
in
{
  flake.tests.hasaspect-registry-users =

    # The user's own include: X lands in alice's home, and in igloo only once
    # the host accepts its users' host-class output (the transition default).
    both "user-includes" (
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.users.alice.hosts = [ "igloo" ];
          den.aspects.alice.includes = [ den.aspects.probeX ];
          expr = {
            igloo = check den config "igloo" "alice";
            registry = b (den.hosts.x86_64-linux.igloo.hasAspect den.aspects.probeX);
            onIceberg = den.hosts.x86_64-linux.iceberg.users ? alice;
          };
          expected = {
            igloo = {
              lands = [
                (if transition then "T" else "f")
                "T"
              ];
              wrong = [ ];
            };
            # The registry lookup keeps its answer: X is in igloo's tree.
            registry = "T";
            onIceberg = false;
          };
        }
      )
    )

    # The host's `provides.to-users`: X lands in igloo and in alice's home.
    // both "host-provides-to-users" (
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.users.alice.hosts = [ "igloo" ];
          den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
          expr = check den config "igloo" "alice";
          expected = {
            lands = [
              "T"
              "T"
            ];
            wrong = [ ];
          };
        }
      )
    )

    # One registry user on two hosts, X provided by igloo only: it lands on
    # igloo for bob and nowhere on iceberg, and iceberg's readers say so.
    // both "two-hosts-no-leak" (
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.users.bob.hosts = [
            "igloo"
            "iceberg"
          ];
          den.aspects.igloo.provides.to-users.includes = [ den.aspects.probeX ];
          expr = {
            igloo = check den config "igloo" "bob";
            iceberg = check den config "iceberg" "bob";
          };
          expected = {
            igloo = {
              lands = [
                "T"
                "T"
              ];
              wrong = [ ];
            };
            iceberg = {
              lands = [
                "f"
                "f"
              ];
              wrong = [ ];
            };
          };
        }
      )
    );
}
