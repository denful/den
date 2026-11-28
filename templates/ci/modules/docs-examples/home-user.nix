# "The home's user" in docs/src/content/docs/guides/standalone-home-manager.mdx:
# one registry field read as `user` in a standalone home and on a host.
{ denTest, ... }:
{
  flake.tests.docs-home-user = {
    test-one-field-reaches-home-and-host = denTest (
      {
        den,
        config,
        tuxHm,
        ...
      }:
      {
        den.default.includes = [ den.provides.define-user ];
        den.users.tux.email = "tux@example.com";

        den.homes.x86_64-linux.tux = { };
        den.hosts.x86_64-linux.igloo.users.tux = { };

        den.aspects.tux.homeManager =
          { user, ... }:
          {
            programs.git.userEmail = user.email;
          };

        expr = {
          home = config.flake.homeConfigurations.tux.config.programs.git.userEmail;
          host = tuxHm.programs.git.userEmail;
        };
        expected = {
          home = "tux@example.com";
          host = "tux@example.com";
        };
      }
    );
  };
}
