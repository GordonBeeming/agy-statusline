#!/bin/bash
# High-performance asynchronous statusline for agy

CACHE_FILE="${HOME}/.gemini/antigravity-cli/scripts/.statusline-cache-output"
LOCK_FILE="${CACHE_FILE}.lock"

# 1. Print the cached output immediately to stdout so the UI renders instantly
cat "$CACHE_FILE" 2>/dev/null || true

# 2. Spawn a background worker to consume stdin and update the cache.
# We redirect stdout and stderr to /dev/null so Go's exec.Cmd.Output() unblocks immediately.
# We inherit stdin (<&0) so agy can write its JSON payload without getting a SIGPIPE.
(
  # Read the full JSON payload from stdin to prevent agy from blocking or erroring
  payload=$(cat)
  
  # Remove stale lock file if older than 10 seconds
  if [[ -f "$LOCK_FILE" ]]; then
    now=$(date +%s)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      lock_mtime=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
    else
      lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
    fi
    if (( now - lock_mtime > 10 )); then
      rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
  fi

  # Try to acquire the lock to prevent concurrent heavy computations
  if ( set -o noclobber; > "$LOCK_FILE" ) 2>/dev/null; then
    trap 'rm -f "$LOCK_FILE"' EXIT HUP INT TERM

    # Helper function to check if a value is present and non-null/non-empty
    is_valid_val() {
      local val="$1"
      [[ -n "$val" && "$val" != "null" && "$val" != "empty" ]]
    }

    # Extract fields using jq with fallback paths for agy/antigravity CLI formats
    model_name=$(echo "$payload" | jq -r '.model | if type == "object" then (.display_name // .id // empty) elif type == "string" then . else empty end' 2>/dev/null || true)
    effort_level=$(echo "$payload" | jq -r '.effort // .model.effort | if type == "string" then . elif type == "number" or type == "boolean" then tostring else empty end' 2>/dev/null || true)
    thinking_enabled=$(echo "$payload" | jq -r '.thinking // .model.thinking // empty' 2>/dev/null || true)
    session_cost_usd=$(echo "$payload" | jq -r '.sessionCost // .session_cost // .cost // empty' 2>/dev/null || true)
    daily_cost=$(echo "$payload" | jq -r '.dailyCost // .daily_cost // empty' 2>/dev/null || true)
    currency_rate=$(echo "$payload" | jq -r '.currencyRate // .currency_rate // empty' 2>/dev/null || true)
    total_input=$(echo "$payload" | jq -r '.totalInputTokens // .total_input_tokens // .context_window.total_input_tokens // empty' 2>/dev/null || true)
    total_output=$(echo "$payload" | jq -r '.totalOutputTokens // .total_output_tokens // .context_window.total_output_tokens // empty' 2>/dev/null || true)
    cwd=$(echo "$payload" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
    five_hour_pct=$(echo "$payload" | jq -r '.fiveHourRateLimitPercent // .five_hour_rate_limit_percent // (if .quota["gemini-5h"].remaining_fraction != null then ((1.0 - .quota["gemini-5h"].remaining_fraction) * 100) elif .quota["3p-5h"].remaining_fraction != null then ((1.0 - .quota["3p-5h"].remaining_fraction) * 100) else empty end)' 2>/dev/null || true)
    five_hour_resets=$(echo "$payload" | jq -r '.fiveHourRateLimitResetsAt // .five_hour_rate_limit_resets_at // (if .quota["gemini-5h"].reset_in_seconds != null then (now + .quota["gemini-5h"].reset_in_seconds) elif .quota["3p-5h"].reset_in_seconds != null then (now + .quota["3p-5h"].reset_in_seconds) else empty end)' 2>/dev/null || true)
    duration_ms=$(echo "$payload" | jq -r '.durationMs // .duration_ms // empty' 2>/dev/null || true)
    ctx_pct=$(echo "$payload" | jq -r '.contextWindowPercent // .context_window_percent // .context_window.used_percentage // empty' 2>/dev/null || true)
    ctx_size=$(echo "$payload" | jq -r '.contextWindowSize // .context_window_size // .context_window.context_window_size // empty' 2>/dev/null || true)

    if ! is_valid_val "$currency_rate" || [[ "$currency_rate" == "0" ]]; then
      currency_rate=1
    fi

    # Formatting utilities
    RESET="\033[0m"
    DIM="\033[2m"
    RED="\033[31m"
    YELLOW="\033[33m"
    GREEN="\033[32m"
    
    format_cost() {
      local val="$1"
      local is_daily="${2:-}"
      local sym="${STATUSLINE_CURRENCY:-A$}"
      
      local is_zero
      is_zero=$(awk -v v="$val" 'BEGIN { print (v == 0 ? 1 : 0) }' 2>/dev/null || echo 1)
      
      if [[ "$is_zero" -eq 1 ]]; then
        echo -e "${DIM}${sym}0.00${RESET}"
      else
        local color="$GREEN"
        if [[ "$is_daily" == "daily" ]]; then
          local ge5 ge2
          ge5=$(awk -v v="$val" 'BEGIN { print (v >= 5.0 ? 1 : 0) }' 2>/dev/null || echo 0)
          ge2=$(awk -v v="$val" 'BEGIN { print (v >= 2.0 ? 1 : 0) }' 2>/dev/null || echo 0)
          if [[ "$ge5" -eq 1 ]]; then color="$RED";
          elif [[ "$ge2" -eq 1 ]]; then color="$YELLOW"; fi
        else
          local ge1 ge05
          ge1=$(awk -v v="$val" 'BEGIN { print (v >= 1.0 ? 1 : 0) }' 2>/dev/null || echo 0)
          ge05=$(awk -v v="$val" 'BEGIN { print (v >= 0.5 ? 1 : 0) }' 2>/dev/null || echo 0)
          if [[ "$ge1" -eq 1 ]]; then color="$RED";
          elif [[ "$ge05" -eq 1 ]]; then color="$YELLOW"; fi
        fi
        echo -e "${color}${sym}${val}${RESET}"
      fi
    }
    
    make_bar() {
      local pct="$1"
      local width="$2"
      (( pct < 0 )) && pct=0
      (( pct > 100 )) && pct=100
      local filled=$(( pct * width / 100 ))
      (( filled < 0 )) && filled=0
      (( filled > width )) && filled=width
      local empty=$(( width - filled ))
      local color="$GREEN"
      if (( pct > 90 )); then color="$RED"
      elif (( pct > 75 )); then color="$YELLOW"
      fi
      local bar_str=""
      if (( filled > 0 )); then bar_str+="${color}$(printf '█%.0s' $(seq 1 $filled))${RESET}"; fi
      if (( empty > 0 )); then bar_str+="${DIM}$(printf '░%.0s' $(seq 1 $empty))${RESET}"; fi
      echo -e "$bar_str"
    }

    join_parts() {
      local parts=("$@")
      local result=""
      for ((i=0; i<${#parts[@]}; i++)); do
        if (( i > 0 )); then result+=" · "; fi
        result+="${parts[i]}"
      done
      echo -e "$result"
    }

    # Repository & Branch Info
    in_git_repo=false
    repo_name=""
    if toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
      repo_name=$(basename "$toplevel")
      in_git_repo=true
    elif is_valid_val "$cwd"; then
      repo_name=$(basename "$cwd")
    else
      repo_name=$(basename "$(pwd -P 2>/dev/null || pwd 2>/dev/null || true)")
    fi

    term_width=${COLUMNS:-0}
    if (( term_width == 0 )); then term_width=$(tput cols 2>/dev/null || echo 100); fi
    branch_line_budget=$(( term_width - 5 ))
    (( branch_line_budget < 20 )) && branch_line_budget=20

    branch_info=""
    current_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "")
    [[ -z "$current_branch" && -z "$cwd" ]] && current_branch=$(git branch --show-current 2>/dev/null || echo "")

    if [[ "$current_branch" == "gitbutler/workspace" ]]; then
      branch_emoji="🌿"
      branch_names=()
      if command -v but &>/dev/null; then
        local cmd_timeout=""
        if command -v timeout &>/dev/null; then cmd_timeout="timeout 1"
        elif command -v gtimeout &>/dev/null; then cmd_timeout="gtimeout 1"; fi
        but_json=$(cd "${cwd:-.}" 2>/dev/null && ${cmd_timeout} but branch list --no-check --no-ahead --json 2>/dev/null || echo '{}')
        while IFS= read -r b; do
          [[ -n "$b" ]] && branch_names+=("$b")
        done < <(echo "$but_json" | jq -r '.appliedStacks[].heads[].name' 2>/dev/null || true)
      fi
      branch_count=${#branch_names[@]}

      if (( branch_count == 0 )); then
        branch_info="${branch_emoji} gitbutler/workspace"
      elif (( branch_count == 1 )); then
        name="${branch_names[0]}"
        (( ${#name} > branch_line_budget )) && name="${name:0:$((branch_line_budget - 1))}…"
        branch_info="${branch_emoji} ${name}"
      else
        shown=""
        shown_count=0
        for name in "${branch_names[@]}"; do
          candidate="${shown:+$shown, }$name"
          remaining_after=$(( branch_count - shown_count - 1 ))
          suffix=""
          (( remaining_after > 0 )) && suffix=" + ${remaining_after} more"
          if (( ${#candidate} + ${#suffix} <= branch_line_budget )); then
            shown="$candidate"
            (( shown_count++ ))
          else
            break
          fi
        done
        if (( shown_count == 0 )); then
          remaining_after=$(( branch_count - 1 ))
          suffix=" + ${remaining_after} more"
          first_budget=$(( branch_line_budget - ${#suffix} ))
          (( first_budget < 8 )) && first_budget=8
          first="${branch_names[0]}"
          (( ${#first} > first_budget )) && first="${first:0:$((first_budget - 1))}…"
          branch_info="${branch_emoji} ${first}${suffix}"
        else
          remaining_after=$(( branch_count - shown_count ))
          if (( remaining_after > 0 )); then
            branch_info="${branch_emoji} ${shown} + ${remaining_after} more"
          else
            branch_info="${branch_emoji} ${shown}"
          fi
        fi
      fi
    elif [[ -n "$current_branch" ]]; then
      truncated_branch="$current_branch"
      (( ${#truncated_branch} > branch_line_budget )) && truncated_branch="${truncated_branch:0:$((branch_line_budget - 1))}…"
      branch_info="🔀 ${truncated_branch}"
    fi

    # Formatting blocks
    model_display=""
    is_valid_val "$model_name" && model_display="🤖 ${model_name}"

    effort_display=""
    if is_valid_val "$effort_level"; then
      case "$effort_level" in
        low)       effort_display=$(printf '⚡ %b%s%b' "$DIM" "$effort_level" "$RESET") ;;
        medium)    effort_display="⚡ ${effort_level}" ;;
        high)      effort_display=$(printf '⚡ %b%s%b' "$YELLOW" "$effort_level" "$RESET") ;;
        xhigh|max) effort_display=$(printf '⚡ %b%s%b' "$RED" "$effort_level" "$RESET") ;;
        *)         effort_display="⚡ ${effort_level}" ;;
      esac
    fi

    thinking_display=""
    [[ "$thinking_enabled" == "true" ]] && thinking_display="🤔"

    session_cost_local=""
    if is_valid_val "$session_cost_usd" && [[ "$session_cost_usd" != "0" ]]; then
      session_cost_val=$(echo "$session_cost_usd $currency_rate" | awk '{printf "%.2f", $1 * $2}' 2>/dev/null || echo "0.00")
      if [[ "$session_cost_val" != "0.00" ]]; then
        session_cost_local="💸 $(format_cost "$session_cost_val") session"
      fi
    fi

    daily_cost_display=""
    if is_valid_val "$daily_cost" && [[ "$daily_cost" != "0" ]]; then
      daily_cost_val=$(echo "$daily_cost $currency_rate" | awk '{printf "%.2f", $1 * $2}' 2>/dev/null || echo "0.00")
      if [[ "$daily_cost_val" != "0.00" ]]; then
        daily_cost_display="💰 $(format_cost "$daily_cost_val" daily) today"
      fi
    fi

    rate_display=""
    if is_valid_val "$five_hour_pct"; then
      pct_int=${five_hour_pct%.*}
      if [[ -n "$pct_int" ]]; then
        bar=$(make_bar "$pct_int" 10)
        time_left=""
        if is_valid_val "$five_hour_resets"; then
          now_ts=$(date +%s)
          resets_int=${five_hour_resets%.*}
          if [[ -n "$resets_int" ]]; then
            remaining=$(( resets_int - now_ts ))
            if (( remaining > 0 )); then
              hours_left=$(( remaining / 3600 ))
              mins_left=$(( (remaining % 3600) / 60 ))
              time_left=" ${hours_left}h${mins_left}m left"
            fi
          fi
        fi
        rate_display="⏱️ ${bar} ${pct_int}%${time_left}"
      fi
    elif is_valid_val "$duration_ms" && [[ "$duration_ms" != "0" ]]; then
      dur_int=${duration_ms%.*}
      if [[ -n "$dur_int" && "$dur_int" -gt 0 ]]; then
        duration_secs=$(( dur_int / 1000 ))
        if (( duration_secs > 0 )); then
          hours=$(( duration_secs / 3600 ))
          mins=$(( (duration_secs % 3600) / 60 ))
          rate_display="⏱️ ${hours}h${mins}m"
        fi
      fi
    fi

    ctx_display=""
    if is_valid_val "$ctx_size" && [[ "$ctx_size" != "0" ]]; then
      if is_valid_val "$ctx_pct"; then
        ctx_int=${ctx_pct%.*}
        if [[ -n "$ctx_int" ]] && (( ctx_int > 0 )); then
          ctx_bar=$(make_bar "$ctx_int" 10)
          ctx_display="💭 ${ctx_bar} ${ctx_int}% ctx"
        fi
      fi
    fi

    token_display=""
    if is_valid_val "$total_input"; then
      inp_int=${total_input%.*}
      out_int=${total_output%.*}
      inp_int=${inp_int:-0}
      out_int=${out_int:-0}
      if (( inp_int > 0 )); then
        in_k=$(( inp_int / 1000 ))
        out_k=$(( out_int / 1000 ))
        token_display="🧠 ${in_k}k in / ${out_k}k out"
      fi
    fi

    # Assemble lines
    line1_parts=()
    if [[ -n "$repo_name" ]]; then
      if [[ "$in_git_repo" == "true" ]]; then line1_parts+=("📂 ${repo_name}");
      else line1_parts+=("📁 ${repo_name} $(printf '%b🚫 no git%b' "$DIM" "$RESET")"); fi
    fi
    [[ -n "$model_display" ]] && line1_parts+=("$model_display")
    [[ -n "$effort_display" ]] && line1_parts+=("$effort_display")
    [[ -n "$thinking_display" ]] && line1_parts+=("$thinking_display")

    line2_parts=()
    [[ -n "$branch_info" ]] && line2_parts+=("$branch_info")

    line3_parts=()
    [[ -n "$session_cost_local" ]] && line3_parts+=("$session_cost_local")
    [[ -n "$daily_cost_display" ]] && line3_parts+=("$daily_cost_display")
    [[ -n "$rate_display" ]] && line3_parts+=("$rate_display")

    line4_parts=()
    [[ -n "$ctx_display" ]] && line4_parts+=("$ctx_display")
    [[ -n "$token_display" ]] && line4_parts+=("$token_display")

    output=""
    if (( ${#line1_parts[@]} > 0 )); then output+=$(join_parts "${line1_parts[@]}"); fi
    if (( ${#line2_parts[@]} > 0 )); then [[ -n "$output" ]] && output+=$'\n'; output+=$(join_parts "${line2_parts[@]}"); fi
    if (( ${#line3_parts[@]} > 0 )); then [[ -n "$output" ]] && output+=$'\n'; output+=$(join_parts "${line3_parts[@]}"); fi
    if (( ${#line4_parts[@]} > 0 )); then [[ -n "$output" ]] && output+=$'\n'; output+=$(join_parts "${line4_parts[@]}"); fi

    # Save to cache
    echo -e "$output" > "${CACHE_FILE}.tmp"
    mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

    # Auto-update logic
    MARKER_FILE="${HOME}/.gemini/antigravity-cli/scripts/.statusline-last-update"
    if [[ -f "$MARKER_FILE" ]]; then
      last_update=$(cat "$MARKER_FILE" 2>/dev/null || echo 0)
      now=$(date +%s)
      if (( now - last_update > 86400 )); then
        echo "$now" > "$MARKER_FILE"
        curl -sSL "https://raw.githubusercontent.com/GordonBeeming/agy-statusline/main/statusline.sh" -o "${HOME}/.gemini/antigravity-cli/scripts/statusline.sh.tmp" && \
        mv "${HOME}/.gemini/antigravity-cli/scripts/statusline.sh.tmp" "${HOME}/.gemini/antigravity-cli/scripts/statusline.sh" && \
        chmod +x "${HOME}/.gemini/antigravity-cli/scripts/statusline.sh"
      fi
    fi
  fi
) <&0 >/dev/null 2>&1 &

disown 2>/dev/null || true
exit 0
