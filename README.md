# 👻 Ghostwave

A hands-on WPA2 wireless security audit — capturing a 4-way handshake from my own home network and testing password strength via an offline dictionary attack.

## ⚠️ Disclaimer

This was performed **only on my own home network**, with explicit permission. It is for educational / security-auditing purposes only.

Capturing and cracking a handshake on a network you do not own or do not have explicit permission to test is illegal in most places. The *technique* documented here is identical either way — the only thing that makes this legitimate is permission.

---

## What I Learned

- How WPA2's 4-way handshake works, and why it can be attacked offline once captured
- Why weak, dictionary-word passwords fall quickly under this kind of attack, while long/random passwords don't
- Linux wireless internals: monitor mode, `rfkill`, and how NetworkManager can silently interfere with raw packet capture
- Real debugging: most of this project was hitting errors and tracing them to their actual cause, not just running commands that worked first try

---

## Setup

- **OS:** Ubuntu (native install, not a VM — monitor mode generally does not work reliably through VM wireless passthrough)
- **Hardware:** Intel wireless card (model supports monitor mode — confirmed via `iw list`)
- **Tools:** `aircrack-ng` suite (`airodump-ng`, `aireplay-ng`, `aircrack-ng`)
- **Wordlist:** `rockyou.txt`

---

## Full Process

### 1. Check if your wireless card supports monitor mode

```bash
iw list | grep -A 10 "Supported interface modes"
```

Look for `monitor` in the list. If it's not there, your card's firmware doesn't support raw packet capture — no software workaround for this.

### 2. Identify your wireless interface name

Modern Ubuntu no longer ships `iwconfig` by default. Use:

```bash
iw dev
```

Look for the line starting with `Interface` — e.g. `Interface wlp2s0`. That's your interface name, used in every command below.

### 3. Stop services that interfere with monitor mode

NetworkManager and `wpa_supplicant` actively manage the wireless card and will fight with raw monitor mode, often causing silent failures or RF-kill errors.

```bash
sudo airmon-ng check kill
```

### 4. Check and clear RF-kill blocks

RF-kill is a software/hardware switch that can block wireless radio use entirely, independent of NetworkManager.

```bash
rfkill list
sudo rfkill unblock all
```

If a device shows `Hard blocked: yes`, that's usually a physical switch or `Fn` key combo on the laptop, not something fixable in software.

### 5. Enable monitor mode

```bash
sudo ip link set wlp2s0 down
sudo iw wlp2s0 set monitor none
sudo ip link set wlp2s0 up
```

Confirm it worked:

```bash
iw dev
```

Should now show `type monitor` instead of `type managed`.

### 6. Broad scan — find the target network

```bash
sudo airodump-ng wlp2s0
```

Let this run 20–30 seconds. It lists every nearby network with:
- **BSSID** — the router's MAC address
- **ESSID** — the network name
- **CH** — the channel it's broadcasting on

Note down the BSSID and channel of the target network, then `Ctrl+C` to stop.

> If you only have the BSSID and not the channel, you can skip `-c` in the next step and airodump-ng will hop channels automatically until it locks onto that BSSID — just slower to start, and slightly more likely to miss a handshake that happens mid-hop.

### 7. Targeted capture — lock onto the one network

```bash
sudo airodump-ng -c CHANNEL --bssid BSSID -w capture wlp2s0
```

Replace `CHANNEL` and `BSSID` with the real values from step 6. Leave this running — it's now only listening on that network's channel, waiting to capture a handshake.

### 8. Trigger the handshake

A handshake only happens when a device connects or reconnects to the network. Two ways to get one:

**A — Natural reconnect (no extra tooling needed):**
Turn Wi-Fi off and back on on any device already connected to the target network (phone, laptop, etc.).

**B — Force it with a deauth (requires packet injection support — not all cards support this reliably):**

```bash
sudo aireplay-ng --deauth 5 -a BSSID wlp2s0
```

This briefly disconnects connected devices, forcing an automatic reconnect — which is exactly the moment the handshake happens.

### 9. Confirm the handshake was captured

Watch the top of the `airodump-ng` window (step 7) for:

```
WPA handshake: BSSID
```

Once it appears, `Ctrl+C` to stop the capture.

### 10. Get a wordlist

`rockyou.txt` isn't pre-installed on plain Ubuntu (it ships by default on Kali only).

```bash
wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt -O ~/rockyou.txt
```

### 11. Crack the handshake offline

```bash
aircrack-ng -w ~/rockyou.txt capture-01.cap
```

(Replace `capture-01.cap` with your actual capture filename — it increments each time you run a new capture, e.g. `capture-02.cap`, `capture-03.cap`.)

If the password is in the wordlist, it prints:

```
KEY FOUND! [ the password ]
```

If not, it finishes the list and reports no match — which is actually a *good* result, since it means the password resists a standard dictionary attack.

---

## Problems I Hit (and How I Fixed Them)

| Problem | Cause | Fix |
|---|---|---|
| `iwconfig: command not found` | Deprecated on newer Ubuntu, not installed by default | Used `ip link show` / `iw dev` instead |
| `RTNETLINK answers: Operation not possible due to RF-kill` | Wireless radio soft/hard-blocked | `sudo rfkill unblock all`, confirmed with `rfkill list` |
| RF-kill error returned even after unblocking | NetworkManager silently re-blocking the interface | `sudo airmon-ng check kill` to stop NetworkManager/wpa_supplicant before retrying |
| `airodump-ng` stuck at `CH 1`, no networks listed | Was running inside assumptions that didn't match reality — turned out to be a sequencing issue, not a VM (confirmed native install) | Re-ran the full sequence in order: kill interfering services → unblock rfkill → re-enable monitor mode → scan |
| `ERROR: Opening dictionary ... failed` | `rockyou.txt` not present — it's a Kali-only default, not on plain Ubuntu | Downloaded it manually via `wget` |
| `0 handshake` in capture file | No device reconnected to the network during capture | Triggered a manual reconnect, then confirmed `1 handshake` on next capture |

---

## Result

Successfully captured a WPA2 handshake and cracked it using a dictionary attack. The password found was a predictable, dictionary-word pattern — a concrete demonstration of why common/guessable passwords are vulnerable to this kind of offline attack, regardless of how "secret" they feel.

---

## Next Steps

- Explore **hashcat** for GPU-accelerated cracking and rule-based/mask attacks (much faster and smarter than plain dictionary attacks)
- Look into **PMKID attacks** via `hcxdumptool`, which can sometimes capture enough from the router alone, without needing a client to connect
- Extend this into a broader offense/defense reinforcement learning project — training agents on opposite objectives (attack vs. detect/defend) in a simulated environment, inspired in part by Microsoft's [CyberBattleSim](https://github.com/microsoft/CyberBattleSim)
