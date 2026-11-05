# CoolerControl — fan control on the B650 Gaming X AX V2

Backup of `/etc/coolercontrol/` (profiles, calibrations, labels). Nothing in this
folder is stowed. Set up 2026-11-02 to 2026-11-05.

Not copied on purpose: `.passwd`, `.tokens`, `coolercontrol.key`/`.crt` (secrets,
regenerated on first start) and `plugins` (a symlink into `/var/lib`).

## What makes fan control work

| Piece | Where |
|-------|-------|
| Out-of-tree it87 driver | `yay -S it87-dkms-git` (frankcrawford/it87, DKMS) |
| Load it87 at boot | `system/desktop/etc/modules-load.d/it87.conf` |
| `ignore_resource_conflict=1` | `system/desktop/etc/modprobe.d/it87.conf` |
| Blacklist gigabyte_wmi | `system/desktop/etc/modprobe.d/gigabyte_wmi.conf` |
| BIOS | Smart Fan: CPU_FAN, SYS_FAN1-3 control mode **PWM** |

`./setup.sh` installs the three `/etc` files. The AUR package and the BIOS
setting are manual.

## Why the out-of-tree driver

With the in-tree it87, CoolerControl's writes landed in the chip (pwm registers
read back correctly) but the BIOS kept reclaiming the outputs: fans followed for
about a minute, then went back to BIOS idle speeds. CPU_FAN never followed at
all. The out-of-tree driver detects the Gigabyte board, talks to the chip over
MMIO, and every fan responds within seconds and stays put.

After a kernel update, if the fans vanish from CoolerControl, check
`dkms status` — the module probably failed to rebuild.

## Headers

| hwmon | Header | Fan |
|-------|--------|-----|
| fan1 | CPU_FAN | DeepCool ASSASSIN IV (both fans, 4-pin) |
| fan2 | SYS_FAN | Case exhaust |
| fan3 | — | Nothing connected |
| fan4 | SYS_FAN | Case intake |
| fan5 | — | Tach only, no PWM |

Profiles: CPU cooler on an 8 s EMA of k10temp Tctl, GPU on an 8 s EMA of the
3080's GPU Temp, case fans on Max(CPU, GPU). The motherboard has no ambient
sensor; it8689 temp1 is the coolest board thermistor.

## Restore

```bash
sudo systemctl stop coolercontrold
sudo install -m 644 machines/desktop/coolercontrol/*.{toml,json} /etc/coolercontrol/
sudo systemctl start coolercontrold
```

Stop the daemon first; it rewrites `config.toml` on shutdown. Calibrations are
tied to these exact fans, so recalibrate after swapping hardware.

## Refresh this backup

```bash
cp /etc/coolercontrol/{config.toml,calibrations.json,config-ui.json,overrides.toml,modes.json,alerts.json} machines/desktop/coolercontrol/
```
