# Hetzner Cloud provider configuration.
#
# This aspect is included in den.default so every host gets it.
# The terranix module declares the hcloud provider and variable.
{ den, ... }:
{
  den.aspects.hcloud-provider = {
    terranix = {
      terraform.required_providers.hcloud = {
        source = "hetznercloud/hcloud";
        version = "~> 1.45";
      };

      variable.hcloud_token = {
        type = "string";
        sensitive = true;
      };

      provider.hcloud.token = "\${var.hcloud_token}";
    };
  };

  den.default.includes = [ den.aspects.hcloud-provider ];
}
