denGen: {
  content.classModule =
    args: v:
    if builtins.isFunction v then (denGen.gen.bind.wrap { bindings = args; } v).module else v;
}
