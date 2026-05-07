{ denTest, ... }:
{
  flake.tests.aspect-meta = {

    test-meta-can-be-referenced = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.foo = {
          funny.names = [ den.aspects.foo.meta.nick ];
          meta.nick = "McLoving";
        };

        expr = funnyNames den.aspects.foo;
        expected = [ "McLoving" ];
      }
    );

    test-meta-can-be-self-referenced = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.foo =
          { config, ... }:
          {
            funny.names = [ config.meta.nick ];
            meta.nick = "McLoving";
          };

        expr = funnyNames den.aspects.foo;
        expected = [ "McLoving" ];
      }
    );

    test-name-can-be-referenced = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.foo = {
          funny.names = [ den.aspects.foo.meta.name ];
        };

        expr = funnyNames den.aspects.foo;
        expected = [ "den.aspects.foo" ];
      }
    );

    test-name-can-be-self-referenced = denTest (
      { den, funnyNames, ... }:
      {
        den.aspects.foo =
          { config, ... }:
          {
            funny.names = [ config.meta.name ];
          };

        expr = funnyNames den.aspects.foo;
        expected = [ "den.aspects.foo" ];
      }
    );

    test-meta-keys-at-host-aspect = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];

        den.aspects.foo =
          { host }:
          {
            nixos.environment.sessionVariables = {
              KEYS = lib.attrNames den.aspects.foo.meta.self.meta;
            };
          };

        expr = {
          inherit (igloo.environment.sessionVariables)
            KEYS
            ;
        };
        expected.KEYS = "collisionPolicy:file:handleWith:loc:name:provider:self";
      }
    );

    test-meta-keys-at-host-fixpoint = denTest (
      {
        den,
        igloo,
        lib,
        ...
      }:
      {
        den.hosts.x86_64-linux.igloo = { };
        den.aspects.igloo.includes = [ den.aspects.foo ];

        den.aspects.foo =
          { host }:
          { config, lib, ... }:
          {
            nixos.environment.sessionVariables = {
              KEYS = lib.attrNames config.meta;
            };
            meta.foo = 12;
          };

        expr = {
          inherit (igloo.environment.sessionVariables)
            KEYS
            ;
        };
        expected.KEYS = "collisionPolicy:file:foo:handleWith:loc:name:provider:self";
      }
    );

  };
}
