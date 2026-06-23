# `LocalGroup`

Manage a local Windows group and its membership. For AD groups, wrap `ActiveDirectoryDsc.ADGroup` via [`DscResource`](DscResource.md).

Named `LocalGroup` (not `Group`) because `Group` is an alias for PowerShell's built-in `Group-Object` cmdlet.

## Syntax

```powershell
LocalGroup '<Name>' <State> `
  [-Description <string>] `
  [-Members <string[]>] `
  [-MembersToInclude <string[]>] `
  [-MembersToExclude <string[]>]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Create the group if missing; enforce membership. |
| `Absent` | Remove the group. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | Group name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Description` | - | Group description. |
| `-Members` | - | **Declarative** list. The group's membership is REPLACED to be exactly this set. |
| `-MembersToInclude` | - | **Additive** list. These members are added; existing members left alone. |
| `-MembersToExclude` | - | **Subtractive** list. These members are removed; other members left alone. |

Use `-Members` *or* `-MembersToInclude` / `-MembersToExclude`, not both.

## Examples

Declarative - these are the only members:

```powershell
LocalGroup 'AppOperators' Present `
    -Description 'Operators of MyApp' `
    -Members     'svc_app','CORP\deployer'
```

Additive - add without removing existing members:

```powershell
LocalGroup 'Remote Desktop Users' Present `
    -MembersToInclude 'CORP\helpdesk'
```

Subtractive:

```powershell
LocalGroup 'Administrators' Present `
    -MembersToExclude 'CORP\ex-employee'
```

Remove a group:

```powershell
LocalGroup 'OldGroup' Absent
```

## Destroy mode

`Present` flips to `Absent`.

## Notes

- Members can be local accounts (`Alice`) or domain accounts (`CORP\alice`). Domain members require the host to be domain-joined and able to resolve the account.
- `-Members` with an empty array means "empty group" (removes all members).
- The compliance report counts adds and removes separately (e.g. `members: +1 -2`).
