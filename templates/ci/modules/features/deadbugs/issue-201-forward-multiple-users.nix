{ denTest, ... }:
{

  # See den#201
  flake.tests.deadbugs-issue-201 = {

    test-forward-two-users = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      let
        inherit (den.lib.policy) include;
      in
      {
        den.default.homeManager.home.stateVersion = "25.11";

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.policies.to-users =
          { host, user, ... }:
          [
            (include {
              includes = [
                den.provides.define-user
                den.aspects.set-user-desc
              ];
            })
          ];
        den.aspects.igloo.includes = [ den.aspects.igloo.policies.to-users ];
        den.aspects.tux.includes = [ den.provides.primary-user ];

        den.aspects.set-user-desc =
          { host, user }:
          {
            ${host.class}.users.users.${user.userName}.description = "User ${user.userName}";
          };

        expr = {
          tux = igloo.users.users.tux.description;
        };
        expected = {
          tux = "User tux";
        };
      }
    );
  };

}
