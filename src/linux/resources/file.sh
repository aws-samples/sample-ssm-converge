#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# SSM Converge — Resource Provider: file
#
# Manage a single file: content, ownership, mode, optional remote source.
#
# Source schemes:
#   s3://bucket/key                 — fetched with `aws s3 cp`
#   https://host/path , http://...  — fetched with curl (or wget fallback)
#   file:///abs/path , /abs/path    — local copy
#
# Idempotency for remote sources:
#   - With `checksum 'sha256:...'`, the file is compared against the expected
#     hash. Subsequent runs are no-ops once the hash matches.
#   - Without `checksum`, presence of the file is treated as compliant
#     (cheap; pin a checksum if you need drift detection).
#
# Authentication for HTTP(S):
#   auth_bearer 'TOKEN'             — adds 'Authorization: Bearer TOKEN'
#   auth_basic  'user:pass'         — HTTP basic auth
#   header      'Name: value'       — repeatable; arbitrary header
#
# Auth values are passed via stdin/argv so they don't appear in process listings.
#
# Usage:
#   file '/etc/nginx/nginx.conf' present source 's3://bucket/nginx.conf' \
#        owner 'root' mode '0644'
#
#   file '/etc/motd' present content 'Welcome to production'
#
#   file '/tmp/agent.deb' present \
#        source   'https://example.com/agent.deb' \
#        checksum 'sha256:a1b2c3...' \
#        mode '0644'
#
#   file '/tmp/release.tgz' present \
#        source      'https://api.github.com/repos/x/y/releases/assets/123' \
#        auth_bearer "$GITHUB_TOKEN" \
#        header      'Accept: application/octet-stream'
#
#   file '/tmp/lib.jar' present \
#        source     'https://nexus.corp/private/lib.jar' \
#        auth_basic 'svc-deploy:S3cret'
#
#   file '/tmp/debug.log' absent
#
#   # Multi-line content with file_content helper:
#   file_content '/etc/nginx/conf.d/app.conf' <<'EOF'
#   server {
#       listen 80;
#       server_name app.example.com;
#   }
#   EOF
# ═══════════════════════════════════════════════════════════════════════════════

# ─── file_content: heredoc-friendly file creation ─────────────────────────────
# Reads content from stdin (heredoc), supports same attributes as file resource.
#
# Usage:
#   file_content '/path/to/file' [owner 'x'] [group 'x'] [mode 'x'] [notify 'handler'] <<'EOF'
#   file contents here
#   multiple lines supported
#   EOF

file_content() {
  local path="$1"
  shift

  # Read remaining args (attributes)
  local owner="" group="" mode="" notify=""
  while [ $# -gt 0 ]; do
    case "$1" in
      owner)  owner="$2"; shift 2 ;;
      group)  group="$2"; shift 2 ;;
      mode)   mode="$2"; shift 2 ;;
      notify) notify="$2"; shift 2 ;;
      *)      shift ;;
    esac
  done

  # Read content from stdin (heredoc)
  local content
  content=$(cat)

  # Delegate to file resource
  file "$path" present \
    content "$content" \
    ${owner:+owner "$owner"} \
    ${group:+group "$group"} \
    ${mode:+mode "$mode"} \
    ${notify:+notify "$notify"}
}

# ─── Internal: download a URL/URI to a destination path ───────────────────────
# Args:
#   $1 dest_path    where to write the file
#   $2 source_uri   s3://, https://, http://, file://, or absolute path
#   $3 auth_bearer  optional bearer token (HTTP only)
#   $4 auth_basic   optional 'user:pass' (HTTP only)
#   $5 headers_var  name of a bash array variable holding header strings
# Returns 0 on success, 1 on failure. Stderr captures details.
_file_fetch() {
  local dest="$1" src="$2" auth_bearer="$3" auth_basic="$4" headers_var="$5"

  case "$src" in
    s3://*)
      aws s3 cp "$src" "$dest" --quiet 2>/dev/null
      return $?
      ;;
    http://*|https://*)
      _file_fetch_http "$dest" "$src" "$auth_bearer" "$auth_basic" "$headers_var"
      return $?
      ;;
    file://*)
      local local_src="${src#file://}"
      cp -f "$local_src" "$dest" 2>/dev/null
      return $?
      ;;
    /*)
      # Bare absolute path — local copy.
      cp -f "$src" "$dest" 2>/dev/null
      return $?
      ;;
    *)
      _debug "file: unsupported source scheme: $src"
      return 1
      ;;
  esac
}

# ─── Internal: HTTP(S) download via curl (preferred) or wget fallback ────────
# Auth and headers go through a curl config file written to a tmpfs (or /tmp)
# and removed on return so secrets don't appear in `ps`.
_file_fetch_http() {
  local dest="$1" src="$2" auth_bearer="$3" auth_basic="$4" headers_var="$5"

  if command -v curl &>/dev/null; then
    local cfg_dir="/dev/shm"
    [ -d "$cfg_dir" ] && [ -w "$cfg_dir" ] || cfg_dir="/tmp"
    local cfg
    cfg=$(mktemp "$cfg_dir/.ssm-converge-curl.XXXXXX") || return 1
    chmod 600 "$cfg"

    {
      echo "silent"
      echo "show-error"
      echo "fail"
      echo "location"
      echo "retry = 3"
      echo "retry-delay = 2"
      echo "connect-timeout = 30"
      echo "max-time = 600"
      if [ -n "$auth_bearer" ]; then
        printf 'header = "Authorization: Bearer %s"\n' "$auth_bearer"
      fi
      if [ -n "$auth_basic" ]; then
        printf 'user = "%s"\n' "$auth_basic"
      fi
      if [ -n "$headers_var" ]; then
        # Safe expansion for empty arrays under set -u.
        eval "local _hcount=\${#${headers_var}[@]}"
        if [ "${_hcount:-0}" -gt 0 ]; then
          local _h
          eval "for _h in \"\${${headers_var}[@]}\"; do printf 'header = \"%s\"\\n' \"\$_h\"; done"
        fi
      fi
      printf 'output = "%s"\n' "$dest"
      printf 'url = "%s"\n' "$src"
    } >> "$cfg"

    curl --config "$cfg" 2>/dev/null
    local rc=$?
    rm -f "$cfg"
    return $rc
  fi

  if command -v wget &>/dev/null; then
    local args=(--quiet --tries=3 --timeout=30 -O "$dest")
    [ -n "$auth_bearer" ] && args+=(--header="Authorization: Bearer $auth_bearer")
    if [ -n "$auth_basic" ]; then
      local user="${auth_basic%%:*}" pass="${auth_basic#*:}"
      args+=(--user="$user" --password="$pass")
    fi
    if [ -n "$headers_var" ]; then
      eval "local _hcount=\${#${headers_var}[@]}"
      if [ "${_hcount:-0}" -gt 0 ]; then
        local _h
        eval "for _h in \"\${${headers_var}[@]}\"; do args+=(--header=\"\$_h\"); done"
      fi
    fi
    wget "${args[@]}" "$src" 2>/dev/null
    return $?
  fi

  _debug "file: neither curl nor wget available for HTTP(S) download"
  return 1
}

# ─── Internal: compute SHA-256 of a file ──────────────────────────────────────
_file_sha256() {
  sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

# ─── Internal: parse 'sha256:HEX' or just 'HEX' into a lowercase hex string ──
_file_parse_checksum() {
  local raw="$1"
  raw="${raw#sha256:}"
  raw="${raw#SHA256:}"
  echo "$raw" | tr '[:upper:]' '[:lower:]'
}

file() {
  local path="$1"
  local desired="$2"
  shift 2

  # Flip state in destroy mode
  if _is_destroy_mode; then
    desired=$(_flip_state "$desired")
  fi

  # Parse keyword args
  local source="" owner="" group="" mode="" content="" notify=""
  local checksum="" auth_bearer="" auth_basic=""
  local _headers=()
  while [ $# -gt 0 ]; do
    case "$1" in
      source)      source="$2"; shift 2 ;;
      owner)       owner="$2"; shift 2 ;;
      group)       group="$2"; shift 2 ;;
      mode)        mode="$2"; shift 2 ;;
      content)     content="$2"; shift 2 ;;
      notify)      notify="$2"; shift 2 ;;
      checksum)    checksum="$2"; shift 2 ;;
      auth_bearer) auth_bearer="$2"; shift 2 ;;
      auth_basic)  auth_basic="$2"; shift 2 ;;
      header)      _headers+=("$2"); shift 2 ;;
      *)           shift ;;
    esac
  done

  local check_start=$(_now_ms)
  local resource_name="file$path"
  local expected_hash=""
  if [ -n "$checksum" ]; then
    expected_hash=$(_file_parse_checksum "$checksum")
  fi

  # Determine if the source is a remote URL (vs local/inline).
  local is_remote=false
  case "$source" in
    s3://*|http://*|https://*|file://*) is_remote=true ;;
  esac

  case "$desired" in
    present)
      local compliant=true
      local reasons=()

      # Check existence
      if [ ! -f "$path" ]; then
        compliant=false
        reasons+=("missing")
      else
        # Inline content drift — hash compare against current file.
        if [ -n "$content" ]; then
          local desired_content_hash
          desired_content_hash=$(printf '%s' "$content" | sha256sum | cut -d' ' -f1)
          local current_hash
          current_hash=$(_file_sha256 "$path")
          if [ "$desired_content_hash" != "$current_hash" ]; then
            compliant=false
            reasons+=("content drift")
          fi
        fi

        # Remote source drift — if checksum given, compare; otherwise trust presence.
        if [ -n "$source" ] && [ -z "$content" ]; then
          if [ -n "$expected_hash" ]; then
            local current_hash
            current_hash=$(_file_sha256 "$path")
            if [ "$current_hash" != "$expected_hash" ]; then
              compliant=false
              reasons+=("checksum mismatch")
            fi
          elif [ "$is_remote" = "true" ] && [ "${source#s3://}" != "$source" ]; then
            # S3 + no checksum: legacy behaviour, hash-compare against fresh fetch.
            local tmp_compare
            tmp_compare=$(mktemp)
            if aws s3 cp "$source" "$tmp_compare" --quiet 2>/dev/null; then
              local desired_hash current_hash
              desired_hash=$(_file_sha256 "$tmp_compare")
              current_hash=$(_file_sha256 "$path")
              if [ "$desired_hash" != "$current_hash" ]; then
                compliant=false
                reasons+=("content drift")
              fi
            fi
            rm -f "$tmp_compare"
          fi
          # HTTP(S)/file://+no checksum: presence treated as compliant.
        fi

        # Check owner
        if [ -n "$owner" ]; then
          local cur_owner=$(stat -c '%U' "$path" 2>/dev/null)
          if [ "$cur_owner" != "$owner" ]; then
            compliant=false
            reasons+=("owner is $cur_owner, want $owner")
          fi
        fi

        # Check group
        if [ -n "$group" ]; then
          local cur_group=$(stat -c '%G' "$path" 2>/dev/null)
          if [ "$cur_group" != "$group" ]; then
            compliant=false
            reasons+=("group is $cur_group, want $group")
          fi
        fi

        # Check mode
        if [ -n "$mode" ]; then
          local cur_mode want_mode
          cur_mode=$(_normalize_mode "$(stat -c '%a' "$path" 2>/dev/null)")
          want_mode=$(_normalize_mode "$mode")
          if [ "$cur_mode" != "$want_mode" ]; then
            compliant=false
            reasons+=("mode is $cur_mode, want $want_mode")
          fi
        fi
      fi

      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if $compliant; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)

        # Ensure parent directory exists
        mkdir -p "$(dirname "$path")" 2>/dev/null

        # Write content
        if [ -n "$source" ]; then
          if ! _file_fetch "$path" "$source" "$auth_bearer" "$auth_basic" _headers; then
            local apply_end=$(_now_ms)
            local apply_ms=$((apply_end - apply_start))
            _log_error "$resource_name" "failed to download from $source"
            _record_result "$resource_name" "error" false "download failed" $check_ms $apply_ms
            return 1
          fi
          # Verify checksum after download if provided.
          if [ -n "$expected_hash" ]; then
            local got_hash
            got_hash=$(_file_sha256 "$path")
            if [ "$got_hash" != "$expected_hash" ]; then
              local apply_end=$(_now_ms)
              local apply_ms=$((apply_end - apply_start))
              _log_error "$resource_name" "checksum mismatch after download (got $got_hash)"
              _record_result "$resource_name" "error" false "checksum mismatch" $check_ms $apply_ms
              rm -f "$path"
              return 1
            fi
          fi
        elif [ -n "$content" ]; then
          printf '%s' "$content" > "$path"
        elif [ ! -f "$path" ]; then
          touch "$path"
        fi

        # Set attributes
        if [ -n "$owner" ] && [ -n "$group" ]; then
          chown "${owner}:${group}" "$path" 2>/dev/null
        elif [ -n "$owner" ]; then
          chown "$owner" "$path" 2>/dev/null
        elif [ -n "$group" ]; then
          chgrp "$group" "$path" 2>/dev/null
        fi

        [ -n "$mode" ] && chmod "$mode" "$path" 2>/dev/null

        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))

        local reason_str=$(IFS=', '; echo "${reasons[*]}")
        _log_changed "$resource_name" "converged ($reason_str)"
        _record_result "$resource_name" "compliant" true "converged: $reason_str" $check_ms $apply_ms

        # Trigger handler if specified
        [ -n "$notify" ] && _notify_handler "$notify"
      else
        local reason_str=$(IFS=', '; echo "${reasons[*]}")
        _log_drift "$resource_name" "$reason_str"
        _record_result "$resource_name" "non_compliant" false "$reason_str" $check_ms 0
      fi
      ;;

    absent)
      local check_end=$(_now_ms)
      local check_ms=$((check_end - check_start))

      if [ ! -f "$path" ]; then
        _log_ok "$resource_name"
        _record_result "$resource_name" "compliant" false "" $check_ms 0
      elif _should_apply; then
        local apply_start=$(_now_ms)
        rm -f "$path"
        local apply_end=$(_now_ms)
        local apply_ms=$((apply_end - apply_start))

        _log_changed "$resource_name" "removed"
        _record_result "$resource_name" "compliant" true "removed" $check_ms $apply_ms
      else
        _log_drift "$resource_name" "exists (should be absent)"
        _record_result "$resource_name" "non_compliant" false "exists" $check_ms 0
      fi
      ;;

    *)
      _log_error "$resource_name" "unknown desired state: $desired"
      _record_result "$resource_name" "error" false "unknown state: $desired"
      return 1
      ;;
  esac
}
