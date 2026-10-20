denGen:
let
  denArgs = [ "host" "user" ];
  # lowered inline includes (entry.nix) are setFunctionArgs functors, not lambdas
  isFn = v: builtins.isFunction v || (builtins.isAttrs v && v ? __functor && v ? __functionArgs);
  # only den ctx args trigger binding; nixpkgs-style module fns pass through untouched
  isDen = f: builtins.any (n: builtins.hasAttr n (denGen.genLib.functionArgs f)) denArgs;
  walk =
    args: v:
    if isFn v then
      (if isDen v then (denGen.gen.bind.wrap { bindings = args; } v).module else v)
    else if builtins.isAttrs v && v ? imports && builtins.isList v.imports then
      v // { imports = map (walk args) v.imports; }
    else
      v;
in
{
  content.classModule = walk;
}
