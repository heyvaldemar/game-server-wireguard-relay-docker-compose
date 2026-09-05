# The relay side

The relay is the cheapest instance your provider sells. It holds the public
address, terminates one WireGuard tunnel, and forwards a game port down it. It
stores no game data, runs no game, and can be rebuilt from this page in a few
minutes if it is ever lost.

What it costs to run: on a small provider instance, a few dollars a month, and
the tunnel itself adds about 1 ms.

## 1. Install WireGuard and enable forwarding

```bash
sudo apt-get update && sudo apt-get install -y wireguard nftables
printf 'net.ipv4.ip_forward=1\n' | sudo tee /etc/sysctl.d/99-relay.conf
sudo sysctl --system
```

## 2. Create the tunnel

```bash
wg genkey | sudo tee /etc/wireguard/server.key | wg pubkey | sudo tee /etc/wireguard/server.pub
sudo chmod 600 /etc/wireguard/server.key
```

`/etc/wireguard/wg0.conf`, with `<server-key>` from the file above and
`<home-public-key>` from the sidecar at home:

```ini
[Interface]
Address = 10.13.13.1/24
ListenPort = 51820
PrivateKey = <server-key>

[Peer]
# The machine at home. It always dials out; it never listens.
PublicKey = <home-public-key>
AllowedIPs = 10.13.13.2/32
```

The configuration you put at home, in `./config/wg_confs/wg0.conf`, needs one
line that generators leave out:

```ini
[Peer]
PublicKey = <server-public-key>
Endpoint = <relay-address>:51820
AllowedIPs = 10.13.13.0/24
# REQUIRED. WireGuard sends nothing when nobody is talking, and a router
# forgets an idle mapping in a minute or two. When it does, the relay's
# forwarded packets arrive at a door that no longer exists: the tunnel still
# reports itself as configured, players simply stop connecting, and nothing
# logs an error. Twenty-five seconds is the usual value.
PersistentKeepalive = 25
```

```bash
sudo systemctl enable --now wg-quick@wg0
```

## 3. Forward the game port into the tunnel

Replace `25565/tcp` with your game's port and protocol. Most game servers want
UDP; Minecraft Java is the exception.

```bash
sudo nft -f - <<'RULES'
table inet relay {
  chain prerouting {
    type nat hook prerouting priority dstnat;
    tcp dport 25565 dnat ip to 10.13.13.2
    udp dport 19132 dnat ip to 10.13.13.2
  }
  chain postrouting {
    type nat hook postrouting priority srcnat;
    ip daddr 10.13.13.2 masquerade
  }
}
RULES
sudo nft list ruleset | sudo tee /etc/nftables.conf > /dev/null
sudo systemctl enable nftables
```

Open the same ports in your provider's firewall. That is the whole relay.

## 4. Check it from outside

```bash
# from any machine that is not on your LAN
nc -vz <relay-address> 25565
```

## What the relay must never do

**Do not give it the game data.** If the relay is compromised, it should hold
nothing but a tunnel key you can rotate in one command. Keep saves, worlds and
backups at home.

**Do not forward the whole tunnel.** `AllowedIPs = 10.13.13.2/32` on the relay
means it can reach exactly one address at home: the sidecar. A wider range
turns a rented instance into a route into your house.

**Do not skip the return path.** Without the masquerade rule the game answers
directly to the player from an address the player never contacted, and the
reply is dropped. The symptom is a server that appears in a list and refuses
every connection.
