{ inputs, lib, ... }:
{
  flake-file.inputs.den.url = lib.mkDefault "github:denful/den";
  imports = [ (inputs.den.flakeModule or { }) ];
}
