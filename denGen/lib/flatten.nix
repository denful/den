# #59 `flatten args ms`: class content (`{ imports = [ fn ]; _file; }`) as one plain value, for an
# `into` that writes into a config-only submodule (users.users.<n>). args = the calling module's args.
# shortcut: content that sets `config`/`options` or imports a path is passed as is; resolve those when a fleet needs it.
denGen: {
  flatten =
    args: ms:
    let
      lib = denGen.genLib;
      go =
        m:
        if lib.isFunction m then
          go (m (builtins.intersectAttrs (lib.functionArgs m) args))
        else if builtins.isAttrs m && !(m ? _type) then
          lib.mkMerge (
            [
              (removeAttrs m [
                "imports"
                "_file"
                "key"
              ])
            ]
            ++ map go (m.imports or [ ])
          )
        else
          m;
    in
    lib.mkMerge (map go ms);
}
