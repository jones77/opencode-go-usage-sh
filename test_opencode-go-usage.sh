#!/usr/bin/env bash
# Core tests for opencode-go-usage.sh.
# Focus on deterministic internals (bar cells/steps, duration formatting),
# not full output layouts which are brittle.
set -uo pipefail
# Do not use set -e: assertions must not abort the suite, and some stubbed
# subprocesses are expected to return non-zero (collected via if/||).

# shellcheck source=/dev/null
source ./opencode-go-usage.sh
set +e  # undo set -e inherited from the sourced script

# TAP test counter and pass/fail tallies.
n=0
pass=0
fail=0

# Derive expected color escapes from the live period_color map so the
# format_entry color tests don't silently break if the rolling color changes.
# shellcheck disable=SC2154  # period_color is assigned by the sourced script
readonly rolling_color_esc=$(printf '\033[38;5;%sm' "${period_color[rolling]}")
readonly color_reset=$'\033[39m'

assert_eq() {
    local expected="$1" actual="$2" name="$3"
    n=$((n + 1))
    if [[ "$expected" == "$actual" ]]
    then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
        printf '# expected: %q\n' "$expected"
        printf '# actual:   %q\n' "$actual"
    fi
}

assert_match() {
    local pattern="$1" actual="$2" name="$3"
    n=$((n + 1))
    if [[ "$actual" =~ $pattern ]]
    then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
        printf '# expected pattern: %s\n' "$pattern"
        printf '# actual:           %q\n' "$actual"
    fi
}

assert_nonzero() {
    local rc="$1" name="$2"
    n=$((n + 1))
    if (( rc != 0 ))
    then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
        printf '# expected non-zero exit, got 0\n'
    fi
}

assert_bar_width() {
    local percent="$1" width="$2" name="$3" style="${4:-vertical}"
    local output
    output=$(bar "$percent" "$width" "$style")
    n=$((n + 1))
    if (( ${#output} == width ))
    then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
        printf '# expected width: %d\n' "$width"
        printf '# actual width:   %d (%q)\n' "${#output}" "$output"
    fi
}

assert_bar_chars_valid() {
    local percent="$1" width="$2" name="$3" style="${4:-vertical}"
    local output bad valid
    output=$(bar "$percent" "$width" "$style")
    case "$style" in
        vertical)   valid='␣▁▂▃▄▅▆▇█' ;;
        horizontal) valid='␣▏▎▍▌▋▊▉█' ;;
        gradient)   valid='␣░▒▓█' ;;
        *)          valid='' ;;
    esac
    bad=$(printf '%s' "$output" | tr -d "$valid")
    n=$((n + 1))
    if [[ -z "$bad" ]]
    then
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    else
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
        printf '# unexpected chars: %q\n' "$bad"
    fi
}

# Runs the script as a subprocess and asserts it exits non-zero.
assert_args_fail() {
    local name="$1"
    shift
    n=$((n + 1))
    if ./opencode-go-usage.sh "$@" >/dev/null 2>&1
    then
        fail=$((fail + 1))
        printf 'not ok %d - %s\n' "$n" "$name"
    else
        pass=$((pass + 1))
        printf 'ok %d - %s\n' "$n" "$name"
    fi
}

# Reset the shared-state globals that format_entry reads, to documented
# defaults. Each format_entry test calls this then overrides only the
# fields it cares about, so a new required global won't break every test.
reset_format_entry_state() {
    display="full"
    color_mode="plain"
    one_line=false
    width=0
    numbers_mode=false
    bar_style="vertical"
    only_field="none"
}

# Reset the shared-state globals that render_output reads. render_output
# resolves use_color internally from color_mode, so that is not set here.
reset_render_output_state() {
    display="full"
    color_mode="plain"
    width="0"
    one_line=false
    date_mode=false
    numbers_mode=false
    bar_style="vertical"
    only_field="none"
    only_period="all"
}

# bar: width 1 spot checks across the 8 steps.
assert_eq "␣" "$(bar 0 1)"   "bar 0% width 1 (empty)"
assert_eq "▁" "$(bar 13 1)"  "bar ~13% width 1 (step 1)"
assert_eq "▂" "$(bar 25 1)"  "bar ~25% width 1 (step 2)"
assert_eq "▄" "$(bar 50 1)"  "bar ~50% width 1 (step 4)"
assert_eq "█" "$(bar 100 1)" "bar 100% width 1 (full)"

# bar: clamping boundaries above 100% and at the high step.
assert_eq "█" "$(bar 101 1)" "bar 101% width 1 clamps to full"
assert_eq "█" "$(bar 200 1)" "bar 200% width 1 (clamp)"
assert_eq "▇" "$(bar 99 1)"  "bar 99% width 1 (step 7)"

# bar: negative percent is treated as empty (clamp lower bound).
assert_eq "␣" "$(bar -5 1)" "bar -5% width 1 (negative treats as empty)"

# bar: width 0 produces an empty string regardless of percent.
assert_eq "" "$(bar 50 0)" "bar 50% width 0 is empty"
assert_eq "" "$(bar 0 0)"  "bar 0% width 0 is empty"

# bar: width boundaries at empty/full, including width 0.
for width in 0 1 2 3 4 5 6 7 8 9 10 11 12 13
do
    assert_bar_width 0 "$width" "bar 0% width $width length"
    assert_bar_width 100 "$width" "bar 100% width $width length"
done

# bar: valid character set for a spread of percents/widths.
for width in 0 1 2 4 8 13
do
    for percent in 0 1 12 25 37 50 63 75 87 99 100
    do
        assert_bar_chars_valid "$percent" "$width" "bar chars valid $percent% width $width"
    done
done

# bar: a specific multi-cell layout (matches the usage table).
assert_eq "██████▄␣␣␣␣␣␣" "$(bar 50 13)" "bar 50% width 13 layout"

# bar: horizontal style spot checks.
assert_eq "␣" "$(bar 0 1 horizontal)"   "bar horizontal 0% width 1 (empty)"
assert_eq "▏" "$(bar 13 1 horizontal)"  "bar horizontal ~13% width 1 (step 1)"
assert_eq "▎" "$(bar 25 1 horizontal)"  "bar horizontal ~25% width 1 (step 2)"
assert_eq "▌" "$(bar 50 1 horizontal)"  "bar horizontal ~50% width 1 (step 4)"
assert_eq "█" "$(bar 100 1 horizontal)" "bar horizontal 100% width 1 (full)"
assert_eq "██████▌␣␣␣␣␣␣" "$(bar 50 13 horizontal)" \
    "bar horizontal 50% width 13 layout"

# bar: gradient style spot checks.
assert_eq "␣" "$(bar 0 1 gradient)"     "bar gradient 0% width 1 (empty)"
assert_eq "░" "$(bar 25 1 gradient)"    "bar gradient 25% width 1 (step 1)"
assert_eq "▒" "$(bar 50 1 gradient)"    "bar gradient 50% width 1 (step 2)"
assert_eq "▓" "$(bar 75 1 gradient)"    "bar gradient 75% width 1 (step 3)"
assert_eq "█" "$(bar 100 1 gradient)"   "bar gradient 100% width 1 (full)"
assert_eq "██████▒␣␣␣␣␣␣" "$(bar 50 13 gradient)" \
    "bar gradient 50% width 13 layout"

# bar: width boundaries at empty/full for all styles.
for style in vertical horizontal gradient
do
    for width in 0 1 2 3 4 5 6 7 8 9 10 11 12 13
    do
        assert_bar_width 0 "$width" "bar $style 0% width $width length" "$style"
        assert_bar_width 100 "$width" "bar $style 100% width $width length" "$style"
    done
done

# bar: valid character set for a spread of percents/widths for all styles.
for style in vertical horizontal gradient
do
    for width in 0 1 2 4 8 13
    do
        for percent in 0 1 12 25 37 50 63 75 87 99 100
        do
            assert_bar_chars_valid "$percent" "$width" \
                "bar $style chars valid $percent% width $width" "$style"
        done
    done
done

# format_duration: pure formatting logic, including boundaries.
assert_eq "0s"               "$(format_duration 0 0 0 0)" "format_duration all zero"
assert_eq "             1s"   "$(format_duration 0 0 0 1)" "format_duration seconds only"
assert_eq "         1m    "  "$(format_duration 0 0 1 0)" "format_duration minutes only"
assert_eq "     1h        "  "$(format_duration 0 1 0 0)" "format_duration hours only"
assert_eq " 1d            "  "$(format_duration 1 0 0 0)" "format_duration days only"
assert_eq " 1d  2h  3m  4s"   "$(format_duration 1 2 3 4)" "format_duration 1d2h3m4s"
assert_eq " 5d            "  "$(format_duration 5 0 0 0)" "format_duration days only nonzero"
assert_eq "100d 23h 59m 59s" "$(format_duration 100 23 59 59)" "format_duration large values"
assert_eq "     2h 30m    "  "$(format_duration 0 2 30 0)" "format_duration zero columns stay blank"

# duration_from_iso8601: past dates clamp to 0 instead of failing (real clock).
assert_eq "0 0 0 0" \
    "$(duration_from_iso8601 "2020-01-01T00:00:00Z")" \
    "duration_from_iso8601 past date clamps to zero"

# duration_from_iso8601: real-clock future date yields 4 non-negative ints
# (the exact value drifts with the wall clock, so only assert the format).
assert_match '^[0-9]+ [0-9]+ [0-9]+ [0-9]+$' \
    "$(duration_from_iso8601 "2099-01-01T00:00:00Z")" \
    "duration_from_iso8601 future date format (real clock)"

# duration_from_iso8601: happy path and human_readable*, with seconds_until_iso
# stubbed to a deterministic clock so the arithmetic is reproducible.
seconds_until_iso_orig=$(declare -f seconds_until_iso)
# shellcheck disable=SC2329  # invoked indirectly through duration_from_iso8601
seconds_until_iso() { printf '%s' "$_stub_secs"; }

_stub_secs=93784  # 1d 2h 3m 4s
assert_eq "1 2 3 4"            "$(duration_from_iso8601 anything)" "duration_from_iso8601 1d2h3m4s"
assert_eq " 1d  2h  3m  4s"   "$(human_readable anything)"          "human_readable 1d2h3m4s"
assert_eq "1d2h"               "$(human_readable_short anything)"   "human_readable_short multi part"

_stub_secs=0
assert_eq "0 0 0 0" "$(duration_from_iso8601 anything)" "duration_from_iso8601 zero"
assert_eq "0s"      "$(human_readable anything)"        "human_readable zero"
assert_eq "0s"      "$(human_readable_short anything)"   "human_readable_short zero (0 parts)"

_stub_secs=60  # 1m
assert_eq "0 0 1 0" "$(duration_from_iso8601 anything)" "duration_from_iso8601 1m"
assert_eq "         1m    "  "$(human_readable anything)"  "human_readable 1m"
assert_eq "1m"       "$(human_readable_short anything)"  "human_readable_short single part"

_stub_secs=3661  # 1h 1m 1s
assert_eq "0 1 1 1" "$(duration_from_iso8601 anything)" "duration_from_iso8601 1h1m1s"

# Restore the real clock before any test that relies on it.
unset -f seconds_until_iso
eval "$seconds_until_iso_orig"

# parse_usage_json: well-formed API response yields three CSV lines,
# with percent coerced to int (75.5 -> 75).
sample_json='{"usage":{"rolling":{"percent":"50","resetsAt":"2026-12-01T00:00:00Z"},"weekly":{"percent":25,"resetsAt":"2026-12-01T00:00:00Z"},"monthly":{"percent":75.5,"resetsAt":"2026-12-01T00:00:00Z"}}}'
expected_csv='rolling,50,2026-12-01T00:00:00Z
weekly,25,2026-12-01T00:00:00Z
monthly,75,2026-12-01T00:00:00Z'
assert_eq "$expected_csv" "$(printf '%s' "$sample_json" | parse_usage_json)" \
    "parse_usage_json well-formed response"

# parse_usage_json: malformed JSON exits non-zero with no stdout.
rc=0
output=$(printf 'garbage' | parse_usage_json 2>/dev/null) || rc=$?
assert_eq "" "$output" "parse_usage_json malformed json no stdout"
assert_nonzero "$rc" "parse_usage_json malformed json exits non-zero"

# format_entry: numbers and --only-* modes.
reset_format_entry_state
numbers_mode=true
assert_eq "rolling 50 12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry numbers full"

reset_format_entry_state
display="short"
numbers_mode=true
assert_eq "50   12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry numbers short"

reset_format_entry_state
one_line=true
numbers_mode=true
assert_eq " 50  12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry numbers one-line"

reset_format_entry_state
one_line=true
assert_eq " 50%  12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry one-line"

reset_format_entry_state
one_line=true
color_mode="color"
numbers_mode=true
assert_eq "${rolling_color_esc} 50  12345${color_reset}" \
    "$(format_entry rolling 50 12345 true)" \
    "format_entry numbers one-line color aligned"

reset_format_entry_state
one_line=true
color_mode="color"
assert_eq "${rolling_color_esc} 50%  12345${color_reset}" \
    "$(format_entry rolling 50 12345 true)" \
    "format_entry one-line color aligned"

# format_entry: numbers mode with a width-8 bar.
reset_format_entry_state
width=8
numbers_mode=true
assert_eq "rolling 50 ████␣␣␣␣ 12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry numbers full with bar"

# format_entry: --only-* modes.
reset_format_entry_state
width=13
only_field="bar"
assert_eq "██████▄␣␣␣␣␣␣" "$(format_entry rolling 50 12345 false)" \
    "format_entry only bar"

reset_format_entry_state
only_field="percent"
assert_eq "50%" "$(format_entry rolling 50 "" false)" \
    "format_entry only percent"

reset_format_entry_state
numbers_mode=true
only_field="percent"
assert_eq "50" "$(format_entry rolling 50 "" false)" \
    "format_entry only percent with numbers"

reset_format_entry_state
one_line=true
color_mode="color"
only_field="percent"
assert_eq "${rolling_color_esc} 50%${color_reset}" \
    "$(format_entry rolling 50 "" true)" \
    "format_entry only percent one-line color aligned"

reset_format_entry_state
only_field="datetime"
assert_eq "12345" "$(format_entry rolling 50 12345 false)" \
    "format_entry only datetime"

reset_format_entry_state
one_line=true
color_mode="color"
only_field="datetime"
assert_eq "${rolling_color_esc} 12345${color_reset}" \
    "$(format_entry rolling 50 12345 true)" \
    "format_entry only datetime one-line color aligned"

# parse_args: --force / -f sets force=true; default is false.
parse_args
# shellcheck disable=SC2154  # force is set by parse_args
assert_eq "false" "$force" "parse_args default force is false"

parse_args --force
assert_eq "true" "$force" "parse_args --force sets force=true"

parse_args -f
assert_eq "true" "$force" "parse_args -f sets force=true"

# parse_args: short-form options (apply_option dispatch) set the right globals.
parse_args -c
assert_eq "color" "$color_mode" "parse_args -c sets color_mode=color"
parse_args -p
assert_eq "plain" "$color_mode" "parse_args -p sets color_mode=plain"

# parse_args: --plain wins over --color regardless of argument order.
parse_args -p -c
assert_eq "plain" "$color_mode" "parse_args -p -c plain wins"
parse_args -c -p
assert_eq "plain" "$color_mode" "parse_args -c -p plain wins"
parse_args --plain --color
assert_eq "plain" "$color_mode" "parse_args --plain --color plain wins"
parse_args --color --plain
assert_eq "plain" "$color_mode" "parse_args --color --plain plain wins"

# Regression: the in-process harness runs with `set +e`, which would hide the
# apply_option &&-chain leak. Re-run the real script under `set -e` so the
# script dies (non-zero) if -c/--color leaks a non-zero status after -p/--plain.
bash -c '
set -euo pipefail
source ./opencode-go-usage.sh
parse_args -p -c
[[ "$color_mode" == "plain" ]]
' 2>/dev/null
rc=$?
assert_eq "0" "$rc" "parse_args -p -c survives set -e (plain wins)"

bash -c '
set -euo pipefail
source ./opencode-go-usage.sh
parse_args --plain --color
[[ "$color_mode" == "plain" ]]
' 2>/dev/null
rc=$?
assert_eq "0" "$rc" "parse_args --plain --color survives set -e (plain wins)"
parse_args -d
assert_eq "true" "$date_mode" "parse_args -d sets date_mode=true"
parse_args -n
assert_eq "true" "$numbers_mode" "parse_args -n sets numbers_mode=true"
parse_args -1
assert_eq "true" "$one_line" "parse_args -1 sets one_line=true"
parse_args -s
assert_eq "short" "$display" "parse_args -s sets display=short"
parse_args -w 5
assert_eq "5" "$width" "parse_args -w 5 sets width=5"
parse_args -dgw 13
assert_eq "true" "$date_mode" "parse_args -dgw 13 sets date_mode=true"
assert_eq "gradient" "$bar_style" "parse_args -dgw 13 sets bar_style=gradient"
assert_eq "13" "$width" "parse_args -dgw 13 sets width=13"
assert_args_fail "parse_args rejects -dgw without value" -dgw
parse_args -v
assert_eq "vertical" "$bar_style" "parse_args -v sets bar_style=vertical"
parse_args -z
assert_eq "horizontal" "$bar_style" "parse_args -z sets bar_style=horizontal"
parse_args -g
assert_eq "gradient" "$bar_style" "parse_args -g sets bar_style=gradient"

# parse_args: bar styles (-v/-z/-g) are mutually exclusive (exits non-zero).
assert_args_fail "main rejects -v -z (styles exclusive)" -v -z
assert_args_fail "main rejects -v -g (styles exclusive)" -v -g
assert_args_fail "main rejects -z -g (styles exclusive)" -z -g

# parse_args: --only-* options can be combined with --short and --one-line.
parse_args --only-bar --short
assert_eq "bar" "$only_field" "parse_args --only-bar --short accepted"
assert_eq "short" "$display" "parse_args --only-bar --short mode"

parse_args --only-bar --one-line
assert_eq "bar" "$only_field" "parse_args --only-bar --one-line accepted"
assert_eq "true" "$one_line" "parse_args --only-bar --one-line one_line"

parse_args --only-percent --short
assert_eq "percent" "$only_field" "parse_args --only-percent --short accepted"

parse_args --only-datetime --one-line
assert_eq "datetime" "$only_field" "parse_args --only-datetime --one-line accepted"

parse_args --only-bar --date
assert_eq "bar" "$only_field" "parse_args --only-bar --date accepted"
assert_eq "true" "$date_mode" "parse_args --only-bar --date date_mode"

# parse_args: --only-* period options.
parse_args --only-rolling
assert_eq "rolling" "$only_period" "parse_args --only-rolling accepted"

parse_args --only-weekly
assert_eq "weekly" "$only_period" "parse_args --only-weekly accepted"

parse_args --only-monthly
assert_eq "monthly" "$only_period" "parse_args --only-monthly accepted"

# parse_args: period options can combine with --only-* output options.
parse_args --only-weekly --only-percent
assert_eq "weekly" "$only_period" "parse_args --only-weekly --only-percent period"
assert_eq "percent" "$only_field" "parse_args --only-weekly --only-percent mode"

# parse_args: --only-* options remain mutually exclusive with each other.
assert_args_fail "parse_args rejects --only-bar --only-percent" --only-bar --only-percent
assert_args_fail "parse_args rejects --only-percent --only-datetime" --only-percent --only-datetime
assert_args_fail "parse_args rejects --only-rolling --only-weekly" --only-rolling --only-weekly
assert_args_fail "parse_args rejects --only-weekly --only-monthly" --only-weekly --only-monthly
assert_args_fail "parse_args rejects removed -r option" -r
assert_args_fail "parse_args rejects removed --percent option" --percent

# validate_width: default-width logic (success cases, in-process).
# Each call resets shared state via parse_args, then validate_width sets width.
parse_args -s
validate_width
assert_eq "0" "$width" "validate_width default width for -s is 0"

parse_args -1
validate_width
assert_eq "0" "$width" "validate_width default width for -1 is 0"

parse_args --only-percent
validate_width
assert_eq "0" "$width" "validate_width default width for --only-percent is 0"

parse_args --only-datetime
validate_width
assert_eq "0" "$width" "validate_width default width for --only-datetime is 0"

parse_args --only-bar
validate_width
assert_eq "8" "$width" "validate_width default width for --only-bar is 8"

parse_args --only-bar --short
validate_width
assert_eq "8" "$width" "validate_width default width for --only-bar --short is 8"

parse_args --only-bar --one-line
validate_width
assert_eq "8" "$width" "validate_width default width for --only-bar --one-line is 8"

parse_args
validate_width
assert_eq "8" "$width" "validate_width default width for no options is 8"

# validate_width: explicit widths within range pass through unchanged.
parse_args -w 0
validate_width
assert_eq "0" "$width" "validate_width -w 0 ok for non-bar"

parse_args -w 5
validate_width
assert_eq "5" "$width" "validate_width -w 5 ok"

parse_args -w 13
validate_width
assert_eq "13" "$width" "validate_width -w 13 ok (upper bound)"

# validate_width returns 0 on the success path (guards the &&-chain leak).
parse_args -w 8
validate_width
rc=$?
assert_eq "0" "$rc" "validate_width returns 0 on success"

# validate_width: failure paths exit non-zero (run as subprocesses because
# exit_fail would otherwise kill the test process).
assert_args_fail "validate_width rejects -w 14 (above range)" -w 14
assert_args_fail "validate_width rejects -w abc (non-numeric)" -w abc
assert_args_fail "validate_width rejects --only-bar -w 0" --only-bar -w 0
assert_args_fail "validate_width rejects -s -1 (short+one-line)" -s -1

# render_output tests: stub save, then reset+override shared state per test.
timestamp_orig=$(declare -f timestamp)
human_readable_short_orig=$(declare -f human_readable_short)
seconds_until_iso_orig=$(declare -f seconds_until_iso)
human_readable_orig=$(declare -f human_readable)
# shellcheck disable=SC2329  # invoked indirectly through render_output
timestamp() { printf '%s' "2026-08-23T12:00:00"; }
# shellcheck disable=SC2329  # invoked indirectly through render_output
human_readable_short() { printf '%s' "FIXED"; }

# render_output: date prefix in one-line mode includes a comma.
reset_render_output_state
one_line=true
date_mode=true
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | render_output)
assert_eq "2026-08-23T12:00:00,  21%  FIXED,  55%  FIXED" "$output" \
    "render_output one-line date prefix uses comma"

# render_output: -d with -n uses epoch seconds for the timestamp prefix.
# shellcheck disable=SC2329  # invoked indirectly through render_output
seconds_until_iso() { printf '%s' "SECS"; }
# shellcheck disable=SC2329  # invoked indirectly through render_output
timestamp() { printf '%s' "1755950400"; }
reset_render_output_state
date_mode=true
numbers_mode=true
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | render_output)
first_line="${output%%$'\n'*}"
assert_eq "1755950400 rolling 21 SECS" "$first_line" \
    "render_output numbers date prefix uses epoch seconds"

# render_output: -d -n -1 uses epoch seconds and a comma separator.
reset_render_output_state
one_line=true
date_mode=true
numbers_mode=true
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\n' \
    | render_output)
assert_eq "1755950400,  21   SECS,  55   SECS" "$output" \
    "render_output numbers one-line date prefix uses epoch seconds and comma"

# render_output: --only-period filters to a single period.
# shellcheck disable=SC2329  # invoked indirectly through render_output
human_readable() { printf '%s' "DURATION"; }
reset_render_output_state
only_period="weekly"
output=$(printf 'rolling,21,2026-08-23T15:00:00Z\nweekly,55,2026-08-23T14:00:00Z\nmonthly,45,2026-08-23T13:00:00Z\n' \
    | render_output)
assert_eq " weekly 55% DURATION" "$output" \
    "render_output --only-weekly filters periods"

# render_output: --only-bar with --short shows the bar at default width (8).
reset_render_output_state
only_field="bar"
display="short"
width="8"
output=$(printf 'rolling,50,2026-08-23T15:00:00Z\nweekly,50,2026-08-23T14:00:00Z\nmonthly,50,2026-08-23T13:00:00Z\n' \
    | render_output)
assert_eq "████␣␣␣␣
████␣␣␣␣
████␣␣␣␣" "$output" \
    "render_output --only-bar --short shows bar at width 8"

# Restore the real functions.
unset -f timestamp human_readable_short seconds_until_iso human_readable
eval "$timestamp_orig"
eval "$human_readable_short_orig"
eval "$seconds_until_iso_orig"
eval "$human_readable_orig"

printf '# passed: %d  failed: %d\n' "$pass" "$fail"
printf '1..%d\n' "$n"
exit "$fail"
