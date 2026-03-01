#
# XXX: this is a nice hack
# by exporting the plain attrset as a module, we get to:
# - have a simple uncluttered config.nix that we can edit (and that a noob could edit)
# - not have to import the config everywhere, it's just there as a module
#

let
  nmr = import ../config.nix;
in
{
  inherit nmr;
  nixosModule =
    { lib, ... }:
    {
      options.nmr = lib.mapAttrs (
        _: value:
        lib.mkOption {
          type = lib.types.anything;
          default = value;
        }
      ) nmr;
    };
}
