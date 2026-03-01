{
  certs.email = "francesco149@gmail.com"; # for automatic cert management

  # change these after deploying and bringing tailscale up on both machines.
  # check `tailscale ip` on each machine or `headscale nodes list` on the relay
  tailnet.mail = "100.64.0.1";
  tailnet.relay = "100.64.0.2";

  # public ip of your vps
  internet.relay = "198.46.149.19";

  # all of these point to internet.relay. see README.md for records setup
  domains.base = "headpats.uk";
  domains.mail = "mail.headpats.uk"; # PTR, spf1, mx records point to this
  domains.fqdn = "smtp.headpats.uk"; # must be different than the relay's
  domains.headscale = "hs.headpats.uk";

  mail.master = "loli"; # this user is aliased to postmaster
  mail.users = [
    "loli" # remember to generate hashed password files, see README
  ];

  # remove my ssh keys, add your own.
  # unless you want to give me access to your server ;)
  ssh.authorized-keys = [
    # workstation
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGv7sF12IrUHiIV4VT6e5x2S0WSil3f4bBt4AwYG7mA/ headpats@bazzite"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOggpEtx3bYTi/Qr59aaAi2RyAwvsBv04tyPVPGd/9j4 headpats@DESKTOP-2FRVAC7"
    # streaming pc
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNTISALC2cQaRAtgsLUK1V5Ko1s8eO8/1WHkdnH/ifiglrbftmfZ72HHSSht54lUsRR6CvGnDRQPJfySI1xCHhg= loli@HCUP"
    # laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJqIAtWyhxUgDI8G9oSyzxEtMggUkBcOcYBfonad6RI deeznuts@MOOPLASTORY"
    # proxmox
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIRmdPK45tD5E9LWrQlU0Cvh/l/31ceXT6tlwBBLwG4 headpats@proxmox"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3GITt7Z4V/IwnPKmFEpz7KVXXkcyiDaZvg59lbmcTlamMuHopMGXEdh7u1qKWqkr+agNxaqWpAConEsCwX5GFRaOe/LQFHVneOArXWS/p1xw+ywxlgA8NabsQUlg7GsKW5LbJyALZiS5CCTdEz2yCk/NauR9MMXUNW/ZJEN2QrYNZloYiRLY8XCNMNZPwhaPH4rd/K1Am1ZuTPlyjTfkTEyLRCF025KIMNe16ll2DT9HxHE8dFsenxpj2Jgt9e7wch5Pg5h6L4S83++fEYBxsdXrEPC2Yz7WYc6io7dLk31kUGH0QpCelLyELiWpltnQ8OBJKpHBVQpA5HlQtK5I4uujRG0gtVAMflwkqwh69ahK4fy0+8ESUhC4ACH4AqURFrEOqamXwPIqHgU+8zoS2+kmKD0LmU8O2RSE0CUw55b2f358QACA94QfQX3gPonvdP1gQjK9ODcFrApnDaqyK1kZ4Wno7W1NrOkJE7rbukRaivp0conSKgaOGNFs3tkkSF6HPjddKqHNGMRttZp3d5HoK78h+0EBbryAiQ5EFIEj27eO/qG2iEykXN7rig1ezVkW9kA9vcP3HJyePpTPQQteEdL7ztLZfuUDmr8KNzoPK/L+X1kS+oRS8EjHVOvSVaWkRWGeJn1/8yKKUWBQG96mlPLkeKX7PYlKaCZxeSQ== root@proxmox"
  ];

  # enable beszel agent for monitoring
  # (gets routed through tailscale and exposed locally at the mail server)
  monitoring = true;

  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";

  systems.dev = "x86_64-linux"; # machine you're deploying from
  systems.mail = "x86_64-linux";
  systems.relay = "x86_64-linux";

  # ###########################################################################
  # probably never change these unless you know what you're doing.
  # for example, changing smtp-relay won't change the port on postfix.
  # these are purely for labeling at the moment

  ports.smtp-relay = 25;
  ports.http = 80;
  ports.https = 443;
  ports.smtp = 587;
  ports.imap = 993;
  ports.managesieve = 4190;
  ports.beszel-agent = 45876;
  ports-udp.headscale = 41641;
  ports.headscale-internal = 8080;

  tailnet.prefixes = [ "100.64.0.0/10" ];
}
