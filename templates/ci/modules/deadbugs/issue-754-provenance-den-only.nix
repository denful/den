# Reported in GitHub #754, round 4: mutual-provider's provenance is den's own.
# Den pushes a provider's token onto a den-only stack around the include's
# walk; nothing reads it from an aspect name, and an author can't name an
# aspect with den's marker. A policy nested in a provider is tagged exactly
# as the provider's static content is: reached also another way, nested in a
# provider inside a provider, innermost first.
{ denTest, lib, ... }:
let
  pol =
    den: n:
    den.lib.policy.mkPolicy n (
      { host, ... }: [ (den.lib.policy.include { nixos.environment.etc.${n}.text = "x"; }) ]
    );
  # Counted, so a second firing shows.
  kpol =
    den:
    den.lib.policy.mkPolicy "k" (
      { host, ... }: [ (den.lib.policy.include { nixos.boot.kernelModules = [ "k" ]; }) ]
    );
  count = igloo: builtins.length (builtins.filter (m: m == "k") igloo.boot.kernelModules);
  explicit = den: { den.schema.host.includes = [ den.batteries.mutual-provider ]; };
  base = den: {
    imports = [ (explicit den) ];
    den.hosts.x86_64-linux.igloo.users.tux = { };
    den.aspects.tux.provides.to-hosts.nixos.environment.etc.real.text = "x";
  };
  etc = igloo: n: igloo.environment.etc ? ${n};
in
{
  flake.tests.deadbugs.issue-754-provenance-den-only = {

    # An author aspect named with den's marker is refused, whatever it
    # carries, and however the name was set.
    test-marker-name-refused-policy = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.includes = [
          {
            name = "den-provides-to-host=tux/to-hosts";
            includes = [ (pol den "fg") ];
          }
        ];
        expr = etc igloo "real";
        expectedError = {
          type = "ThrownError";
          msg = "den-provides-to-host=.*is reserved";
        };
      }
    );
    test-marker-name-refused-static = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.includes = [
          {
            name = "den-provides-to-host=tux/to-hosts";
            nixos.environment.etc.fs.text = "x";
          }
        ];
        expr = etc igloo "fs";
        expectedError = {
          type = "ThrownError";
          msg = "is reserved";
        };
      }
    );
    test-marker-name-refused-on-den-record = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.includes = [
          (den.batteries.define-user // { name = "den-provides-to-host=tux/to-hosts"; })
        ];
        expr = etc igloo "real";
        expectedError = {
          type = "ThrownError";
          msg = "is reserved";
        };
      }
    );
    # An author policy's include carrying den's provenance fields, set to
    # tux's real token, is not tagged: dispatch replaces them.
    test-author-provenance-fields-replaced = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.includes = [
          (den.lib.policy.mkPolicy "forger" (
            { host, ... }:
            [
              (
                (den.lib.policy.include { nixos.environment.etc.fg.text = "x"; })
                // {
                  __denProvenance = [ "tux/to-hosts" ];
                  __denRegChain = [ "tux/to-hosts" ];
                }
              )
            ]
          ))
        ];
        expr = {
          fg = etc igloo "fg";
          real = etc igloo "real";
        };
        expected = {
          fg = false;
          real = true;
        };
      }
    );

    # A carrier reached both directly and inside to-hosts: its policy is
    # delivered as its static content is, once.
    test-carrier-direct-and-to-hosts = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.carrier.includes = [ (kpol den) ];
        den.aspects.carrier.nixos.environment.etc.s.text = "x";
        den.aspects.tux.includes = [ den.aspects.carrier ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.carrier ];
        expr = {
          k = count igloo;
          s = etc igloo "s";
        };
        expected = {
          k = 1;
          s = true;
        };
      }
    );
    test-carrier-schema-user-and-to-hosts = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.carrier.includes = [ (kpol den) ];
        den.aspects.carrier.nixos.environment.etc.s.text = "x";
        den.schema.user.includes = [ den.aspects.carrier ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.carrier ];
        expr = {
          k = count igloo;
          s = etc igloo "s";
        };
        expected = {
          k = 1;
          s = true;
        };
      }
    );

    # A provider nested in a provider: the inner token wins, at two levels and
    # three; excluding the inner provided aspect stops both its contents.
    test-nested-provider-two-levels = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.shared.provides.to-hosts = {
          nixos.environment.etc.ss.text = "x";
          includes = [ (pol den "g5") ];
        };
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.shared ];
        expr = {
          ss = etc igloo "ss";
          g5 = etc igloo "g5";
        };
        expected = {
          ss = true;
          g5 = true;
        };
      }
    );
    test-nested-provider-three-levels = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.deep.provides.to-hosts = {
          nixos.environment.etc.sd.text = "x";
          includes = [ (pol den "g6") ];
        };
        den.aspects.shared.provides.to-hosts.includes = [ den.aspects.deep ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.shared ];
        expr = {
          sd = etc igloo "sd";
          g6 = etc igloo "g6";
        };
        expected = {
          sd = true;
          g6 = true;
        };
      }
    );
    test-nested-provider-inner-excluded = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.shared.provides.to-hosts = {
          nixos.environment.etc.ss.text = "x";
          includes = [ (pol den "g5") ];
        };
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.shared ];
        den.aspects.igloo.excludes = [ den.aspects.shared.provides.to-hosts ];
        expr = {
          ss = etc igloo "ss";
          g5 = etc igloo "g5";
        };
        expected = {
          ss = false;
          g5 = false;
        };
      }
    );
    test-named-host-provider = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.provides.igloo.includes = [ (pol den "g7") ];
        expr = etc igloo "g7";
        expected = true;
      }
    );

    # The other direction: not inherited where it shouldn't be.
    test-sibling-policy-not-tagged = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.tux.provides.to-hosts.includes = [ (pol den "g") ];
        den.aspects.tux.includes = [ (pol den "h") ];
        expr = {
          g = etc igloo "g";
          h = etc igloo "h";
        };
        expected = {
          g = true;
          h = false;
        };
      }
    );
    # The carrier is in tux's to-hosts; pingu includes it directly. pingu's
    # instance is pingu's own, not tux's provider's.
    test-other-users-direct-carrier-not-tagged = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.hosts.x86_64-linux.igloo.users.pingu = { };
        den.aspects.carrier.includes = [
          (den.lib.policy.mkPolicy "who" (
            { host, user, ... }:
            [ (den.lib.policy.include { nixos.environment.etc."who-${user.name}".text = "x"; }) ]
          ))
        ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.carrier ];
        den.aspects.pingu.includes = [ den.aspects.carrier ];
        expr = {
          tux = etc igloo "who-tux";
          pingu = etc igloo "who-pingu";
        };
        expected = {
          tux = true;
          pingu = false;
        };
      }
    );
    test-carrier-both-ways-battery-excluded = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.aspects.carrier.includes = [ (kpol den) ];
        den.aspects.tux.includes = [ den.aspects.carrier ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.carrier ];
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        expr = count igloo;
        expected = 0;
      }
    );
    test-carrier-both-ways-acknowledged-no-battery = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.migrations.user-host-content.acknowledged = true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.carrier.includes = [ (kpol den) ];
        den.aspects.tux.includes = [ den.aspects.carrier ];
        den.aspects.tux.provides.to-hosts.includes = [ den.aspects.carrier ];
        expr = count igloo;
        expected = 0;
      }
    );
    test-acknowledged-explicit-battery-delivers = denTest (
      { den, igloo, ... }:
      {
        imports = [ (base den) ];
        den.internal.transitionDefaults = lib.mkForce true;
        den.migrations.user-host-content.acknowledged = true;
        den.aspects.tux.provides.to-hosts.includes = [ (pol den "g4") ];
        expr = etc igloo "g4";
        expected = true;
      }
    );
    test-default-only-delivers = denTest (
      { den, igloo, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.includes = [ (pol den "g4") ];
        expr = etc igloo "g4";
        expected = true;
      }
    );

    # The warning names a nested policy's content by its provider, as it
    # names the provider's static content.
    test-default-only-warning-names-provider = denTest (
      { den, config, ... }:
      {
        den.internal.transitionDefaults = lib.mkForce true;
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.provides.to-hosts.includes = [ (pol den "g8") ];
        expr = map (l: l.aspect) (
          config.flake.nixosConfigurations.igloo._module.args.denTransitionDefaultLost or [ ]
        );
        expected = [ "tux/to-hosts" ];
      }
    );
  };
}
