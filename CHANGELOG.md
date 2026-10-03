# Changelog

All notable changes to btrborg are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-03

First release as a standalone project. The script previously lived as an
unversioned helper next to a btrbk installation.

### Added

- `list`, `create`, `info`, `check` and `prune` commands as before, plus
  `init`, `compact` and `run`.
- Configuration through `/etc/btrborg.conf` (or `--config`) and
  `BTRBORG_*` environment variables; see btrborg.conf(5).
- Optional filtering by subvolume name, `--dry-run` and `--verbose`.
- Nix flake with a package, a NixOS module (`services.btrborg`) and a
  NixOS VM test.
- Man pages btrborg(1) and btrborg.conf(5), bash completion.

### Changed

- btrbk output is parsed instead of `eval`'d.
- The snapshot path is taken from the `snapshot_subvolume` column, which
  btrbk 0.32 prints; `snapshot_path` is accepted as a fallback.
- `create` skips archives that already exist, so a run can be repeated.
- `prune` selects archives with `--glob-archives` instead of the deprecated
  `--prefix` and is followed by `borg compact`, which borg 1.2 and later
  require to actually free space.
- `run` only prunes when every create and check succeeded.
- Borg errors are reported per subvolume and the exit status is non-zero if
  any operation failed.
