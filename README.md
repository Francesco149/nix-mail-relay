self hosted e-mail server using nixos-mailserver and a cheap vps as a relay.

the actual mail server runs on my own hardware. the vps is purely used as a relay and doubles
as a headscale server to access my home net when i'm away.

this has not been tested beyond my own deployment so you might need to fiddle with things
here and there, but it should be a good base for anyone trying to do anything similar.

huge thanks to the [nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)
project for doing the heavy lifting of putting together a reliable and easy to set up mail server solution.

# architecture

arrows point the way the ports need to be open

```
         home LAN         |          internet
                          |
+----------------------+  |  +----------------------+
|     home server      |  |  |         vps          |
|   PTR (can't have)   |  |  | PTR mail.headpats.uk |
|   IP  (dynamic)      |  |  | IP  11.22.33.44      |
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

                          "okay inbound email from 11.22.33.44"

                          "PTR is mail.headpats.uk"

                          "mail.headpats.uk resolves back to 11.22.33.44"

                          "PTR matches, SPF passes, DKIM valid,
                           looks good to me!"
```

# setting up the relay
## vps
buy the cheapest vps you can find that meets these requirements:
- you need to be able to set the PTR record to your domain.
- you must have port 25 open inbound and outbound.

1 vCPU 1gb ram is all you need. my install sits at 6.24gb disk and 260mb ram.
it could be smaller since I've messed around a bunch and didn't clean up.

I used racknerd for ~13$/year with the new year deals. port 25 was open out of the box.
for the PTR record, I had to open a support ticket and they responded and changed it within 20 minutes.

you can either ask support before buying or buy, test it and open a ticket if it's blocked.

you can test outbound port 25 by running this from the vps:

```sh
nc -zv gmail-smtp-in.l.google.com 25
```

which should succeed.

you could also test inbound 25 by running this on your home machine:

```sh
nc -zv x.x.x.x 25
```

where x.x.x.x is your vps ip. this should get refused but not time out.

realistically if your vps is blocking 25, it's gonna be blocking it outbound.
plus, your isp could be blocking 25 outbound too which would invalidate the test. 

when setting up your vps, just select some version of ubuntu, which tends to be a good
base to convert it to nixos later. if your vps provider happens to support custom iso's
or nixos, just install nixos directly. most don't.

I used ubuntu 24.04 on racknerd.

## domain
buy a domain. I used cloudflare and got `headpats.uk` for $5.22/year.

for the purposes of this readme, mentally replace `headpats.uk` with your domain.

- log into the cloudflare dashboard, go to Domains -> headpats.uk -> DNS -> Records
- set these dns records, add if missing. replace x.x.x.x with your vps ip

| Type | Name          | Content                        | Proxy status | TTL  | Priority |
| ---- | ------------- | ------------------------------ | ------------ | ---- | -------- |
| A    | headpats.uk   | x.x.x.x                        | DNS only     | Auto | -        |
| A    | hs            | x.x.x.x                        | DNS only     | Auto | -        |
| A    | mail          | x.x.x.x                        | DNS only     | Auto | -        |
| A    | smtp          | x.x.x.x                        | DNS only     | Auto | -        |
| MX   | headpats.uk   | mail.headpats.uk               | DNS only     | Auto | 10       |
| TXT  | _dmarc        | v=DMARC1; p=none               | DNS only     | 2 hr | -        |
| TXT  | headpats.uk   | v=spf1 a:mail.headpats.uk -all | DNS only     | 2 hr | -        |

if your vps has an ipv6, you can set a AAAA record, but this is optional so probably
wait until you have everything working.

**for the DKIM record, we will set it up once the mail server is up.**

set your PTR record on your VPS to point to `mail.headpats.uk`

double check with [nixos-mailserver guide](https://nixos-mailserver.readthedocs.io/en/nixos-25.11/setup-guide.html) .

it walks you through checking all the boxes with the records and checking them.

some of these records can take hours to propagate, **just remember to
check them before you send mail later.**

here's my records:

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

## installing nixos
for the base os, i selected ubuntu 24.04 which tends to work well with the nixos-infect script.
you might have to do some reinstalls to test different distros and find one that works.

now ssh into the vps. login with the root password you're given

```sh
ssh root@x.x.x.x
ssh-keygen
exit
```

- **NOTE:** don't forget to add public ssh keys to `~/.ssh/authorized_keys` and/or `/root/.ssh/authorized_keys`
- **NOTE:** don't forget to check that you can ssh without a password before closing the ssh session.
- **NOTE:** if you forget, you will have to redeploy or use recovery mode, mount the rootfs and add the keys.
  ask me how I know

## convert it to nixos:

```sh
curl https://raw.githubusercontent.com/elitak/nixos-infect/36f48d8feb89ca508261d7390355144fc0048932/nixos-infect | NIX_CHANNEL=nixos-25.11 bash -x

reboot
```

**FIXME:** using an old version of the script for now because of [a regression](https://github.com/elitak/nixos-infect/issues/255#issuecomment-3963186336) .

check that you can still ssh into the server

## entering the dev environment
from your home machine, [install nix](https://nix.dev/manual/nix/2.28/installation/) or just run nixos

```
nix-shell -p git --run git clone https://github.com/Francesco149/nix-mail-relay
cd nix-mail-relay
./env.sh 
```

this should drop you into the `headpats-dev` shell.

## configuration
edit `config.nix` with your favorite editor. the shell comes with nvim preconfigured for nix.

remove my ssh keys and add your own.

check all the other .nix files in case something looks off, you don't want to blindly run my code do you.

copy over the hardware configuration.
you could run `nixos-generate-config` on the server again for good measure.

```sh
scp root@x.x.x.x:/etc/nixos/hardware-configuration.nix hosts/relay/
```

edit `hosts/relay/configuration.nix` to match what your `/etc/nixos/configuration.nix` looks
like on the fresh install.

I need to look into making this into a flake template so you don't have to overwrite my
hardware config and you can make your own flake repo based on it.

## beszel credentials
if you don't use beszel for monitoring, just set `monitoring = false` in `config.nix`
and skip this section.

otherwise, click add system in beszel, stay on that screen to copy key and token
and put it in the env file like so:

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

now you can confirm on the beszel ui. for the host/ip you want to point it
to the tail network ip of the relay, which you don't know yet so just use
a placeholder and change it later.

in my case, my beszel ui is running in a docker container and I decided to just
have a nginx stream proxy on the mail server forwarding the beszel port to the
tail net ip for the relay. this is already set up for you with this flake

## deploy

```sh
deploy .#relay -- --hostname x.x.x.x
ssh root@x.x.x.x
reboot
```

## tailscale connectivity
### on the relay
let's bring tailscale up and get the relay side of things connected.

```sh
ssh root@x.x.x.x
headscale users create default
tailscale up --login-server https://hs.headpats.uk
```

this will give you a url, open it, copy the command it shows you.

open another shell and run the command but change the example `--user` part to `--user default`.

```sh
ssh root@x.x.x.x
headscale nodes register --key xxxxxxx_xxxxxxxxxxxxxxxx --user default
```

the tailscale up shell should say success

now get the tailnet IP:

```sh
tailscale ip
```

update `tailnet.relay` in `config.nix` with that IP, then **redeploy the relay** so that
postfix and nginx pick up the correct address before the mail server tries to use it:

```sh
deploy .#relay
```

## on your computer
you should now be able to do the same tailscale dance from your home machine.

first, install and enable tailscale and its daemon

```sh
sudo pacman -S tailscale # or whatever package manager you use
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
```

then, do the usual tailscale up dance

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
# we're in, through tailscale this time

# we can take a look at all the nodes
[root@relay:~]# headscale nodes list
ID | Hostname | Name     | MachineKey | NodeKey | User    | IP addresses                  | Ephemeral | Last seen           | Expiration          | Connected | Expired
2  | relay    | relay    | [xxxxx]    | [xxxxx] | default | 100.64.0.2, fd7a:115c:a1e0::2 | false     | 2026-02-28 03:05:02 | N/A                 | online    | no     
4  | home     | home     | [xxxxx]    | [xxxxx] | default | 100.64.0.4, fd7a:115c:a1e0::4 | false     | 2026-02-28 16:11:21 | N/A                 | online    | no     

```

# mail server
## install nixos and set up ssh
install nixos on the target machine. I like to use the graphical installer for convenience.

on the target machine, login as root:

```sh
ssh-keygen
nano /etc/nixos/configuration.nix
```

enable openssh and add your ssh key by adding in `/etc/nixos/configuration.nix`:

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

apply changes

```sh
nixos-rebuild switch
```

now you should be able to ssh into the machine.

## prepare secrets
```
ssh root@nix-mail.local

mkdir -p /var/lib/secrets
chmod 700 /var/lib/secrets

# must match the username you set in config.nix
nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt' > /var/lib/secrets/loli-hashed-password
chmod 600 /var/lib/secrets/loli-hashed-password
```

## configuration
copy over the hardware configuration.
you could run `nixos-generate-config` on the server again for good measure.

```sh
scp root@nix-mail.local:/etc/nixos/hardware-configuration.nix hosts/mail/
```

edit `hosts/mail/configuration.nix` to match what your `/etc/nixos/configuration.nix` looks
like on the fresh install.

## deploy

```
deploy .#mail -- --hostname nix-mail.local
reboot
```

## tailscale dance

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

update `tailnet.mail` in `config.nix` with the ip you got.

double check that everything is happy

```sh
# ssh root@hs.headpats.uk
# headscale nodes list
ID | Hostname | Name     | MachineKey | NodeKey | User    | IP addresses                  | Ephemeral | Last seen           | Expiration          | Connected | Expired
1  | nix-mail | nix-mail | [xxxxx]    | [xxxxx] | default | 100.64.0.1, fd7a:115c:a1e0::1 | false     | 2026-03-01 15:34:20 | N/A                 | online    | no     
2  | relay    | relay    | [xxxxx]    | [xxxxx] | default | 100.64.0.2, fd7a:115c:a1e0::2 | false     | 2026-03-01 15:21:35 | 0001-01-01 00:00:00 | online    | no     
4  | home     | home     | [xxxxx]    | [xxxxx] | default | 100.64.0.4, fd7a:115c:a1e0::4 | false     | 2026-03-01 15:28:15 | N/A                 | online    | no     

```

now redeploy both machines so they pick up the final tailnet IPs. the relay needs
`tailnet.mail` for its nginx stream proxy to the beszel agent, and the mail server needs
`tailnet.relay` for postfix:

```sh
deploy
```

now you can deploy both machines individually or at the same time without specifying the ips

```sh
deploy
deploy .#mail
deploy .#relay
```

# set up the DKIM signature
```sh
# ssh root@nix-mail
Last login: Sun Mar  1 15:25:22 2026 from 10.0.10.173

[root@nix-mail:~]# cat /var/dkim/headpats.uk.mail.txt
mail._domainkey IN TXT ( "v=DKIM1; k=rsa; "
	"p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF9wPspjt+6m3LG7g/knlgi8Kv6"
	"6529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB"
) ; 
```

set the record on the domain accordingly 

```
Type: TXT
Name: mail._domainkey
Content: "v=DKIM1; k=rsa; s=email; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF" "9wPspjt+6m3LG7g/knlgi8Kv66529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB"
Proxy status: DNS only
TTL: 2 hr
```

I pieced together the p= strings into a single one, not sure if that's necessary, like this:

```
p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF9wPspjt+6m3LG7g/knlgi8Kv66529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB
```

but it probably wasn't necessary since it got split up again

check the record with:

```sh
# host -t txt mail._domainkey.headpats.uk
mail._domainkey.headpats.uk descriptive text "v=DKIM1; k=rsa; s=email; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyVtusbiNSKChlIDsFHodQPnGZ03XegGrOuihI25C+fAPhArVuuM3xXE7pcxBjdWHTCOoWGYbKN9OndxGu4VmRPjUYZgU3UWGfS8spyoG3vVPle/0Mcldz60YBBTE3vjBrRKBSvGNyF+57QvBbSKZWtsLgeeu52DBhzvTgj3TZThgW8VCMRSL+rNF" "9wPspjt+6m3LG7g/knlgi8Kv66529EQhsEUAlkBiS2YGXnkLSyQ/hGbe4pqeOP2iyCRxvS6Yc02pOTUI6ndn5XoExumq0Q5g9pnzdd0D+6EVzJxK57ZqjLYaw5yMLjGhDVRoshmJkT2gVac01LENmGmLYad19wIDAQAB"
```

# test the spamminess of your emails
go to [mail-tester](https://www.mail-tester.com/) and send an email to it. this will quickly point out
if you missed anything.

[mailgenius](https://mailgenius.com) is another equivalent tool.

[mxtoolbox](https://mxtoolbox.com/) also helps finding issues, though not all its warnings need to be fixed.

for example for the DMARC stuff ideally you want to wait until mail has circulated for a couple weeks.

for the BIMI record, it's entirely optional and cosmetic. I might set it up once I get the DMARC tightened up.

# dev environment
some basic workflows that are included in the dev shell.

```sh
# Ctrl+r - fuzzy search command history
# Ctrl+t - fuzzy find files and insert path at cursor
# Alt+c - fuzzy find directories and cd into them

# edit code
nvim hosts/mail/configuration.nix

# CTRL+Z to drop back into shell, fg to resume nvim

# check for common nix antipatterns
statix check .

# find unused variables and imports
deadnix .

# fix statix issues automatically
statix fix .

# fix deadnix issues automatically
deadnix --edit .
```

in nvim:
* `gd` - go to definition of an option or package
* `K` - hover docs for the option under cursor
* `<leader>ca` - code actions, can auto-fix some issues
* `<leader>e` - show explanation of linter when the line shows W or E

leader is `\` by default

## build locally without deploying
```sh
# check your config builds without errors
nom build .#nixosConfigurations.mail.config.system.build.toplevel

# nom gives you a nice progress display instead of raw nix output
```

## seeing what will change before deploying
```sh
diff-system mail
```


or manually

```sh
# build the new config
nom build .#nixosConfigurations.nix-mail.config.system.build.toplevel -o /tmp/new-nix-mail

# compare against what's currently running on the remote machine
nvd diff $(ssh root@100.64.0.1 readlink /run/current-system) /tmp/new-nix-mail
```
