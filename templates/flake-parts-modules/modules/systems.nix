{ den, ... }:
{
  # The flake-parts `systems` setting can be automatically generated
  # from your host aspects.
  #
  # NOTE: If you're having trouble building this
  # template on your machine, make sure you've created a host
  # that matches your architecture in `./den.nix`.
  systems = builtins.attrNames den.hosts;
}
