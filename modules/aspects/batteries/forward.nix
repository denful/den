{ den, ... }:
let
  description = ''
    An aspect that imports all modules defined for `from` class
    into a target `into` submodule.

    This can be used to create custom Nix classes that help
    people separating concerns on huge module hierarchies.

    For example, using a new `user` class that forwards all its
    settings into `users.users.<userName>` allows:

      den.aspects.alice.nixos.users.users.alice.isNormalUser = true;

    to become:

      den.aspects.alice.user.isNormalUser = true;


    This is exactly how `homeManager` class support is implemented in Den.
    See home-manager/hm-integration.nix.

    Den also provides the mentioned `user` class (`den.batteries.os-user`) for setting 
    NixOS/Darwin options under `users.users.<userName>` at os-level.

    Any other user-environments like `nix-maid` or `hjem` or user-custom classes
    are easily implemented using `den.batteries.forward`.

    Note: `den.batteries.forward` returns an aspect that needs to be included for
    the new class to exist.

    See templates/ci/modules/guarded-forward.nix, templates/ci/modules/forward-from-custom-class.nix
    See also: https://github.com/denful/den/issues/160
  '';

in
{
  den.batteries.forward = {
    inherit description;
    __functor = _self: den.lib.forward.forwardEach;
  };
}
