# See usage at: templates/example/modules/aspects/{defaults.nix,alice.nix,igloo.nix}
{ den, lib, ... }:
let

  description = ''
    Allows hosts and users to contribute configuration **to each other** 
    through `provides`.

    This battery implements an aspect "routing" pattern.

    Be sure to read diagrams for the Host context pipeline:
    https://den.oeiuwq.com/guides/mutual

    ## Usage

      den.hosts.x86_64-linux.igloo.users.tux = { };
      den.schema.user.includes = [ den.provides.mutual-provider ];

      # user aspect provides to specific host or to all where it lives
      den.aspects.tux = {
        provides.igloo.nixos.programs.emacs.enable = true;
        provides.to-hosts = { host, ... }: {
          nixos.programs.nh.enable = host.name == "igloo";
        };
      };

      # host aspect provides to specific user or to all its users
      den.aspects.igloo = {
        provides.alice.homeManager.programs.vim.enable = true;
        provides.to-users = { user, ... }: {
          homeManager.programs.helix.enable = user.name == "alice";
        };
      };
  '';

  find-mutual = from: to: from.aspect.provides.${to.aspect.name} or { };
  to-hosts = from: from.aspect.provides.to-hosts or { };
  to-users = from: from.aspect.provides.to-users or { };

  mutual-user-user = host: user: {
    includes = map (from: {
      includes = [
        (find-mutual from user)
        (to-users from)
      ];
    }) (builtins.filter (u: u.id_hash != user.id_hash) (builtins.attrValues host.users));
  };

  mutual-host-user =
    { host, user }:
    {
      inherit description;
      includes = [
        (find-mutual host user)
        (find-mutual user host)
        (to-users host)
        (to-hosts user)
        (mutual-user-user host user)
      ];
    };

  inherit (den.lib.aspects.fx.handlers) constantHandler;

  # For standalone homes bound to a host (name@host), resolve the
  # host-named provider with host/user context from the home entity.
  # Without this, the provider's { host, user } args would be unresolvable
  # since the home pipeline only has { home } in scope.
  mutual-standalone-home =
    { home }:
    if home.hostName == null then
      { }
    else
      let
        prov = home.aspect.provides.${home.hostName} or null;
        ctx = lib.filterAttrs (_: v: v != null) {
          host = home.host or null;
          user = home.user or null;
        };
      in
      if prov == null then
        { }
      else
        prov
        // lib.optionalAttrs (ctx != { }) {
          __scopeHandlers = constantHandler ctx;
        };

in
{
  den.provides.mutual-provider = {
    includes = [
      mutual-host-user
      mutual-standalone-home
    ];
  };
}
