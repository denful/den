# Issue #694: excluding mutual-provider turns cross-provision off. Each cell
# reads the option values a host ends up with; a host that keeps the battery is
# the positive control in the same config.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-694-mutual-provider-exclude = {

    # `provides.to-hosts`: excluded on igloo, kept on iceberg. igloo doesn't
    # receive it; iceberg still gets it.
    test-to-hosts-excluded-on-one-host = denTest (
      {
        den,
        igloo,
        iceberg,
        ...
      }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = {
          iceberg = iceberg.environment.etc.probe.text;
          igloo = igloo.environment.etc ? probe;
        };
        expected = {
          iceberg = "from-tux";
          igloo = false;
        };
      }
    );

    # The positive control on its own: the non-excluding host delivers.
    test-to-hosts-kept-on-other-host = denTest (
      { den, iceberg, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = iceberg.environment.etc.probe.text;
        expected = "from-tux";
      }
    );

    # `provides.<host>`: the named host excludes the battery.
    test-named-host-provide-excluded = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.igloo.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc ? probe;

        expected = false;
      }
    );

    # Fleet-wide exclude: no host gets it.
    test-fleet-wide-exclude = denTest (
      { den, iceberg, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.hosts.x86_64-linux.iceberg.users.tux = { };
        den.schema.host.excludes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = iceberg.environment.etc ? probe;

        expected = false;
      }
    );

    # With it excluded, a user's provides.to-hosts does not reach the host.
    test-excluded-not-delivered = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc ? probe;
        expected = false;
      }
    );

    # The two batteries are independent: with mutual-provider excluded,
    # user-aspects still carries the user's whole host-class output.
    test-excluded-with-user-aspects-arrives = denTest (
      { den, igloo, ... }:
      {
        den.schema.host.includes = [ den.batteries.mutual-provider ];
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.excludes = [ den.batteries.mutual-provider ];
        den.aspects.igloo.includes = [ den.batteries.user-aspects ];
        den.aspects.tux.provides.to-hosts.nixos.environment.etc.probe.text = "from-tux";
        expr = igloo.environment.etc.probe.text;
        expected = "from-tux";
      }
    );
  };
}
