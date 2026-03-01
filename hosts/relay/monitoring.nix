{ ... }:
{
  services.beszel.agent = {
    enable = true;
    environmentFile = "/etc/secrets/beszel-agent";
    openFirewall = false; # we use headscale
  };

  systemd.services.beszel-agent = {
    serviceConfig.SupplementaryGroups = [ "beszel-secrets" ];
  };
}
