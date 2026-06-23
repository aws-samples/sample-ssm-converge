# `mount_fs`

Mount a filesystem at a given mount point, and optionally persist the entry to `/etc/fstab`.

The function is named `mount_fs` (not `mount`) to avoid shadowing the system `mount` binary.

## Syntax

```bash
mount_fs '<mount_point>' <state> [key value ...]
```

## Actions

| State | Aliases | Effect |
|-------|---------|--------|
| `present` | `mounted` | Ensure the filesystem is mounted here, with optional fstab entry. |
| `absent` | `unmounted` | Unmount and remove the fstab entry. |

## Properties

| Property | Default | Description |
|----------|---------|-------------|
| `device` | - | Block device or NFS source (`/dev/xvdf`, `10.0.1.5:/data`). Required for `present`. |
| `fstype` | `auto` | Filesystem type (`ext4`, `xfs`, `nfs`, `nfs4`, ...). |
| `options` | `defaults` | Mount options, comma-separated. |
| `dump` | `0` | fstab dump field. |
| `pass` | `0` | fstab pass field (fsck order). |
| `persist` | `true` | Whether to add an entry to `/etc/fstab`. When `false`, only mounts for the current boot. |

## Examples

EBS volume formatted ext4:

```bash
mount_fs '/mnt/data' present \
  device '/dev/xvdf' \
  fstype 'ext4' \
  options 'defaults,noatime'
```

NFS share:

```bash
mount_fs '/mnt/shared' present \
  device '10.0.1.50:/exports/shared' \
  fstype 'nfs4' \
  options 'rw,hard,intr,rsize=32768,wsize=32768'
```

Runtime-only mount (gone after reboot):

```bash
mount_fs '/mnt/scratch' present \
  device '/dev/xvdg' \
  fstype 'xfs' \
  persist false
```

Unmount and remove from fstab:

```bash
mount_fs '/mnt/old' absent
```

## Destroy mode

`present` / `mounted` flips to `absent` / `unmounted`. The filesystem is unmounted and the fstab line is removed. Data on the device is untouched.

## Notes

- The mount point directory is created if missing.
- Compliance check compares both live mount state (`mount | grep " on <point> "`) and fstab presence. Drift is reported if either is wrong.
- Removing an entry that's currently in use returns the usual `umount: target is busy` — record that as `error` on the operator.
