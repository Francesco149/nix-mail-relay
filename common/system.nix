{ config, ... }:

{
  time.timeZone = config.nmr.time.timeZone;
  i18n.defaultLocale = config.nmr.i18n.defaultLocale;

  security.acme = {
    acceptTerms = true;
    defaults.email = config.nmr.certs.email;
  };

  networking.firewall.enable = true;
}
