{ config, ... }:
{

  # tunnel beszel agent port to the remote relay through headscale

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream beszel_agent {
        server ${config.nmr.tailnet.relay}:${toString config.nmr.ports.beszel-agent};
      }

      server {
        listen ${toString config.nmr.ports.beszel-agent};
        proxy_pass beszel_agent;
      }
    '';
  };

  networking.firewall = {
    allowedTCPPorts = [
      config.nmr.ports.beszel-agent
    ];
  };

}
