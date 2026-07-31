# Issue #644: a host-attached PARAMETRIC aspect feeding a declaring custom
# forward class delivers every user's content to every user.
#
# The aspect is fanned per user at the host scope, so the host's `myshell`
# bucket holds all users' emissions. A child-scope complex forward then pulls
# that root bucket wholesale (`getCollectedSource`), handing each user the union
# instead of their own slice. Silent — the result is a wrong configuration, not
# an error.
{ denTest, ... }:
let
  shellClass =
    den: lib:
    { class, aspect-chain }:
    den._.forward {
      each = lib.singleton class;
      fromClass = _: "myshell";
      intoClass = _: "homeManager";
      intoPath = _: [
        "programs"
        "bash"
      ];
      fromAspect = _: lib.last aspect-chain;
      guard = { options, ... }: options ? programs.bash;
    };

  aliasesOf =
    lib: igloo: user:
    lib.attrNames (igloo.home-manager.users.${user}.programs.bash.shellAliases or { });
in
{
  flake.tests.deadbugs.issue-644-parametric-host-forward-per-user = {

    # No battery: no spawn at all, so the leak is attributable to the parent
    # pipeline's forward source collection alone.
    test-parametric-host-content-stays-per-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.includes = [ (shellClass den lib) ];

        den.aspects.per-user =
          { user, ... }:
          {
            myshell.shellAliases.${user.name} = "mine";
          };

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [ den.aspects.per-user ];

        expr = {
          tux = aliasesOf lib igloo "tux";
          pingu = aliasesOf lib igloo "pingu";
        };
        expected = {
          tux = [ "tux" ];
          pingu = [ "pingu" ];
        };
      }
    );

    # Same shape with host-aspects on — the projection path must agree.
    test-parametric-host-content-stays-per-user-with-battery = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.includes = [
          den._.host-aspects
          (shellClass den lib)
        ];

        den.aspects.per-user =
          { user, ... }:
          {
            myshell.shellAliases.${user.name} = "mine";
          };

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [ den.aspects.per-user ];

        expr = {
          tux = aliasesOf lib igloo "tux";
          pingu = aliasesOf lib igloo "pingu";
        };
        expected = {
          tux = [ "tux" ];
          pingu = [ "pingu" ];
        };
      }
    );

    # CONTROL: non-parametric host content through the same forward is shared by
    # design and must still reach both users.
    test-static-host-content-reaches-every-user = denTest (
      {
        den,
        lib,
        igloo,
        ...
      }:
      {
        den.default.includes = [ (shellClass den lib) ];

        den.aspects.shared.myshell.shellAliases.ll = "ls -l";

        den.hosts.x86_64-linux.igloo.users = {
          tux = { };
          pingu = { };
        };

        den.aspects.igloo.includes = [ den.aspects.shared ];

        expr = {
          tux = aliasesOf lib igloo "tux";
          pingu = aliasesOf lib igloo "pingu";
        };
        expected = {
          tux = [ "ll" ];
          pingu = [ "ll" ];
        };
      }
    );

  };
}
