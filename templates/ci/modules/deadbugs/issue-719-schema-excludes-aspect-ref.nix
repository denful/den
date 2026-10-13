# #719: an aspect reference in den.schema.host.excludes was ignored after #717,
# and a bracket reference to a nested aspect recursed through den.aspects.
{ denTest, ... }:
{
  flake.tests.issue-719-schema-excludes-aspect-ref = {

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

  };
}
