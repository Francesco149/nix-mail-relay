{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    simple-nixos-mailserver = {
      url = "gitlab:simple-nixos-mailserver/nixos-mailserver/nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs =
    {
      self,
      nixpkgs,
      simple-nixos-mailserver,
      deploy-rs,
      ...
    }:
    let

      # this module contains all the global settings in config.nix
      config-module = import ./modules/config.nix;
      inherit (config-module) nmr;
      pkgs = nixpkgs.legacyPackages.${nmr.systems.dev};

    in
    {

      # this is for the deploy helper, so that it automatically knows the ips and architectures
      deploy.nodes = builtins.listToAttrs (
        map
          (name: {
            inherit name;
            value = {
              hostname = nmr.tailnet.${name};
              profiles.system = {
                user = "root";
                sshUser = "root";
                path = deploy-rs.lib.${nmr.systems.${name}}.activate.nixos self.nixosConfigurations.${name};
              };
            };
          })
          [
            "mail"
            "relay"
          ]
      );

      # silences a warning about deploy, and runs deployment validation
      # This is highly advised, and will prevent many possible mistakes
      checks = builtins.mapAttrs (_: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;

      nixosConfigurations =
        let
          s = name: modules: {
            inherit name;
            value = nixpkgs.lib.nixosSystem {
              modules = [
                { nixpkgs.hostPlatform = nmr.systems.${name}; }
                config-module.nixosModule
                ./common/system.nix
                ./common/ssh.nix
                ./common/tailscale.nix
                ./hosts/${name}/hardware-configuration.nix
                ./hosts/${name}/configuration.nix
                ./hosts/${name}/${name}.nix
              ]
              ++ (
                if nmr.monitoring then
                  [
                    ./hosts/${name}/monitoring.nix
                  ]
                else
                  [ ]
              )
              ++ modules;
            };
          };
        in
        builtins.listToAttrs [
          (s "mail" [ simple-nixos-mailserver.nixosModules.mailserver ])
          (s "relay" [ ])
        ];

      # this is the dev shell you enter when you run `nix develop`
      devShells.${nmr.systems.dev}.default = pkgs.mkShell {
        shellHook = ''
          export NIX_CONFIG="experimental-features = nix-command flakes"
          export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'

          exec fish --init-command '
            # prompt
            function fish_prompt
              set_color purple --bold
              echo -n "[headpats-dev] "
              set_color green
              echo -n (prompt_pwd)
              set_color normal
              echo -n " λ "
            end

            # fzf keybinds
            fzf --fish | source

            # carapace completions
            carapace _carapace fish | source

            function diff-system
              set host $argv[1]
              if test -z "$host"
                echo "Usage: diff-system <machine>"
                return 1
              end
              set machine (nix eval --raw .#deploy.nodes.$host.hostname)
              set new_path (nom build .#nixosConfigurations.$host.config.system.build.toplevel --no-link --print-out-paths 2>&1 | tail -1)
              set current (ssh root@$machine readlink /run/current-system)
              nix copy --no-check-sigs --from ssh-ng://root@$machine $current
              nvd diff $current $new_path
            end
          '
        '';

        packages = with pkgs; [
          nixfmt-rfc-style
          nil # nix LSP
          nix-output-monitor # nicer nixos-rebuild output
          nvd # show package diff before deploy
          statix # linter
          deadnix # find dead code
          fzf # fuzzy search command historu, files, directories
          carapace # shell completion with fuzzy matching
          fish

          # remote deployment helper
          deploy-rs.packages.${nmr.systems.dev}.deploy-rs

          (neovim.override {
            configure = {
              packages.myPlugins = with vimPlugins; {
                start = [
                  conform-nvim
                  blink-cmp
                ];
              };
              customRC = ''
                set tabstop=2
                set shiftwidth=2
                set expandtab

                lua << EOF
                  vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float)
                  vim.opt.clipboard = "unnamedplus"

                  vim.g.clipboard = {
                    name = "OSC 52",
                    copy = {
                      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
                      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
                    },
                    paste = {
                      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
                      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
                    },
                  }

                  vim.lsp.config('nil_ls', {
                    cmd = { 'nil' },
                    filetypes = { 'nix' },
                    root_markers = { 'flake.nix', '.git' },
                  })
                  vim.lsp.enable('nil_ls')

                  require("blink.cmp").setup({
                    keymap = { preset = 'default' },
                    sources = {
                      default = { 'lsp', 'path', 'buffer' },
                    },
                  })

                  require("conform").setup({
                    formatters_by_ft = {
                      nix = { "nixfmt" },
                    },
                    format_on_save = {
                      timeout_ms = 500,
                      lsp_fallback = true,
                    },
                  })

                EOF
              '';
            };
          })
        ];
      };
    };
}
