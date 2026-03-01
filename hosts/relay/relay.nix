{ config, ... }:
{

  # this is what links everything together: headscale is a self-hosted tailscale server.
  # it estabilishes a private network between the mail server, the relay and whichever of
  # my machines I decide to run a tailscale client on and point it at this server.

  # clients are assigned a special tailnet ip and can see eachother, as if on the same lan,
  # without having to open any inbound ports to the internet.

  services.headscale = {
    enable = true;
    port = config.nmr.ports.headscale-internal;
    settings = {
      database = {
        type = "sqlite3";
        sqlite.path = "/var/lib/headscale/db.sqlite";
      };
      server_url = "https://${config.nmr.domains.headscale}";
      listen_addr = "127.0.0.1:${toString config.nmr.ports.headscale-internal}"; # nginx will route
      ip_prefixes = config.nmr.tailnet.prefixes;
      noise.private_key_path = "/var/lib/headscale/noise_private.key";
      dns = {
        magic_dns = false;
        override_local_dns = false;
      };
      # if there's serious routing/connectivity issues, the connection will go through
      # tailscale's DERP server as a fallback.
      derp = {
        urls = [ "https://controlplane.tailscale.com/derpmap/default" ];
        auto_update_enabled = true;
        update_frequency = "24h";
      };
    };
  };

  # we send all mail through this relay so it comes from the trusted vps ip.
  # it is only accessible through tailscale.

  services.postfix = {
    enable = true;
    settings.main = {
      myhostname = config.nmr.domains.mail;
      inet_interfaces = config.nmr.tailnet.relay; # bind only to tailnet ip
      inet_protocols = "ipv4";
      mynetworks = config.nmr.tailnet.prefixes;
      relay_domains = null;
      smtp_bind_address = config.nmr.internet.relay; # send outbound from public IP
    };
  };

  # if tailscale gos down, stop postfix. only start after tailscale goes up
  systemd.services.postfix = {
    after = [
      "tailscaled.service"
      "sys-subsystem-net-devices-tailscale0.device"
    ];
    wants = [ "tailscaled.service" ];
    bindsTo = [ "sys-subsystem-net-devices-tailscale0.device" ];
  };

  # nginx is acting as a reverse proxy which routes all connections to their destination.
  # the stream proxy is great for tunneling ports over tailnet

  services.nginx = {
    enable = true;

    # NOTE: we can't use port 80 because it's used for acme challenges for the certs.
    #       make sure onlySSL is true to not try to grab port 80

    virtualHosts.${config.nmr.domains.headscale} = {
      onlySSL = true;
      enableACME = true;

      # headscale wants to be the root location so we can't do something like /headscale/
      # but we can do hs.domain.example
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.nmr.ports.headscale-internal}";

        # headscale uses websockets for the control protocol.
        # we also have to disable buffering for the websockets to work properly.
        # set longer timeouts so the tailscale connection doesn't die if it lags.

        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          keepalive_timeout 3600s;
        '';
      };
    };

    # we don't need to open submission and imaps ports to the internet.
    # we'll access those at home only or through headscale.
    # same for managesieve

    streamConfig = ''
      upstream mail_smtp {
        server ${config.nmr.tailnet.mail}:${toString config.nmr.ports.smtp-relay};
      }

      upstream mail_http {
        server ${config.nmr.tailnet.mail}:${toString config.nmr.ports.http};
      }

      server {
        listen ${config.nmr.internet.relay}:${toString config.nmr.ports.smtp-relay};
        proxy_pass mail_smtp;
        proxy_buffer_size 16k;
      }

      server {
        listen ${config.nmr.internet.relay}:${toString config.nmr.ports.http};
        proxy_pass mail_http;
      }
    '';
  };

  networking.firewall = {
    allowedTCPPorts = [
      config.nmr.ports.smtp-relay
      config.nmr.ports.http
      config.nmr.ports.https
    ];
    allowedUDPPorts = [
      config.nmr.ports-udp.headscale
    ];
  };

}
