# YouTube Transcript Extractor

`yt_transcriptv3.sh` downloads a YouTube video's captions with `yt-dlp` and emits a
flat, timestamped plain-text transcript.

No video is downloaded — captions only.

## Prerequisites

- **yt-dlp** — `brew install yt-dlp`
- **curl_cffi** — required for the browser-impersonation fast path. The Homebrew
  `yt-dlp` formula already bundles it. Verify with:

  ```bash
  yt-dlp --list-impersonate-targets
  ```

  If that prints nothing, impersonation is unavailable; see
  [Rate limiting](#rate-limiting-http-429) below.

## Usage

```bash
./yt_transcriptv3.sh "https://youtu.be/VIDEO_ID"
```

Accepted URL forms: `watch?v=`, `youtu.be/`, and `/live/`.

Output is written to the **current working directory**, so `cd` to wherever you
want the transcript to land.

Typical run is a few seconds.

## Output

Two files are left in the working directory:

| File | Description |
| --- | --- |
| `<Video-Title-Slug>.txt` | The final transcript |
| `<Video Title> [<id>].<lang>.srt` | The raw caption file (not auto-removed) |

The transcript carries a two-line header, then one line per caption cue:

```
URL: https://youtu.be/bmqPLYht22g
Title: How-Trump-Plans-to-Steal-the-Midterm-Elections
00:00:05.359 Thank you. Thank you, Scott.
00:00:11.920 The Trump White House is attempting to
00:00:15.280 put into place a series of mechanisms
00:00:18.560 to fix or invalidate the midterm
00:00:20.960 elections.
```

If `<Slug>.txt` already exists, the script appends `-1`, `-2`, … rather than
overwriting.

## Configuration

All configuration is via environment variables.

| Variable | Default | Purpose |
| --- | --- | --- |
| `YT_SLEEP_SUBTITLES` | `0` | Seconds to wait before the caption fetch |
| `YT_IMPERSONATE` | `chrome` | `yt-dlp --impersonate` target; set empty to disable |
| `YT_SUB_LANGS` | `en-orig en` | Language try order, space-separated |
| `YT_RETRY_SLEEPS` | `5 10` | Escalating sleeps used only after a 429 |

Examples:

```bash
# Start with a 5s delay instead of 0
YT_SLEEP_SUBTITLES=5 ./yt_transcriptv3.sh "URL"

# Disable TLS impersonation
YT_IMPERSONATE= ./yt_transcriptv3.sh "URL"

# Spanish, falling back to English
YT_SUB_LANGS="es en" ./yt_transcriptv3.sh "URL"
```

## How it works

1. Parse the video ID out of the URL.
2. Remove any stale `.srt` / `.vtt` for that ID in the working directory.
3. For each language in `YT_SUB_LANGS`, attempt the caption download — first with
   no delay, then retrying with the `YT_RETRY_SLEEPS` values **only** if YouTube
   returns HTTP 429.
4. Select the best caption file, preferring SRT over VTT.
5. Flatten cues to `START_TIME TEXT`, stripping VTT inline tags such as `<c>`.
6. Prepend the URL/title header and write the final `.txt`.

### Why SRT and not VTT

This matters — it is not a cosmetic preference.

YouTube's auto-caption **VTT** uses rolling display windows, so captions appear to
scroll on screen. Every cue repeats the previous line:

```
00:00:15.270  The Trump White House is attempting to
00:00:15.280  The Trump White House is attempting to put into place a series of mechanisms
00:00:18.550  put into place a series of mechanisms
00:00:18.560  put into place a series of mechanisms to fix or invalidate the midterm
```

Flattening that yields a transcript where nearly every line appears two or three
times. The **SRT** variant is served already collapsed — one cue, one line.

For the same video: 44 KB SRT vs 198 KB VTT, 653 output lines vs 1303.

Converting VTT to SRT after the fact does **not** help; `--convert-subs` preserves
the repeats. The format must be requested as SRT up front, which is what the
script does via `--sub-format "srt/best"`.

If SRT is genuinely unavailable, the script falls back to VTT, still produces a
transcript, and prints a warning to stderr that the text will contain duplicates.

> **Note on repeated phrasing:** not every repeat is a bug. Lines that recur in
> clean SRT output — a speaker saying "will not save us" three times — are
> genuine speech, not rolling-caption artifacts.

## Rate limiting (HTTP 429)

YouTube applies strict rate limits to its `timedtext` caption endpoint. The
failure looks like:

```
ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests
```

The script's primary defense is **browser TLS impersonation**
(`--impersonate chrome`), which in practice avoids the limit with no delay at all.
If a 429 still occurs it retries with short sleeps (5s, then 10s).

Further options if you are persistently limited:

```bash
# Longer initial delay
YT_SLEEP_SUBTITLES=30 ./yt_transcriptv3.sh "URL"

# Cookies from a logged-in browser session
yt-dlp --cookies-from-browser chrome --impersonate chrome \
  --write-auto-subs --skip-download --sub-langs en-orig "URL"
```

Otherwise, wait a few minutes — the limit is per-IP and time-based.

Background: [yt-dlp#13831](https://github.com/yt-dlp/yt-dlp/issues/13831).

See also `optimize-vpn-bypass.md` in this directory for VPN/cookie notes.

## Troubleshooting

**`Could not extract video ID from URL`**
The URL form isn't recognized. Use a `watch?v=`, `youtu.be/`, or `/live/` link.

**`No subtitle files found` / `may not have subtitles available`**
The video has no captions in the requested languages. Check what exists:

```bash
yt-dlp --list-subs "URL"
```

Then set `YT_SUB_LANGS` accordingly.

**Transcript contains duplicated lines**
The script fell back to VTT (a stderr warning is printed when this happens). See
[Why SRT and not VTT](#why-srt-and-not-vtt).

**`yt-dlp: command not found`**
Install it: `brew install yt-dlp`.

## Related one-liner

Quick ad-hoc extraction without the script:

```bash
yt-dlp --write-auto-subs --skip-download --sub-format srt --sub-langs en-orig \
  --impersonate chrome "URL"
```
