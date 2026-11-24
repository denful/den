# A host aspect's key named after a user (`den.aspects.igloo.tux`) reaches
# that user only (#788). `host-to-users` used to include it at host scope, so
# its home content reached every user on the host. It's now part of the user's
# own aspect on that host, so the identity cells below pin what that
# composition must leave unchanged.
{ denTest, lib, ... }:
let
  two =
    { den, ... }:
    {
      den.default.includes = [ den.provides.define-user ];
      den.hosts.x86_64-linux.igloo.users = {
        tux = { };
        pingu = { };
      };
    };
  marker = hm: hm.home.sessionVariables.PERHOST or "absent";
in
{
  flake.tests.host-nested-user-aspect-scope = {

    test-reaches-only-the-named-user = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "tux";
        expr = {
          tux = marker tuxHm;
          pingu = marker pinguHm;
        };
        expected = {
          tux = "tux";
          pingu = "absent";
        };
      }
    );

    # Its user-class content is the named user's too.
    test-user-class-content-is-per-user = denTest (
      { den, igloo, ... }:
      {
        imports = [ two ];
        den.hosts.x86_64-linux.igloo.users.pingu.classes = [ "user" ];
        den.aspects.igloo.pingu.user.description = "pingu on igloo";
        expr = {
          pingu = igloo.users.users.pingu.description;
          tux = igloo.users.users.tux.description;
        };
        expected = {
          pingu = "pingu on igloo";
          tux = "";
        };
      }
    );

    # Each user's key stays apart, two users at once.
    test-two-users-two-keys = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo = {
          tux.homeManager.home.sessionVariables.PERHOST = "tux";
          pingu.homeManager.home.sessionVariables.PERHOST = "pingu";
        };
        expr = {
          tux = marker tuxHm;
          pingu = marker pinguHm;
        };
        expected = {
          tux = "tux";
          pingu = "pingu";
        };
      }
    );

    # The key is read in the user's scope, so a parametric one sees the user.
    test-parametric-key-sees-the-user = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux = (
          { user, ... }:
          {
            homeManager.home.sessionVariables.PERHOST = "for-${user.name}";
          }
        );
        expr = {
          tux = marker tuxHm;
          pingu = marker pinguHm;
        };
        expected = {
          tux = "for-tux";
          pingu = "absent";
        };
      }
    );

    # -- identity: the composite user aspect changes nothing keyed by it --

    test-provides-to-host-still-delivers = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "tux";
        den.aspects.tux.provides.igloo.homeManager.home.sessionVariables.VIA_PROVIDES = "tux";
        expr = {
          tux = tuxHm.home.sessionVariables.VIA_PROVIDES or "absent";
          pingu = pinguHm.home.sessionVariables.VIA_PROVIDES or "absent";
        };
        expected = {
          tux = "tux";
          pingu = "absent";
        };
      }
    );

    test-user-at-host-still-applies = denTest (
      {
        den,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "tux";
        den.aspects."tux@igloo".homeManager.home.sessionVariables.AT_HOST = "tux@igloo";
        expr = {
          tux = tuxHm.home.sessionVariables.AT_HOST or "absent";
          pingu = pinguHm.home.sessionVariables.AT_HOST or "absent";
        };
        expected = {
          tux = "tux@igloo";
          pingu = "absent";
        };
      }
    );

    # hasAspect on the user's own aspects answers as before, from the host and
    # from the user: the host doesn't see a user's includes, the user does.
    test-has-aspect-unchanged = denTest (
      {
        den,
        igloo,
        tuxHm,
        pinguHm,
        ...
      }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "tux";
        den.aspects.feature.homeManager = { };
        den.aspects.tux.includes = [ den.aspects.feature ];
        den.schema.host.includes = [
          (
            { host, ... }:
            {
              nixos.environment.etc."host-has-feature".text = lib.boolToString (
                host.hasAspect den.aspects.feature
              );
            }
          )
        ];
        den.schema.user.includes = [
          (
            { host, user }:
            {
              homeManager.home.sessionVariables.HAS_FEATURE = lib.boolToString (
                user.hasAspect den.aspects.feature
              );
            }
          )
        ];
        expr = {
          host = igloo.environment.etc."host-has-feature".text;
          tux = tuxHm.home.sessionVariables.HAS_FEATURE;
          pingu = pinguHm.home.sessionVariables.HAS_FEATURE;
        };
        expected = {
          host = "false";
          tux = "true";
          pingu = "false";
        };
      }
    );

    # A user with no key on the host keeps exactly its own aspect.
    test-user-without-key-keeps-its-aspect = denTest (
      { den, ... }:
      {
        imports = [ two ];
        den.aspects.igloo.tux.homeManager.home.sessionVariables.PERHOST = "tux";
        expr = {
          name = den.hosts.x86_64-linux.igloo.users.pingu.aspect.name;
          isOwn = den.hosts.x86_64-linux.igloo.users.pingu.aspect == den.aspects.pingu;
        };
        expected = {
          name = "pingu";
          isOwn = true;
        };
      }
    );
  };
}
