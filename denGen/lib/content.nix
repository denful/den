denGen:
let
  denArgs = [ "host" "user" ];
  # only den ctx args trigger binding; nixpkgs-style module fns pass through untouched
  isDen = f: builtins.any (n: builtins.hasAttr n (builtins.functionArgs f)) denArgs;
  walk =
    args: v:
    if builtins.isFunction v then
      (if isDen v then (denGen.gen.bind.wrap { bindings = args; } v).module else v)
    else if builtins.isAttrs v && v ? imports && builtins.isList v.imports then
      v // { imports = map (walk args) v.imports; }
    else
      v;
in
{
  content.classModule = walk;
}
