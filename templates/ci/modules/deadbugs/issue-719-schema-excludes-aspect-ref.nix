# #719: an aspect reference in den.schema.host.excludes was ignored after #717,
# and a bracket reference to a nested aspect recursed through den.aspects.
{ denTest, ... }:
{
  flake.tests.deadbugs.issue-719-schema-excludes-aspect-ref = {

    test-schema-excludes-aspect-ref = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.unwanted.nixos.networking.domain = "unwanted.example";
        den.aspects.igloo.includes = [ den.aspects.unwanted ];

        den.schema.host.excludes = [ den.aspects.unwanted ];

        expr = igloo.networking.domain;
        expected = null;
      }
    );

    test-schema-excludes-bracket-ref = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) __findFile;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.unwanted.nixos.networking.domain = "unwanted.example";
        den.aspects.igloo.includes = [ <unwanted> ];

        den.schema.host.excludes = [ <unwanted> ];

        expr = igloo.networking.domain;
        expected = null;
      }
    );

    test-schema-excludes-nested-bracket-ref = denTest (
      { den, igloo, ... }:
      let
        inherit (den.lib) __findFile;
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.gui.unwanted.nixos.networking.domain = "unwanted.example";
        den.aspects.igloo.includes = [ <gui/unwanted> ];

        den.schema.host.excludes = [ <gui/unwanted> ];

        expr = igloo.networking.domain;
        expected = null;
      }
    );

    # The parent kind's collections hold the same references. They do not
    # apply to a host instance (as before #717); these pin that they evaluate.
    test-conf-excludes-aspect-ref = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.unwanted.nixos.networking.domain = "unwanted.example";
        den.aspects.igloo.includes = [ den.aspects.unwanted ];

        den.schema.conf.excludes = [ den.aspects.unwanted ];

        expr = igloo.networking.domain;
        expected = "unwanted.example";
      }
    );

    test-conf-includes-aspect-ref = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.wanted.nixos.networking.domain = "wanted.example";

        den.schema.conf.includes = [ den.aspects.wanted ];

        expr = igloo.networking.domain;
        expected = null;
      }
    );

  };
}
