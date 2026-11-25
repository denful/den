# The registry form `den.hosts.<s>.<h>.hasAspect` keeps its answer for every
# caller, early or late: the host's resolved tree, with its users. `probeX` is
# included by tux only, so it's in igloo's tree but, in the end state, doesn't
# land in igloo's nixos. Each cell reads the registry from one place a caller
# can and expects that answer, true, while the finalized query
# (den.lib.__hasLandedAspect) and in-context `host.hasAspect` answer what lands.
#
# A host's policy reading its own registry entry, and two hosts' policies
# reading each other's, recurse. They aren't cells:
# `just ci` can't catch a recursion (tryEval doesn't), so they would fail the
# run rather than pin it.
{ denTest, lib, ... }:
let
  base =
    transition:
    { den, ... }:
    {
      den.internal.transitionDefaults = lib.mkForce transition;
      den.schema.user.classes = [ "homeManager" ];
      den.default.homeManager.home.stateVersion = "25.11";
      den.default.includes = [ den._.define-user ];
      den.hosts.x86_64-linux = {
        igloo.users.tux = { };
        iceberg.users.pingu = { };
      };
      den.aspects.probeX = {
        nixos.environment.etc."mark-x".text = "x";
        homeManager.home.file."mark-x".text = "x";
      };
      den.aspects.tux.includes = [ den.aspects.probeX ];
      den.aspects.marker.nixos.environment.etc."mark-y".text = "y";
    };
  reg = den: den.hosts.x86_64-linux.igloo.hasAspect den.aspects.probeX;
  marks = etc: builtins.filter (lib.hasPrefix "mark-") (builtins.attrNames etc);
  cells = {

    # iceberg's policy reads igloo's registry entry.
    cross-host-policy =
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.aspects.iceberg.policies.peer-read =
            { host, ... }:
            lib.optional (host.name == "iceberg" && reg den) (den.lib.policy.include den.aspects.marker);
          den.aspects.iceberg.includes = [ den.aspects.iceberg.policies.peer-read ];
          expr = marks config.flake.nixosConfigurations.iceberg.config.environment.etc;
          expected = [ "mark-y" ];
        }
      );

    # A computed include list reading another host's registry entry.
    computed-include =
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.aspects.iceberg.includes = lib.optional (reg den) den.aspects.marker;
          expr = marks config.flake.nixosConfigurations.iceberg.config.environment.etc;
          expected = [ "mark-y" ];
        }
      );

    # The registry read captured in an alias and forced in a class module.
    aliased-in-class-module =
      transition:
      denTest (
        { den, config, ... }:
        let
          q = den.hosts.x86_64-linux.igloo.hasAspect;
        in
        {
          imports = [ (base transition) ];
          den.aspects.iceberg.nixos.environment.etc."r-alias".text = lib.boolToString (q den.aspects.probeX);
          expr = config.flake.nixosConfigurations.iceberg.config.environment.etc."r-alias".text;
          expected = "true";
        }
      );

    # A thunk built by a policy during the walk and forced after it, in a
    # class module.
    early-thunk-forced-late =
      transition:
      denTest (
        { den, config, ... }:
        {
          imports = [ (base transition) ];
          den.aspects.iceberg.policies.capture =
            { host, ... }:
            lib.optional (host.name == "iceberg") (
              den.lib.policy.include {
                nixos.environment.etc."r-early".text = lib.boolToString (reg den);
              }
            );
          den.aspects.iceberg.includes = [ den.aspects.iceberg.policies.capture ];
          expr = config.flake.nixosConfigurations.iceberg.config.environment.etc."r-early".text;
          expected = "true";
        }
      );
  };
in
{
  flake.tests.hasaspect-registry-pins = lib.concatMapAttrs (n: mk: {
    "test-end-state-${n}" = mk false;
    "test-transition-${n}" = mk true;
  }) cells;

}
