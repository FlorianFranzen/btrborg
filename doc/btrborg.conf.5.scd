btrborg.conf(5)

# NAME

btrborg.conf - configuration file for btrborg

# SYNOPSIS

_/etc/btrborg.conf_

# DESCRIPTION

*btrborg*(1) reads its settings from a shell file: every line is a variable
assignment, and the file is sourced by bash with all assignments exported.
The file is looked up in this order:

. the argument of *--config*
. _$BTRBORG_CONFIG_
. _/etc/btrborg.conf_, if it exists

Because the file is sourced, it may also source other files, which is how
secrets are kept out of a world-readable configuration:

```
BORG_REPO_BASE='ssh://borg@backup.example.org/./btrbk'
. /run/secrets/btrborg
```

Quote values the way a shell expects. Every variable can also be set in the
environment instead; a configuration file is optional when _BORG_REPO_BASE_
comes from the environment.

Repositories are usually encrypted, so _BORG_PASSPHRASE_ or
_BORG_PASSCOMMAND_ has to be set for every command except *list*.

# VARIABLES

*BORG_REPO_BASE*
	Required. Location below which the repositories live. The repository
	of a subvolume is _$BORG_REPO_BASE_/_subvolume_. Local paths and any
	URL that borg accepts work, for example
	_ssh://user@host/./backups_.

*BTRBORG_ARCHIVE_PREFIX*
	Prefix of the archive names. Default: _btrbk._ (with the trailing
	dot). *prune* only touches archives with this prefix.

*BTRBORG_COMPRESSION*
	Argument to *borg create --compression*. Default: _zstd,3_.

*BTRBORG_KEEP*
	Retention options passed to *borg prune*. Default:

```
--keep-within 7d --keep-daily 14 --keep-weekly 4 \
--keep-monthly 12 --keep-yearly -1
```

*BTRBORG_INIT_ARGS*
	Options passed to *borg init* by the *init* command. Default:
	_--encryption repokey-blake2_.

*BTRBORG_CREATE_ARGS*, *BTRBORG_CHECK_ARGS*, *BTRBORG_PRUNE_ARGS*,
*BTRBORG_COMPACT_ARGS*
	Extra options for the corresponding borg command, for example
	_--exclude-caches_ for *create*. Default: empty.

	*borg check* without options verifies the whole repository on every
	run, which reads all of its data and can take hours on large or remote
	repositories. For a daily *run*, _--archives-only_ checks just the
	latest archive, _--max-duration 1800_ verifies the repository in
	half-hour slices across runs, and _--verify-data_ adds a (slow)
	cryptographic check of the archive contents. For example:

```
BTRBORG_CHECK_ARGS='--archives-only'
```

*BTRBORG_BTRBK_ARGS*
	Options passed to *btrbk list latest*, most usefully
	_-c /etc/btrbk/other.conf_ to select a configuration file.
	Default: empty.

*BTRBORG_BORG*, *BTRBORG_BTRBK*
	The borg and btrbk executables to use. Default: _borg_ and _btrbk_
	from _PATH_.

*BTRBORG_CONFIG*
	Path of the configuration file, if *--config* is not given.

The option variables above are split on whitespace, so a value cannot
contain an argument with spaces in it. Use *BORG_\** variables or a wrapper
script for anything more involved.

# BORG VARIABLES

Everything borg reads from the environment is passed through unchanged. The
ones that typically belong in this file are:

*BORG_PASSPHRASE*, *BORG_PASSCOMMAND*
	Passphrase of the repositories, or a command printing it. All
	repositories below _BORG_REPO_BASE_ share it.

*BORG_RSH*
	The ssh command used for remote repositories, for example
	_ssh -i /root/.ssh/borg_.

*BORG_REMOTE_PATH*
	The borg executable on the remote side.

*BORG_RELOCATED_REPO_ACCESS_IS_OK*, *BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK*
	Answer borg's interactive questions in unattended runs.

See *borg*(1) for the full list.

# EXAMPLE

```
# Repositories live on a remote host, one per subvolume.
BORG_REPO_BASE='ssh://borg@backup.example.org/./btrbk'
BORG_RSH='ssh -i /root/.ssh/borg-backup'

# Keep a bit less than the default.
BTRBORG_KEEP='--keep-daily 7 --keep-weekly 4 --keep-monthly 6'
BTRBORG_COMPRESSION='zstd,6'
BTRBORG_CREATE_ARGS='--exclude-caches'

# btrbk configuration of the snapshots to back up.
BTRBORG_BTRBK_ARGS='-c /etc/btrbk/btrbk.conf'

# The passphrase lives in a root-only file.
. /etc/btrborg.secret
```

# SEE ALSO

*btrborg*(1), *borg*(1), *btrbk.conf*(5)
