{ denTest, ... }:
{
  flake.tests.top-level-parametric = {

    test-user-aspect-with-context = denTest (
      { den, igloo, ... }:
      let
        custom-user-config =
          { user, ... }:
          {
            nixos.users.users.tux.description = user.userName;
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ custom-user-config ];

        expr = igloo.users.users.tux.description;
        expected = "tux";
      }
    );

    test-host-aspect-with-context = denTest (
      { den, igloo, ... }:
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.igloo.includes = [ den.provides.hostname ];

        expr = igloo.networking.hostName;
        expected = "igloo";
      }
    );

    test-user-and-host-context = denTest (
      { den, igloo, ... }:
      let
        from-both =
          { host, user, ... }:
          {
            nixos.users.users.tux.description = "${user.userName}@${host.name}";
          };
      in
      {
        den.hosts.x86_64-linux.igloo.users.tux = { };
        den.aspects.tux.includes = [ from-both ];

        expr = igloo.users.users.tux.description;
        expected = "tux@igloo";
      }
    );

  };
}
