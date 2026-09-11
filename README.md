# `opencode-go-usage.sh`

A single-file shell script that fetches
and displays your [OpenCode Go](https://opencode.ai/go) usage.

Results are cached
(using `path/to/opencode-go-usage-path/.opencode-go-usage-cache`
or in `$TMPDIR`)
for 120 seconds so repeated runs don't hit the API.

Depends on Bash V4.4+, curl, and Python 3
(for JSON and unix-compatible iso-8601 parsing,
eg BSD `/usr/bin/date` can't parse iso-8601)

- **bash** 4.4+ (4.4 fixed empty-array expansion under `set -u`)
- **python3** (for ISO-8601 timestamp parsing and JSON handling)
- **curl**

## Usage

```bash
$ ./opencode-go-usage.sh --help
Usage: opencode-go-usage.sh [options]

Print OpenCode Go usage numbers and reset times.

Options:
  -h, --help
  -c, --color    force colored output (default when a terminal detected)
  -p, --plain    force plain output (no color)
  -d, --date     prefix each output line with a local ISO timestamp
  -f, --force    bypass the cache; always fetch from the API (and refresh the cache)
  -n, --numbers  omit '%' and show seconds remaining instead of duration
  -1, --one-line print all values on one line, comma-separated
  -s, --short    compact output: <percent> <short-date>
Bar styles (-v/-z/-g) are mutually exclusive; -v is the default, ␣ means empty
  -v,   --vertical   vertical bar style
  -z,   --horizontal horizontal bar style
  -g,   --gradient   gradient shade bar style
  -w N, --width=N    0-13 (8 is the default; 0 means no bar is drawn)
        --only-percent/-bar/-datetime
            only show one field: percent remaining / progress bar /  reset time
        --only-rolling/-weekly/-monthly
           only show one period: rolling/weekly/monthly

All styles use an empty cell, ␣.  The gradient bar uses four shades: ␣░▒▓█
The default vertical bar fills bottom-to-top with 8 steps per cell:  ␣▁▂▃▄▅▆▇█
The -z, horizontal bar fills left-to-right with 8 steps per cell:    ␣▏▎▍▌▋▊▉█

  Width  One step   One cell  67% -v/--vertical  67% -z/--horizontal
     13   0.9615%    7.6923%  ████████▅␣␣␣␣      ████████▋␣␣␣␣
     11   1.1364%    9.0909%  ███████▂␣␣␣        ███████▎␣␣␣
      9   1.3889%   11.1111%  ██████␣␣␣          ██████␣␣␣
      7   1.7857%   14.2857%  ████▅␣␣            ████▋␣␣
      5   2.5000%   20.0000%  ███▂␣              ███▎␣
      3   4.1667%   33.3333%  ██␣                ██␣
      1  12.5000%  100.0000%  ▅                  ▋
```

## Screenshot
<img width="1361" height="638" alt="Demonstration of --one-line mode and --vertical showing a poor man's usage over datetimestamp"
 src="https://github.com/user-attachments/assets/9a3ee94a-faf4-4c19-9f28-5a34f05c369f"
/>

## Setup

Copy the example env file: `cp .env.example .env`

Then edit `.env` and replace `your-api-key-here` with your actual key.
The `.env` file is `.gitignore`d which (allegedly)
will prevent its accidental committal.

## Tests

```bash
bash test_opencode-go-usage.sh
```

The test file sources the main script through the entry-point guard.

## API Call

[Unofficial documentation](https://github.com/yumusb/dsh-opencode-go-usage/tree/ee314339abe3a98125d5b685a47ea397ccdbe131#the-usage-api)
for: `https://opencode.ai/zen/go/v1/usage`


Returns:

```json
{
  "usage": {
    "rolling": {
      "status": "ok",
      "percent": 9,
      "resetsAt": "2026-08-24T20:36:08.609Z"
    },
    "weekly": {
      "status": "ok",
      "percent": 12,
      "resetsAt": "2026-08-31T00:00:00.609Z"
    },
    "monthly": {
      "status": "ok",
      "percent": 60,
      "resetsAt": "2026-09-04T03:27:15.609Z"
    }
  }
}
```

Look for `Bearer` in the code to see how to call it.

```bash
$ grep Bearer opencode-go-usage.sh
    response=$(printf 'Authorization: Bearer %s\n' "$OPENCODE_GO_API_KEY" \
```
