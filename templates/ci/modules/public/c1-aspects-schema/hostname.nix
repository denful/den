{ denTest, ... }:
{
  flake.tests.hostname = {

    test-sets-hostname = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.default.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-sets-custom-hostname = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo = {
          hostName = "sahara";
          users.tux = { };
        };

        den.default.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "sahara";
      }
    );

    test-included-in-host = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.igloo.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-included-in-user = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-included-in-host-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # NOTE: foo needs parametric to pass over `{host}` context into den.provides.hostname
        den.aspects.foo = den.lib.parametric {
          includes = [ den.provides.hostname ];
        };

        den.aspects.igloo.includes = [ den.aspects.foo ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-included-in-user-includes = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };

        # NOTE: foo needs parametric to pass over `{host}` context into den.provides.hostname
        den.aspects.foo = den.lib.parametric {
          includes = [ den.provides.hostname ];
        };

        den.aspects.tux.includes = [ den.aspects.foo ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

  };
}
