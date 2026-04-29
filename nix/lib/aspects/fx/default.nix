{
  lib,
  den,
  ...
}:
{
  identity = import ./identity.nix { inherit lib den; };
  constraints = import ./constraints.nix { inherit lib den; };
  includes = import ./includes.nix { inherit lib den; };
  trace = import ./trace.nix { inherit lib den; };
  handlers = import ./handlers { inherit lib den; };
  aspect = import ./aspect.nix { inherit lib den; };
  pipeline = import ./pipeline.nix { inherit lib den; };
}
