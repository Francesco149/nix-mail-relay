{ ... }:

{
  # adjust based on what's in your stock /etc/nixos/configuration.nix
  # depending on the installation method these settings will differ slightly.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "nix-mail";
  networking.networkmanager.enable = true;

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 1024;
    }
  ];

  system.stateVersion = "25.11";

}
