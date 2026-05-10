{
  den,
  lib,
  inputs,
  ...
}:
{
  den.lib.nvf.package =
    pkgs: vimAspect: ctx:
    (inputs.nvf.lib.neovimConfiguration {
      inherit pkgs;
      modules = [ (den.lib.nvf.module vimAspect ctx) ];
    }).neovim;

  den.lib.nvf.module =
    vimAspect: ctx:
    let
      # a custom `vim` class that forwards to `nvf.vim`
      vimClass =
        { class, aspect-chain }:
        den.batteries.forward {
          each = lib.singleton true;
          fromClass = _: "vim";
          intoClass = _: "nvf";
          intoPath = _: [ "vim" ];
          fromAspect = _: lib.head aspect-chain;
          adaptArgs = lib.id;
        };

      aspect = den.lib.parametric.fixedTo ctx {
        includes = [
          vimClass
          vimAspect
        ];
      };

      module = den.lib.aspects.resolve "nvf" aspect;
    in
    module;
}
