#!/bin/bash
# =============================================================================
# Generate a single unified USAGE.md from the per-resource pages.
#
# Usage:
#   bash docs/resources/build-usage.sh
#
# Output:
#   docs/resources/USAGE.md
#
# The individual per-resource pages remain the source of truth. This script
# stitches them together so you have one printable/searchable document.
# =============================================================================

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/USAGE.md"

# Canonical ordering (same order as the index). Keeping this explicit rather
# than alphabetical because the reading order matters.
LINUX_ORDER=(
  package file file_content execute directory service
  user group sysctl cron line_in_file
  mount_fs timezone locale host_entry
)
WINDOWS_ORDER=(
  File Directory Package Execute WindowsService RegistryKey
  WindowsFeature PowerShellModule Certificate
  LocalUser LocalGroup HostEntry EnvironmentVariable
  ScheduledTask DscResource
)

# --- Emit header ------------------------------------------------------------

cat > "$OUT" <<'EOF'
# SSM Converge - Unified Resource Reference

*Generated from the per-resource pages in `docs/resources/linux/` and `docs/resources/windows/`. Run `bash docs/resources/build-usage.sh` to regenerate.*

This document stitches together the complete reference for every built-in resource shipped with SSM Converge. For editing or deep-linking, prefer the per-resource pages in the same directory - they're the source of truth.

## How resources work

Resources are the vocabulary of the DSL. Each resource declares *what* you want the system to look like; SSM Converge figures out *how* to get there, idempotently, and records the result.

Every resource shares the same contract:

- **Check** the current state on the host.
- **Apply** the change only when the state differs (skipped in `audit` mode).
- **Record** the outcome (`compliant` / `non_compliant` / `error`) for the compliance report.
- **Notify** handlers if the resource changed and specified a handler.

Resources are platform-specific. Linux configurations source `lib.sh` and get bash functions with lowercase-underscore names (`package`, `file`, `line_in_file`). Windows configurations dot-source `lib.ps1` and get PowerShell functions with PascalCase names (`Package`, `File`, `WindowsService`).

## Common conventions

### States

Linux resources take a bare desired state as the second positional argument:

```bash
package 'nginx' installed
file    '/etc/motd' present
service 'nginx' running enabled
```

Windows resources take an explicit `State` parameter:

```powershell
Package        'nginx' Installed
File           'C:\motd' Present
WindowsService 'nginx' Running -StartupType Automatic
```

Both accept a state-neutral `present`/`absent` pair as an alias for resource-specific names (`installed`/`uninstalled`, `running`/`stopped`).

### Destroy mode

When the library is invoked with `DSC_MODE=destroy`, most resources flip their desired state:

| Declared | Destroy-mode effective |
|----------|------------------------|
| `present` / `installed` / `mounted` | `absent` |
| `absent` / `uninstalled` / `removed` | `present` |
| `running` | `stopped` |
| `enabled` | `disabled` |

Resources with no safe inverse (`sysctl`, `timezone`, `locale`) are skipped in destroy mode.

### Handler notification

Resources that change state can `notify` a handler. The handler runs once at the end of the configuration, no matter how many resources triggered it.

### Return codes and compliance status

| Status | When |
|--------|------|
| `compliant` | Current state matches desired state (may or may not have been fixed this run) |
| `non_compliant` | Drift detected in `audit` mode, or apply could not converge |
| `error` | Check or apply failed (missing binary, permission denied, invalid argument) |

The run exits:

- `0` - success
- `1` - one or more resources reported `error`
- `2` - `audit` mode detected drift

### Table of contents

**Linux resources:** [package](#package) - [file](#file) - [file_content](#file_content) - [execute](#execute) - [directory](#directory) - [service](#service) - [user](#user) - [group](#group) - [sysctl](#sysctl) - [cron](#cron) - [line_in_file](#line_in_file) - [mount_fs](#mount_fs) - [timezone](#timezone) - [locale](#locale) - [host_entry](#host_entry)

**Windows resources:** [File](#File-windows) - [Directory](#Directory-windows) - [Package](#Package-windows) - [Execute](#Execute) - [WindowsService](#WindowsService) - [RegistryKey](#RegistryKey) - [WindowsFeature](#WindowsFeature) - [PowerShellModule](#PowerShellModule) - [Certificate](#Certificate) - [LocalUser](#LocalUser) - [LocalGroup](#LocalGroup) - [HostEntry](#HostEntry) - [EnvironmentVariable](#EnvironmentVariable) - [ScheduledTask](#ScheduledTask) - [DscResource](#DscResource)

---

# Linux Resources

EOF

# --- Helper to splice a per-resource file, demoting its top-level heading ---
#
# Each per-resource page starts with `# resource_name`. We want that to become
# `## resource_name` inside the unified doc, and in-page headings demote one level.

splice() {
  local file="$1"
  local anchor_suffix="$2"   # '' for Linux, '-windows' for Windows disambiguation

  # Demote headings by one # level, but ONLY outside fenced code blocks.
  # Also inject a stable HTML anchor on the resource's first top-level heading
  # so TOC links land precisely regardless of the rest of the heading text.
  # Also rewrite sibling markdown links so the unified doc is self-contained:
  #   (file.md)              -> (#file)
  #   (file_content.md)      -> (#file_content)
  #   (../linux/cron.md)     -> (#cron)
  #   (DscResource.md)       -> (#DscResource)
  #   (../windows/Package.md) -> (#Package-windows)   -- but we don't need cross-
  #                                                      platform refs in practice
  awk -v suffix="$anchor_suffix" -v fname="$file" '
    BEGIN {
      n = split(fname, parts, "/")
      stem = parts[n]
      sub(/\.md$/, "", stem)
      anchor_name = stem suffix
      # A simple table: map every .md filename stem that appears inside the
      # resource docs to its anchor in the unified doc.
      # Linux stems keep their name; Windows File/Directory/Package get -windows.
      lx["package"]       = "package"
      lx["file"]          = "file"
      lx["file_content"]  = "file_content"
      lx["execute"]       = "execute"
      lx["directory"]     = "directory"
      lx["service"]       = "service"
      lx["user"]          = "user"
      lx["group"]         = "group"
      lx["sysctl"]        = "sysctl"
      lx["cron"]          = "cron"
      lx["line_in_file"]  = "line_in_file"
      lx["mount_fs"]      = "mount_fs"
      lx["timezone"]      = "timezone"
      lx["locale"]        = "locale"
      lx["host_entry"]    = "host_entry"
      lx["File"]          = "File-windows"
      lx["Directory"]     = "Directory-windows"
      lx["Package"]       = "Package-windows"
      lx["Execute"]             = "Execute"
      lx["WindowsService"]      = "WindowsService"
      lx["RegistryKey"]         = "RegistryKey"
      lx["WindowsFeature"]      = "WindowsFeature"
      lx["PowerShellModule"]    = "PowerShellModule"
      lx["Certificate"]         = "Certificate"
      lx["LocalUser"]           = "LocalUser"
      lx["LocalGroup"]          = "LocalGroup"
      lx["HostEntry"]           = "HostEntry"
      lx["EnvironmentVariable"] = "EnvironmentVariable"
      lx["ScheduledTask"]       = "ScheduledTask"
      lx["DscResource"]         = "DscResource"
      in_fence = 0
      first_h1_done = 0
    }
    /^```/ { in_fence = !in_fence; print; next }
    {
      line = $0
      if (!in_fence) {
        # Rewrite sibling markdown links -> in-doc anchors.
        # Pattern: ](something/name.md) or ](name.md)
        while (match(line, /\]\([^)]*[A-Za-z_]+\.md\)/)) {
          fragment = substr(line, RSTART, RLENGTH)
          # Extract just the filename stem.
          stem_found = fragment
          sub(/^.*\//, "", stem_found)
          sub(/\.md\)$/, "", stem_found)
          sub(/^\]\(/, "", stem_found)
          if (stem_found in lx) {
            replacement = "](#" lx[stem_found] ")"
          } else {
            # Unknown .md reference — leave as-is by prefixing a marker that
            # prevents re-matching on this iteration.
            replacement = "](UNKNOWN_" stem_found ".md)"
          }
          line = substr(line, 1, RSTART - 1) replacement substr(line, RSTART + RLENGTH)
        }
      }
      # Heading demotion (outside fences).
      if (!in_fence && line ~ /^#+ /) {
        if (!first_h1_done && line ~ /^# /) {
          first_h1_done = 1
          # Use {#anchor} attribute syntax so MkDocs Material recognises it.
          print "## " substr(line, 3) " { #" anchor_name " }"
          next
        }
        print "#" line
        next
      }
      print line
    }
  ' "$file"

  echo ""
  echo "---"
  echo ""
}

# --- Splice Linux resources ------------------------------------------------

for name in "${LINUX_ORDER[@]}"; do
  file="$ROOT/linux/$name.md"
  if [ ! -f "$file" ]; then
    echo "warning: missing $file" >&2
    continue
  fi
  splice "$file" "" >> "$OUT"
done

# --- Windows section ------------------------------------------------------

cat >> "$OUT" <<'EOF'

# Windows Resources

EOF

for name in "${WINDOWS_ORDER[@]}"; do
  file="$ROOT/windows/$name.md"
  if [ ! -f "$file" ]; then
    echo "warning: missing $file" >&2
    continue
  fi
  # File / Directory / Package share names with Linux resources; disambiguate.
  case "$name" in
    File|Directory|Package) splice "$file" "-windows" >> "$OUT" ;;
    *)                      splice "$file" ""         >> "$OUT" ;;
  esac
done

# --- Footer ---------------------------------------------------------------

cat >> "$OUT" <<'EOF'

---

*Source files: per-resource pages in [Linux index](index.md#linux-index) and [Windows index](index.md#windows-index). Regenerate with `bash docs/resources/build-usage.sh`.*
EOF

echo "Wrote $OUT ($(wc -l < "$OUT") lines, $(wc -c < "$OUT") bytes)"
