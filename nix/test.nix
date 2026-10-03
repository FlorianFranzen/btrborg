# NixOS VM test: btrfs volume with two subvolumes, btrbk snapshots, borg
# repositories managed by btrborg, and the services.btrborg module with its
# timer.
{ btrborgModule }:

{ pkgs, ... }:

let
  # Only for the test; a real passphrase never belongs in the Nix store.
  passphrase = "test-passphrase";
  envFile = pkgs.writeText "btrborg-test-env" ''
    BORG_PASSPHRASE='${passphrase}'
  '';
in
{
  name = "btrborg";

  nodes.machine =
    { ... }:
    {
      imports = [ btrborgModule ];

      environment.systemPackages = with pkgs; [
        btrfs-progs
        borgbackup
        btrbk
      ];

      services.btrbk.instances.btrbk = {
        onCalendar = null;
        settings = {
          timestamp_format = "long";
          volume."/mnt" = {
            snapshot_dir = ".snapshots";
            subvolume = {
              data = { };
              www = { };
            };
          };
        };
      };

      services.btrborg = {
        enable = true;
        repoBase = "/var/lib/borg";
        environmentFile = envFile;
        settings = {
          BTRBORG_COMPRESSION = "lz4";
          # Keep a single archive so that pruning is observable.
          BTRBORG_KEEP = "--keep-last 1";
        };
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    def borg(args):
        return machine.succeed(f"BORG_PASSPHRASE='${passphrase}' borg {args}")

    def archives(repo):
        return borg(f"list --short /var/lib/borg/{repo}").split()

    def latest_snapshot(subvol):
        return machine.succeed(f"ls -1 /mnt/.snapshots | grep '^{subvol}\\.' | sort | tail -n1").strip()

    with subtest("prepare btrfs volume and btrbk snapshots"):
        machine.succeed(
            "dd if=/dev/zero of=/data_fs bs=120M count=1",
            "mkfs.btrfs /data_fs",
            "mkdir -p /mnt",
            "mount /data_fs /mnt",
            "btrfs subvolume create /mnt/data",
            "btrfs subvolume create /mnt/www",
            "mkdir /mnt/.snapshots",
            "echo hello > /mnt/data/hello.txt",
            "echo quoted > \"/mnt/data/it's a file.txt\"",
            "mkdir -p /mnt/www/site && echo '<h1>hi</h1>' > /mnt/www/site/index.html",
            "btrbk -c /etc/btrbk/btrbk.conf run",
        )
        assert latest_snapshot("data"), "btrbk created no snapshot of data"

    with subtest("configuration file is generated"):
        def setting(name):
            return machine.succeed(f"bash -c '. /etc/btrborg.conf && printf %s \"''${name}\"'")

        assert setting("BORG_REPO_BASE") == "/var/lib/borg"
        assert setting("BTRBORG_BTRBK_ARGS") == "-c /etc/btrbk/btrbk.conf"
        assert setting("BTRBORG_COMPRESSION") == "lz4"
        assert setting("BTRBORG_KEEP") == "--keep-last 1"
        # The environment file is sourced, so secrets reach borg.
        assert setting("BORG_PASSPHRASE") == "${passphrase}"

    with subtest("list"):
        out = machine.succeed("btrborg list")
        version = latest_snapshot("data").split(".")[-1]
        assert f"data\tbtrbk.{version}\t/mnt/.snapshots/data.{version}\t/var/lib/borg/data" in out, out
        assert "\nwww\tbtrbk." in out, out
        assert machine.succeed("btrborg list www | wc -l").strip() == "1"
        assert machine.succeed("btrborg list nope 2>&1 | grep -c 'no btrbk snapshot found for subvolume'").strip() == "1"

    with subtest("init"):
        machine.succeed("btrborg init")
        borg("info /var/lib/borg/data")
        borg("info /var/lib/borg/www")
        out = machine.succeed("btrborg init")
        assert out.count("already exists") == 2, out

    with subtest("create"):
        machine.succeed("btrborg create")
        version = latest_snapshot("data").split(".")[-1]
        assert archives("data") == [f"btrbk.{version}"], archives("data")
        assert len(archives("www")) == 1

        machine.succeed(
            "mkdir /tmp/restore && cd /tmp/restore && "
            f"BORG_PASSPHRASE='${passphrase}' borg extract /var/lib/borg/data::btrbk.{version}",
            "grep -qx hello /tmp/restore/hello.txt",
            "grep -qx quoted \"/tmp/restore/it's a file.txt\"",
        )

        # Running create again must not fail or duplicate anything.
        out = machine.succeed("btrborg create")
        assert out.count("already exists") == 2, out
        assert len(archives("data")) == 1

    with subtest("info and check"):
        out = machine.succeed("btrborg info")
        assert "Archive name: btrbk." in out, out
        out = machine.succeed("btrborg check")
        assert "Checking latest backup of subvolume 'www'" in out, out

    with subtest("dry run prints commands and changes nothing"):
        out = machine.succeed("btrborg --dry-run prune")
        assert "+ borg prune --stats --keep-last 1 --glob-archives btrbk.\\* /var/lib/borg/data" in out, out
        assert len(archives("data")) == 1

    with subtest("service runs create, check, prune and compact"):
        machine.succeed(
            "echo more > /mnt/data/more.txt",
            "btrbk -c /etc/btrbk/btrbk.conf run",
        )
        new_version = latest_snapshot("data").split(".")[-1]
        assert len(machine.succeed("ls -1 /mnt/.snapshots | grep '^data\\.'").split()) == 2
        machine.succeed("systemctl start btrborg.service")
        # --keep-last 1 pruned the first archive, the new one survived.
        assert archives("data") == [f"btrbk.{new_version}"], archives("data")
        machine.succeed(
            "rm -rf /tmp/restore && mkdir /tmp/restore && cd /tmp/restore && "
            f"BORG_PASSPHRASE='${passphrase}' borg extract /var/lib/borg/data::btrbk.{new_version}",
            "grep -qx more /tmp/restore/more.txt",
        )
        journal = machine.succeed("journalctl -u btrborg.service")
        for step in ("Backing up", "Checking", "Pruning", "Compacting"):
            assert step in journal, journal

    with subtest("timer is installed"):
        machine.succeed("systemctl is-active btrborg.timer")
        timers = machine.succeed("systemctl list-timers --all btrborg.timer")
        assert "btrborg.timer" in timers, timers

    with subtest("failures are reported"):
        machine.succeed("echo 'BORG_PASSPHRASE=wrong' > /tmp/bad.conf")
        machine.succeed("echo 'BORG_REPO_BASE=/var/lib/borg' >> /tmp/bad.conf")
        status = machine.execute("btrborg -c /tmp/bad.conf info")[0]
        assert status == 1, f"expected exit status 1, got {status}"
        status, out = machine.execute("btrborg -c /nonexistent list 2>&1")
        assert status == 2 and "cannot read" in out, (status, out)
        status, out = machine.execute("btrborg bogus 2>&1")
        assert status == 2 and "unknown command" in out, (status, out)
  '';
}
