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
  contentUtil = import ./content-util.nix { inherit lib; };
  pipeline = import ./pipeline.nix { inherit lib den; };
  wrapClasses = import ./wrap-classes.nix { inherit lib den; };
  keyClassification = import ./key-classification.nix { inherit lib den; };
  argClass = import ./arg-class.nix { inherit lib den; };
  edgeTrace = import ./edge-trace.nix { inherit lib den; };
  edges = {
    edge = import ./edges/edge.nix { inherit lib; };
    pi = import ./edges/pi.nix { inherit lib; };
    toposort = import ./edges/toposort.nix { inherit lib; };
    materialize = import ./edges/materialize.nix { inherit lib den; };
    materializeUnified = import ./edges/materialize-unified.nix { inherit lib den; };
    instantiateSubtree = import ./edges/instantiate-edges.nix { inherit lib den; };
  };
}
