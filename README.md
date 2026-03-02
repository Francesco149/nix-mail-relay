Self-hosted e-mail server using nixos-mailserver and a cheap VPS as a relay.

The actual mail server runs on my own hardware. The VPS is purely used as a relay and doubles
as a headscale server to access my home network when I'm away.

This has not been tested beyond my own deployment so you might need to fiddle with things
here and there, but it should be a good base for anyone trying to do anything similar.

Huge thanks to the [nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)
project for doing the heavy lifting of putting together a reliable and easy to set up mail server solution.

# Architecture

Arrows point the way the ports need to be open.

```
         home LAN         |          internet
                          |
+----------------------+  |  +----------------------+
|     home server      |  |  |         vps          |
|   PTR (can't have)   |  |  | PTR mail.headpats.uk |
|   IP  (dynamic)      |  |  | IP  x.x.x.x          |
|                      | tcp |                      |
| +------------------+ | 443 | +------------------+ |
| | tailscale client |-------->| headscale server | |
| |    100.64.0.1    | |41641| +------------------+ |
| +------------------+ | udp |          |           |
|           |          |  |  | +------------------+ |
| +------------------+ |  |  | | tailscale client | | 25
| |   email server   | |  |  | |    100.64.0.2    |<--.
| | smtp.headpats.uk | |  |  | +------------------+ | |
| +------------------+ |  |  |          |           | |
+----------A-----------+  |  | +------------------+ | |
           | 993/587      |  | |   email relay    | | |
    +-------------+       |  | | mail.headpats.uk | | |
    | PC / Laptop |       |  | +------------------+ | |
    +-------------+       |  +----------|-----------+ |
                          |             V 25          |
                          |         +-------+         |
                          |         | gmail |---------'
                                    +-------+

                          "Okay, inbound email from x.x.x.x."

                          "PTR is mail.headpats.uk."

                          "mail.headpats.uk resolves back to x.x.x.x."

                          "PTR matches, SPF passes, DKIM valid,
                           looks good to me!"
```

# Overview

The steps below follow this order:

1. Buy and configure a VPS and domain.
2. Install NixOS on the VPS (relay).
3. Enter the dev environment and edit `config.nix`.
4. Deploy to the relay and bring tailscale up on it.
5. Update `tailnet.relay` in `config.nix` and redeploy the relay.
6. Install NixOS on the home server (mail).
7. Deploy to the mail server and bring tailscale up on it.
8. Update `tailnet.mail` in `config.nix` and redeploy both machines.
9. Set up the DKIM record and test.

# Setting Up the Relay
## VPS
Buy the cheapest VPS you can find that meets these requirements:
- You need to be able to set the PTR record to your domain.
- You must have port 25 open inbound and outbound.

1 vCPU and 1 GB RAM is all you need. My install sits at 6.24 GB disk and 260 MB RAM.
It could be smaller since I've messed around a bunch and didn't clean up.

I used RackNerd for ~$13/year with the New Year deals. Port 25 was open out of the box.
For the PTR record, I had to open a support ticket and they responded and changed it within 20 minutes.

You can either ask support before buying, or buy, test it, and open a ticket if it's blocked.

You can test outbound port 25 by running this from the VPS:

```sh
nc -zv gmail-smtp-in.l.google.com 25
```

Which should succeed.

You could also test inbound 25 by running this on your home machine:

```sh
nc -zv x.x.x.x 25
```

Where x.x.x.x is your VPS IP. This should get refused but not time out.

Realistically, if your VPS is blocking 25 it's going to be blocking it outbound.
Plus, your ISP could be blocking 25 outbound too, which would invalidate the test.

When setting up your VPS, just select some version of Ubuntu, which tends to be a good
base to convert to NixOS later. If your VPS provider happens to support custom ISOs
or NixOS, just install NixOS directly if it supports it (most don't).

I used Ubuntu 24.04 on RackNerd.

## Domain
Buy a domain. I used Cloudflare and got `headpats.uk` for $5.22/year.

For the purposes of this readme, mentally replace `headpats.uk` with your domain.

- Log into the Cloudflare dashboard, go to Domains → headpats.uk → DNS → Records.
- Set these DNS records, adding any that are missing. Replace x.x.x.x with your VPS IP.

| Type | Name          | Content                        | Proxy status | TTL  | Priority |
| ---- | ------------- | ------------------------------ | ------------ | ---- | -------- |
| A    | headpats.uk   | x.x.x.x                        | DNS only     | Auto | -        |
| A    | hs            | x.x.x.x                        | DNS only     | Auto | -        |
| A    | mail          | x.x.x.x                        | DNS only     | Auto | -        |
| A    | smtp          | x.x.x.x                        | DNS only     | Auto | -        |
| MX   | headpats.uk   | mail.headpats.uk               | DNS only     | Auto | 10       |
| TXT  | _dmarc        | v=DMARC1; p=none               | DNS only     | 2 hr | -        |
| TXT  | headpats.uk   | v=spf1 a:mail.headpats.uk -all | DNS only     | 2 hr | -        |

If your VPS has an IPv6 address, you can set a AAAA record, but this is optional, so probably wait until you have everything working.

**For the DKIM record, we will set it up once the mail server is up.**

Set your PTR record on your VPS to point to `mail.headpats.uk`.

Double-check with the [nixos-mailserver guide](https://nixos-mailserver.readthedocs.io/en/nixos-25.11/setup-guide.html).
It walks you through checking all the boxes with the records and verifying them.

Some of these records can take hours to propagate. **Remember to check them before you send mail.**

Here are my records for reference:

```
# host -t A mail.headpats.uk
mail.headpats.uk has address 198.46.149.19
# host -t AAAA mail.headpats.uk
mail.headpats.uk has no AAAA record
# host 198.46.149.19
19.149.46.198.in-addr.arpa domain name pointer mail.headpats.uk.
# host -t mx headpats.uk
headpats.uk mail is handled by 10 mail.headpats.uk.
# host -t TXT headpats.uk
headpats.uk descriptive text "v=spf1 a:mail.headpats.uk -all"
# host -t TXT _dmarc.headpats.uk
_dmarc.headpats.uk descriptive text "v=DMARC1; p=none"
```

## Installing NixOS
For the base OS, I selected Ubuntu 24.04 which tends to work well with the nixos-infect script.
You might have to do some reinstalls to test different distros and find one that works.

SSH into the VPS and log in with the root password you're given:

```sh
ssh root@x.x.x.x
ssh-keygen
exit
```

- **NOTE:** Don't forget to add your public SSH keys to `~/.ssh/authorized_keys` and/or `/root/.ssh/authorized_keys`.
- **NOTE:** Don't forget to check that you can SSH in without a password before closing the session.
- **NOTE:** If you forget, you will have to redeploy or use recovery mode, mount the rootfs, and add the keys.
  Ask me how I know.

## Convert to NixOS

```sh
curl https://raw.githubusercontent.com/elitak/nixos-infect/36f48d8feb89ca508261d7390355144fc0048932/nixos-infect | NIX_CHANNEL=nixos-25.11 bash -x

reboot
```

**FIXME:** Using an old pinned version of the script for now because of [a regression](https://github.com/elitak/nixos-infect/issues/255#issuecomment-3963186336).

Check that you can still SSH into the server.

## Entering the Dev Environment
From your home machine, [install nix](https://nix.dev/manual/nix/2.28/installation/) or just run NixOS:

```
nix-shell -p git --run git clone https://github.com/Francesco149/nix-mail-relay
cd nix-mail-relay
./env.sh
```

This should drop you into the `headpats-dev` shell. See the [Dev Environment](#dev-environment) section
at the bottom for an overview of the tools and workflows available.

## Configuration
Edit `config.nix` with your favorite editor. The shell comes with nvim preconfigured for nix.

Remove my SSH keys and add your own.

Check all the other .nix files in case something looks off. You don't want to blindly run my code, do you.

Copy over the hardware configuration (you could run `nixos-generate-config` on the server again for good measure):

```sh
scp root@x.x.x.x:/etc/nixos/hardware-configuration.nix hosts/relay/
```

Edit `hosts/relay/configuration.nix` to match what your `/etc/nixos/configuration.nix` looks
like on the fresh install.

I need to look into making this into a flake template so you don't have to overwrite my
hardware config and you can make your own flake repo based on it.

## Beszel Credentials
If you don't use Beszel for monitoring, just set `monitoring = false` in `config.nix`
and skip this section.

Otherwise, click "Add System" in the Beszel UI, stay on that screen to copy the key and token,
and put them in the env file like so:

```sh
ssh root@x.x.x.x
mkdir -p /etc/secrets
chmod 700 /etc/secrets

# or use your favorite text editor
cat > /etc/secrets/beszel-agent << EOF
KEY=ssh-ed25519 ...
TOKEN=...
EOF

groupadd beszel-secrets
chown root:beszel-secrets /etc/secrets/beszel-agent
chmod 600 /etc/secrets/beszel-agent
```

For the host/IP in the Beszel UI, you need the tailnet IP of the relay, which you won't
know until after the tailscale dance below. Use a placeholder for now and update it once
you have the IP.

In my setup, Beszel runs in a Docker container and I have an nginx stream proxy on the mail
server that forwards the Beszel port to the relay's tailnet IP. This is already wired up in
the flake.

## Deploy

```sh
deploy .#relay -- --hostname x.x.x.x
ssh root@x.x.x.x
reboot
```

## Tailscale Connectivity
### On the Relay
Let's bring tailscale up and get the relay side connected.

```sh
ssh root@x.x.x.x
headscale users create default
tailscale up --login-server https://hs.headpats.uk
```

This will give you a URL. Open it and copy the command it shows you.

Open another shell and run the command, but change the example `--user` part to `--user default`:

```sh
ssh root@x.x.x.x
headscale nodes register --key xxxxxxx_xxxxxxxxxxxxxxxx --user default
```

The tailscale up shell should say success.

Now get the tailnet IP:

```sh
tailscale ip
```

Update `tailnet.relay` in `config.nix` with that IP, then **redeploy the relay** so that
postfix and nginx pick up the correct address before the mail server tries to use it:

```sh
deploy .#relay
```

### On Your Computer
You should now be able to do the same tailscale dance from your home machine.

First, install and enable tailscale and its daemon (example for Arch; adapt to your distro):

```sh
sudo pacman -S tailscale
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
```

Then do the usual tailscale up dance:

```
[user@home:~]# sudo tailscale up --login-server https://hs.headpats.uk

To authenticate, visit:

	https://hs.headpats.uk/register/xxxxxxx_xxxxxxxxxxxxxxxx

Success.

[root@relay:~]# headscale nodes register --key xxxxxxx_xxxxxxxxxxxxxxxx --user default
Node home registered

[user@home:~]# tailscale ip
100.64.0.4
fd7a:115c:a1e0::4

[user@home:~]# ssh root@100.64.0.2
Last login: Sat Feb 28 17:08:13 2026 from 100.64.0.4

[root@relay:~]#
# We're in, through tailscale this time.

# We can take a look at all the nodes.
[root@relay:~]# headscale nodes list
ID | Hostname | Name     | MachineKey | NodeKey | User    | IP addresses                  | Ephemeral | Last seen           | Expiration          | Connected | Expired
2  | relay    | relay    | [xxxxx]    | [xxxxx] | default | 100.64.0.2, fd7a:115c:a1e0::2 | false     | 2026-02-28 03:05:02 | N/A                 | online    | no     
4  | home     | home     | [xxxxx]    | [xxxxx] | default | 100.64.0.4, fd7a:115c:a1e0::4 | false     | 2026-02-28 16:11:21 | N/A                 | online    | no     

```

# Mail Server
## Install NixOS and Set Up SSH
Install NixOS on the target machine. I like to use the graphical installer for convenience.

On the target machine, log in as root:

```sh
ssh-keygen
nano /etc/nixos/configuration.nix
```

Enable openssh and add your SSH key by adding to `/etc/nixos/configuration.nix`:

```nix
  users.users.root.openssh.authorizedKeys.keys = [
      "ssh-... <your ssh key>"
    ];
  }

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
    };
  };
```

Apply changes:

```sh
nixos-rebuild switch
```

Now you should be able to SSH into the machine.

## Prepare Secrets
```
ssh root@nix-mail.local

mkdir -p /var/lib/secrets
chmod 700 /var/lib/secrets

# must match the username you set in config.nix
nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt' > /var/lib/secrets/loli-hashed-password
chmod 600 /var/lib/secrets/loli-hashed-password
```

## Configuration
Copy over the hardware configuration (you could run `nixos-generate-config` on the server again for good measure):

```sh
scp root@nix-mail.local:/etc/nixos/hardware-configuration.nix hosts/mail/
```

Edit `hosts/mail/configuration.nix` to match what your `/etc/nixos/configuration.nix` looks
like on the fresh install.

## Deploy

**NOTE:** `nix-mail.local` relies on mDNS resolving on your LAN. If that doesn't work,
substitute the machine's local IP directly.

```sh
deploy .#mail -- --hostname nix-mail.local
reboot
```

## Tailscale Dance

```sh
ssh root@nix-mail.local
tailscale up --login-server=https://hs.headpats.uk
```

```sh
ssh root@hs.headpats.uk
headscale nodes register --key xxxxxxx_xxxxxxxxxxxxxxxx --user default
```

```sh
ssh root@nix-mail.local
tailscale ip
```

Update `tailnet.mail` in `config.nix` with the IP you got.

Double-check that everything looks happy:

```sh
# ssh root@hs.headpats.uk
# headscale nodes list
ID | Hostname | Name     | MachineKey | NodeKey | User    | IP addresses                  | Ephemeral | Last seen           | Expiration          | Connected | Expired
1  | nix-mail | nix-mail | [xxxxx]    | [xxxxx] | default | 100.64.0.1, fd7a:115c:a1e0::1 | false     | 2026-03-01 15:34:20 | N/A                 | online    | no     
2  | relay    | relay    | [xxxxx]    | [xxxxx] | default | 100.64.0.2, fd7a:115c:a1e0::2 | false     | 2026-03-01 15:21:35 | 0001-01-01 00:00:00 | online    | no     
4  | home     | home     | [xxxxx]    | [xxxxx] | default | 100.64.0.4, fd7a:115c:a1e0::4 | false     | 2026-03-01 15:28:15 | N/A                 | online    | no     

```

Now redeploy both machines so they pick up the final tailnet IPs. The relay needs
`tailnet.mail` for its nginx stream proxy to the beszel agent, and the mail server needs
`tailnet.relay` for postfix:

```sh
deploy
```

Going forward, you can deploy both machines individually or together without specifying IPs:

```sh
deploy
deploy .#mail
deploy .#relay
```

# Set Up the DKIM Signature
```sh
# ssh root@nix-mail
Last login: Sun Mar  1 15:25:22 2026 from 10.0.10.173

[root@nix-mail:~]# cat /var/dkim/headpats.uk.mail.txt
mail._domainkey IN TXT ( "v=DKIM1; k=rsa; "
	"p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF9wPspjt+6m3LG7g/knlgi8Kv6"
	"6529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB"
) ;
```

The file uses BIND zone file syntax: multiple quoted strings inside parentheses that get
concatenated when read. **Do not paste this verbatim into Cloudflare.** Cloudflare wants a
single plain value with no surrounding quotes.

Strip the quotes and join all the string fragments into one value:

```
v=DKIM1; k=rsa; p=MIIBIjAN...rNF9wPspjt...IDAQAB
```

In my case that's:

```
v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF9wPspjt+6m3LG7g/knlgi8Kv66529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB
```

Set the record on the domain:

```
Type: TXT
Name: mail._domainkey
Content: v=DKIM1; k=rsa; p=MIIBIjAN...(your full key)...IDAQAB
Proxy status: DNS only
TTL: 2 hr
```

Cloudflare will automatically split the value into 255-byte chunks when it stores the record,
which is why `host -t txt` shows it split up again. That's expected and correct.

Check the record with:

```sh
# host -t txt mail._domainkey.headpats.uk
mail._domainkey.headpats.uk descriptive text "v=DKIM1; k=rsa; s=email; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF" "9wPspjt+6m3LG7g/knlgi8Kv66529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB"
```

# Test the Spamminess of Your Emails
Go to [mail-tester](https://www.mail-tester.com/) and send an email to it. This will quickly point out
if you missed anything.

[mailgenius](https://mailgenius.com) is another equivalent tool.

[mxtoolbox](https://mxtoolbox.com/) also helps find issues, though not all its warnings need to be fixed.

For the DMARC stuff, ideally you want to wait until mail has been circulating for a couple of weeks.

For the BIMI record, it's entirely optional and cosmetic. I might set it up once I get the DMARC tightened up.

# Dev Environment
Some basic workflows included in the dev shell:

```sh
# Ctrl+r - fuzzy search command history
# Ctrl+t - fuzzy find files and insert path at cursor
# Alt+c - fuzzy find directories and cd into them

# edit code
nvim hosts/mail/configuration.nix

# Ctrl+Z to drop back into shell, fg to resume nvim

# check for common nix antipatterns
statix check .

# find unused variables and imports
deadnix .

# fix statix issues automatically
statix fix .

# fix deadnix issues automatically
deadnix --edit .
```

In nvim:
* `gd` - go to definition of an option or package
* `K` - hover docs for the option under cursor
* `<leader>ca` - code actions, can auto-fix some issues
* `<leader>e` - show explanation of linter when the line shows W or E

Leader is `\` by default.

## Build Locally Without Deploying
```sh
# check your config builds without errors
nom build .#nixosConfigurations.mail.config.system.build.toplevel

# nom gives you a nice progress display instead of raw nix output
```

## Seeing What Will Change Before Deploying
```sh
diff-system mail
```

Or manually:

```sh
# build the new config
nom build .#nixosConfigurations.nix-mail.config.system.build.toplevel -o /tmp/new-nix-mail

# compare against what's currently running on the remote machine
nvd diff $(ssh root@100.64.0.1 readlink /run/current-system) /tmp/new-nix-mail
```
