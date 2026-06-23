# `LocalUser`

Manage a local Windows user account. For Active Directory users, wrap the `ActiveDirectoryDsc.ADUser` resource via [`DscResource`](DscResource.md) instead.

The DSL keyword is `LocalUser` (not `User`) to avoid conflicts with any `User` function you might already have in scope.

## Syntax

```powershell
LocalUser '<Name>' <State> `
  [-Password <secureString>] `
  [-FullName <string>] `
  [-Description <string>] `
  [-PasswordNeverExpires] `
  [-UserMayNotChangePassword] `
  [-Disabled]
```

## State

| State | Effect |
|-------|--------|
| `Present` | Create the user if missing; enforce attributes on existing user. |
| `Absent` | Remove the user. |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Name` | *(positional 0)* | User name. |
| `-State` | *(positional 1)* | `Present` or `Absent`. |
| `-Password` | *(none, created without password)* | SecureString for the password. |
| `-FullName` | - | Display name. |
| `-Description` | - | Description field. |
| `-PasswordNeverExpires` | *off* | Set password-never-expires flag. |
| `-UserMayNotChangePassword` | *off* | Prevent user from changing password. |
| `-Disabled` | *off* | Create/leave the account disabled. |

## Examples

Service account with a fixed password (from SSM Parameter Store in production):

```powershell
$pw = ConvertTo-SecureString 'REPLACE-FROM-SSM-PARAMETER-STORE' -AsPlainText -Force

LocalUser 'svc_app' Present `
    -FullName     'App service' `
    -Description  'Runs MyApp via task scheduler' `
    -Password     $pw `
    -PasswordNeverExpires
```

Remove a legacy account:

```powershell
LocalUser 'olduser' Absent
```

## Destroy mode

`Present` flips to `Absent`.

## Errors

- `LocalAccounts module not available` - on very old Windows (pre-Windows 10 / Server 2016) the `LocalAccounts` module doesn't exist. Use `DscResource` with `PSDscResources.User` instead.

## Notes

- Attribute enforcement drift-checks `FullName`, `Description`, `PasswordNeverExpires`, and `Enabled` on existing users. Password drift is not checked (we can't read it back); `Password` is only set on create.
- For membership in a group, use [`LocalGroup`](LocalGroup.md).
- Windows built-in aliases: on Windows Server the `User` PowerShell function name is reserved by some modules, so we use `LocalUser` to avoid conflicts.
