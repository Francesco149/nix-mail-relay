{ config, ... }:

{
  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--login-server=https://${config.nmr.domains.headscale}"
    ];
  };
}
