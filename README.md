# updatedns.sh
Shell script to update DNS entries via RFC 2136

## Installation

`updatedns.sh` depends on some basic programs most of which are probably part of your Linux distribution BSD or Mac operating system. Just make sure these are installed on your system.
```bash
ECHO=$PREFIX/bin/echo
WGET=$PREFIX/bin/wget
GREP=$PREFIX/bin/grep
NSUPDATE=$PREFIX/bin/nsupdate
DIG=$PREFIX/bin/dig
JQ=$PREFIX/bin/jq
```

Download or clone this repository and adapt the `config.json` file (see #configuration).

## Configuration
```json
{
    "updatedns" : [
        {
            "Keyfile"     : "tsig.key",
            "IPv4Service" : "http://checkip.dyndns.com/index.html",
            "IPv6Service" : "http://checkipv6.dyndns.com/index.html",
            "DNSServer"   : "your.dns.com",
            "Zone"        : "yourzone.org",
            "Host"        : "yourhost.yourzone.org",
            "TTL"         : "900"
        }
    ]
}
```
### Keyfile
A file containing the signature key nsupdate uses to send the RFC 2136 requests. This can be generated using tsig-keygen and should also be present in your DNS configuration to allow updates.
```json
key "<name>" {
        algorithm <algorithm>;
        secret "<base64 encoded key>";
};
```

#### name
The name of the key.
#### algorithm
For example hmac-sha256 or hmac-sha512.
#### base64 encoded key
A shared secret

#### Example
Do NOT use this key in your setup, generate your own!
```bash
# tsig-keygen -a hmac-sha512 somezone.com
key "somezone.com" {
        algorithm hmac-sha512;
        secret "DaRVLuRRqU+LWibT2TDsrqhNyPdsGZQUNbTWHC0ktQKuQlMP5qL+jk8fMRJupS2JWZghjPvBYOJGUBbhQtL6qA==";
};
```

## Automatic and periodic runs
There are various options to have your computer run updatedns.sh periodically.

### systemd
You can utilize the systemd user instance to provide a unit that periodically restarts updatedns.sh.
```bash
[Unit]
Description=Check and update dns entries with updatedns.sh

[Service]
ExecStart=/home/pi/updatedns/updatedns.sh
WorkingDirectory=/home/pi/updatedns

RestartSec=180
Restart=always

[Install]
WantedBy=default.target
```
Here the unit expects the updatedns.sh script to reside in the directory `/home/pi/updatedns`. Adapt the paths in the `ExecStart` and `WorkingDirectory` lines.
Additionally, adapt the restart policy to your liking (`RestartSec` and `Restart`) to only run once (`Restart=no`) or with a different delay between starts (`RestartSec=300` for five minutes).

### cron
```
#minute hour    mday    month   wday    command
*/3     *       *       *       *       /usr/bin/bash /home/pi/updatedns/updatedns.sh
```
