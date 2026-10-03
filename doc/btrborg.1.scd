btrborg(1)

# NAME

btrborg - back up the latest btrbk snapshots into borg repositories

# SYNOPSIS

*btrborg* [_OPTIONS_] _COMMAND_ [_SUBVOLUME_...]

# DESCRIPTION

*btrborg* bridges *btrbk*(1) and *borg*(1). btrbk takes read-only btrfs
snapshots of a set of subvolumes; btrborg stores the most recent snapshot of
every subvolume in a borg repository named after that subvolume.

For every subvolume that btrbk knows about, btrborg looks at the latest
snapshot, say _/mnt/.snapshots/home.20260101T0300_. It splits the snapshot
name at the last dot into the subvolume name (_home_) and the timestamp
(_20260101T0300_) and then operates on

	repository: _$BORG_REPO_BASE_/_home_++
	archive:    _btrbk._20260101T0300

The archive is created from inside the snapshot directory, so paths inside
the archive are relative to the subvolume root.

btrborg has to run with enough privileges to read every snapshot and to let
btrbk inspect the btrfs volume, which usually means running it as root.

# COMMANDS

*list*
	Print one tab-separated line per subvolume: subvolume name, archive
	name, snapshot path and repository.

*init*
	Create the borg repositories that do not exist yet with
	*borg init* and the options in _BTRBORG_INIT_ARGS_. Existing
	repositories are left alone.

*create*
	Archive the latest snapshot of every subvolume. If the archive already
	exists in the repository it is skipped, so the command can be repeated
	safely.

*info*
	Show *borg info* for the latest archive of every subvolume.

*check*
	Run *borg check* on every repository, verifying the latest archive.

*prune*
	Apply the retention policy in _BTRBORG_KEEP_ to every repository. Only
	archives whose name starts with _BTRBORG_ARCHIVE_PREFIX_ are
	considered, so archives created by other tools in the same repository
	are untouched.

*compact*
	Run *borg compact* on every repository. Since borg 1.2, pruning only
	marks data as unused; compacting is what frees the space.

*run*
	*create*, then *check*, then, if nothing failed so far, *prune* and
	*compact*. This is what the systemd service of the NixOS module runs.

If one or more _SUBVOLUME_ names are given, only those subvolumes are
processed. A name that btrbk does not know produces a warning.

# OPTIONS

*-c*, *--config* _FILE_
	Read configuration from _FILE_ instead of _$BTRBORG_CONFIG_ or
	_/etc/btrborg.conf_. The file must exist.

*-n*, *--dry-run*
	Print the borg commands that would run instead of running them.
	Nothing is changed, not even repositories are inspected.

*-v*, *--verbose*
	Print every borg command before running it.

*-h*, *--help*
	Show usage information and exit.

*-V*, *--version*
	Print the version and exit.

# CONFIGURATION

Settings are read from the configuration file, see *btrborg.conf*(5), and
from the environment. The only required setting is _BORG_REPO_BASE_. All of
borg's own environment variables, such as _BORG_PASSPHRASE_, _BORG_RSH_ or
_BORG_REMOTE_PATH_, are passed through.

# EXIT STATUS

*0*
	Every operation succeeded. Borg warnings (exit status 1) are reported
	but do not change the exit status.

*1*
	At least one borg operation failed. btrborg keeps going with the next
	subvolume after a failure, so look at the output for details.

*2*
	Usage error, unreadable configuration, missing _BORG_REPO_BASE_ or
	btrbk failing to list snapshots.

# EXAMPLES

Set up repositories for every subvolume, then take the first backup:

```
# btrborg init
# btrborg create
```

Daily job, as run by the NixOS module:

```
# btrborg run
```

Inspect the latest archive of a single subvolume:

```
# btrborg info home
```

See which commands a prune would run:

```
# btrborg --dry-run prune
```

# SEE ALSO

*btrborg.conf*(5), *btrbk*(1), *borg*(1)

# AUTHORS

Florian Franzen. Maintained at https://github.com/FlorianFranzen/btrborg.
