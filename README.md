# btrborg

Back up the latest [btrbk](https://digint.ch/btrbk/) snapshots into
[borg](https://www.borgbackup.org/) repositories.

btrbk is great at taking cheap, consistent btrfs snapshots and shipping them
to other btrfs volumes. borg is great at deduplicated, encrypted, off-site
archives on any storage. btrborg connects the two: for every subvolume btrbk
manages, it takes the most recent snapshot and stores it in a borg repository
of the same name.

```
/mnt/.snapshots/home.20260101T0300  ->  $BORG_REPO_BASE/home::btrbk.20260101T0300
/mnt/.snapshots/www.20260101T0300   ->  $BORG_REPO_BASE/www::btrbk.20260101T0300
```

Because the archive is taken from a read-only snapshot, the backup is
consistent even while the live subvolume keeps changing.

## Usage

```
btrborg [OPTIONS] COMMAND [SUBVOLUME...]
```

| Command   | What it does                                                        |
| --------- | ------------------------------------------------------------------- |
| `list`    | Show the latest snapshot and archive name of every subvolume        |
| `init`    | Create the borg repositories that do not exist yet                  |
| `create`  | Archive the latest snapshot of every subvolume (skips existing)     |
| `info`    | `borg info` of the latest archive of every subvolume                |
| `check`   | `borg check` of the latest archive of every subvolume               |
| `prune`   | Apply the retention policy to every repository                      |
| `compact` | `borg compact` every repository (needed since borg 1.2)             |
| `run`     | `create`, `check`, and if all went well `prune` and `compact`       |

Subvolume names restrict a command to those subvolumes. `--dry-run` prints
the borg commands instead of running them, `--verbose` prints them as they
run. See [btrborg(1)](doc/btrborg.1.scd) for the details.

A typical first setup:

```sh
# cat > /etc/btrborg.conf <<'CONF'
BORG_REPO_BASE='ssh://borg@backup.example.org/./btrbk'
. /etc/btrborg.secret          # BORG_PASSPHRASE='...'
CONF
# chmod 600 /etc/btrborg.secret
# btrborg list
# btrborg init
# btrborg run
```

## Configuration

btrborg reads `/etc/btrborg.conf` (or `--config FILE`, or
`$BTRBORG_CONFIG`). The file is a shell snippet of variable assignments, so
secrets can be kept in a separate root-only file that is sourced from it.
Every variable can also come from the environment.

| Variable                   | Default                       | Meaning                                            |
| -------------------------- | ----------------------------- | -------------------------------------------------- |
| `BORG_REPO_BASE`           | required                      | Repositories live at `$BORG_REPO_BASE/<subvolume>` |
| `BTRBORG_ARCHIVE_PREFIX`   | `btrbk.`                      | Prefix of archive names                            |
| `BTRBORG_COMPRESSION`      | `zstd,3`                      | `borg create --compression`                        |
| `BTRBORG_KEEP`             | see below                     | `borg prune` retention options                     |
| `BTRBORG_INIT_ARGS`        | `--encryption repokey-blake2` | Options for `borg init`                            |
| `BTRBORG_CREATE_ARGS` etc. | empty                         | Extra options for the respective borg command      |
| `BTRBORG_BTRBK_ARGS`       | empty                         | Options for `btrbk list`, e.g. `-c FILE`           |

The default retention is
`--keep-within 7d --keep-daily 14 --keep-weekly 4 --keep-monthly 12 --keep-yearly -1`.

All `BORG_*` variables, such as `BORG_PASSPHRASE`, `BORG_PASSCOMMAND` or
`BORG_RSH`, are passed through to borg. See
[btrborg.conf(5)](doc/btrborg.conf.5.scd) and
[the example](doc/btrborg.conf.example).

## Installation

### Nix flake

```sh
nix run github:FlorianFranzen/btrborg -- --help
nix profile install github:FlorianFranzen/btrborg
```

The package wraps the pinned `borg` and `btrbk` from nixpkgs, so nothing
else is needed. The flake follows the latest NixOS stable release.

### NixOS module

```nix
{
  inputs.btrborg.url = "github:FlorianFranzen/btrborg";
  # Optional, to share one nixpkgs: inputs.btrborg.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, btrborg, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        btrborg.nixosModules.default
        {
          services.btrbk.instances.btrbk = {
            onCalendar = "daily";
            settings.volume."/mnt" = {
              snapshot_dir = ".snapshots";
              subvolume = { home = { }; www = { }; };
            };
          };

          services.btrborg = {
            enable = true;
            repoBase = "ssh://borg@backup.example.org/./btrbk";
            # Root-only file with BORG_PASSPHRASE='...' and friends.
            environmentFile = "/run/secrets/btrborg";
            settings.BTRBORG_KEEP = "--keep-daily 7 --keep-weekly 4 --keep-monthly 6";
            onCalendar = "daily";
          };
        }
      ];
    };
  };
}
```

The module writes `/etc/btrborg.conf`, installs the command for interactive
use, and adds a `btrborg.service` plus `btrborg.timer` that run `btrborg
run`. The service is ordered after the `btrbk-*` services, so when both
timers fire at the same time the snapshots are taken first. With a single
btrbk instance the module picks its configuration automatically; set
`services.btrborg.btrbkInstance` otherwise.

Remember to create the repositories once with `btrborg init` (or by hand)
before the first timer run.

### Elsewhere

Copy `bin/btrborg` somewhere in `$PATH`. It needs bash 4.4 or newer,
`borg`, `btrbk`, `grep` and coreutils. Man pages are built from `doc/*.scd`
with [scdoc](https://git.sr.ht/~sircmpwn/scdoc):

```sh
scdoc < doc/btrborg.1.scd > btrborg.1
scdoc < doc/btrborg.conf.5.scd > btrborg.conf.5
```

## How it works

1. `btrbk list latest --format=raw` reports, for every configured
   subvolume and target, the most recent snapshot and its path. btrborg
   parses that output (without `eval`), ignores rows that have no snapshot,
   and keeps the newest snapshot of each subvolume even if btrbk lists an
   older one for a target that is lagging behind.
2. The snapshot name `<name>.<timestamp>` is split at the last dot. `name`
   selects the repository `$BORG_REPO_BASE/<name>`, `timestamp` names the
   archive `btrbk.<timestamp>`.
3. The requested borg command runs per subvolume. borg warnings (exit 1)
   are printed but tolerated; errors (exit 2 and up) are counted and make
   btrborg exit with status 1 after all subvolumes have been handled. A
   backup run that finds no snapshots at all, or is given a subvolume name
   btrbk does not know, fails instead of silently doing nothing.

`run` includes a `borg check` of every repository. On large repositories
set `BTRBORG_CHECK_ARGS='--archives-only'` or `--max-duration SECONDS` to
keep the daily run short; see btrborg.conf(5).

## Development

```sh
nix develop            # borg, btrbk, scdoc, shellcheck, nixfmt
nix build              # package, including shellcheck of the script
nix flake check        # package, formatting and the NixOS VM test
nix build .#checks.x86_64-linux.nixos   # only the VM test
nix fmt                # format the Nix files
```

The VM test in `nix/test.nix` formats a btrfs volume, takes btrbk
snapshots, and exercises every command plus the module's service and timer.
It needs KVM.

## License

Apache License 2.0, see [LICENSE](LICENSE).
