{ config, ... }:
{
  # relay only for outbound mail, so it comes from the vps ip
  # the relay's domain needs to be different than the domain used by the mail server at home.
  # this is to avoid a loop.
  # for example:
  # - mail server at home: smtp.headpats.uk (also points to vps ip)
  # -    relay on the vps: mail.headpats.uk (needs to match ptr)
  services.postfix.settings.main = {
    relayhost = [
      "${config.nmr.tailnet.relay}:${toString config.nmr.ports.smtp-relay}"
    ];
    myhostname = config.nmr.domains.fqdn;
  };

  mailserver = {
    enable = true;
    stateVersion = 3;
    fqdn = config.nmr.domains.fqdn;
    domains = [ config.nmr.domains.base ];
    certificateScheme = "acme-nginx"; # auto let's encrypt certificate. NOTE: leave port 80 unbound
    enableManageSieve = true; # enables filters using sieve scripts
    enableSubmission = true; # STARTTLS on port 587/tcp disabled by default since 25.11
    enableSubmissionSsl = true; # ^

    loginAccounts = builtins.listToAttrs (
      map (user: {
        name = "${user}@${config.nmr.domains.base}";
        value = {
          hashedPasswordFile = "/var/lib/secrets/${user}-hashed-password";
        }
        // (
          if user == config.nmr.mail.master then
            {
              aliases = [ "postmaster@${config.nmr.domains.base}" ];
            }
          else
            { }
        );
      }) config.nmr.mail.users
    );

  };

  # these are open to the home lan for mail clients to use. not exposed to the internet
  networking.firewall = {
    allowedTCPPorts = [
      config.nmr.ports.imap
      config.nmr.ports.smtp
      config.nmr.ports.managesieve
    ];
  };

}
