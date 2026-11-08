#!/bin/bash
set -o pipefail

# YouTube transcript extractor with error handling
url="$1"

if [ -z "$url" ]; then
    echo "Usage: $0 <youtube_url>"
    exit 1
fi

# Extract video ID from URL
video_id=$(echo "$url" | sed -n 's/.*[?&]v=\([^&]*\).*/\1/p' | head -c 11)
if [ -z "$video_id" ]; then
    # Try youtu.be format
    video_id=$(echo "$url" | sed -n 's|.*youtu.be/\([^?]*\).*|\1|p' | head -c 11)
fi
if [ -z "$video_id" ]; then
    # Try live URL format
    video_id=$(echo "$url" | sed -n 's|.*live/\([^?]*\).*|\1|p' | head -c 11)
fi

if [ -z "$video_id" ]; then
    echo "Error: Could not extract video ID from URL"
    exit 1
fi

echo "Processing video ID: $video_id"

# Clean up any existing files for this video ID
rm -f *"$video_id"*.srt *"$video_id"*.vtt

# YouTube rate-limits timedtext (HTTP 429) and often requires a real session
# ("Sign in to confirm you’re not a bot").
#
# Defaults that currently work on this machine (2026-10-30):
#   - Safari cookies (--cookies-from-browser safari)
#   - Chrome TLS impersonation (--impersonate chrome)
# VPN alone (e.g. Mullvad) is not enough and can make bot checks worse.
#
# Subtitle format: SRT only. YouTube's auto-caption VTT uses rolling display
# windows that repeat the prior line in every cue, which produced duplicated
# transcripts. The SRT variant is served already collapsed.
#
# Env overrides:
#   YT_SLEEP_SUBTITLES=0|5|10     base sleep before timedtext (default 0)
#   YT_IMPERSONATE=chrome|""      yt-dlp --impersonate target (default chrome)
#   YT_COOKIES_FROM_BROWSER=safari|chrome|brave|""   (default safari; empty skips)
#   YT_COOKIES=/path/to/cookies.txt                  optional Netscape cookie file
#   YT_SUB_LANGS="en-orig en"     language try order
#   YT_RETRY_SLEEPS="5 10"        short retry sleeps after 429/bot-check
SLEEP_SUBS="${YT_SLEEP_SUBTITLES:-0}"
IMPERSONATE="${YT_IMPERSONATE-chrome}"
# Default safari: confirmed working with bot-check + Mullvad on this host.
COOKIES_BROWSER="${YT_COOKIES_FROM_BROWSER-safari}"
COOKIES_FILE="${YT_COOKIES:-}"
SUB_LANG_CANDIDATES="${YT_SUB_LANGS:-en-orig en}"
RETRY_SLEEPS="${YT_RETRY_SLEEPS:-5 10}"
dl_ok=0
last_err=""

has_sub_file_for_lang() {
    local lang="$1"
    find . -maxdepth 1 \( \
        -name "*$video_id*.$lang.srt" -o -name "*$video_id*.$lang.vtt" -o \
        -name "*$video_id*.srt" -o -name "*$video_id*.vtt" \
    \) 2>/dev/null | grep -q .
}

ytdlp_auth_args() {
    # Print auth-related args (cookies + impersonate) for any yt-dlp call.
    if [ -n "$COOKIES_FILE" ] && [ -f "$COOKIES_FILE" ]; then
        printf '%s\0' --cookies "$COOKIES_FILE"
    elif [ -n "$COOKIES_BROWSER" ]; then
        printf '%s\0' --cookies-from-browser "$COOKIES_BROWSER"
    fi
    if [ -n "$IMPERSONATE" ]; then
        printf '%s\0' --impersonate "$IMPERSONATE"
    fi
}

run_ytdlp_subs() {
    local lang="$1" sleep_s="$2"
    local -a cmd
<<<<<<< HEAD:YT/yt_transcriptv4.sh
    # Convert to SRT: YouTube's auto VTT uses rolling captions that repeat each
    # line 2-3x. yt-dlp's SRT conversion collapses them into clean single cues.
    cmd=(yt-dlp --write-subs --write-auto-subs --skip-download
         --sub-langs "$lang"
         --sub-format "srt/vtt/best"
=======
    # SRT is required, not cosmetic: YouTube serves SRT already collapsed,
    # while auto-caption VTT uses rolling windows that repeat the previous
    # line in every cue. --convert-subs is a safety net if only VTT exists.
    cmd=(yt-dlp --write-subs --write-auto-subs --skip-download
         --sub-langs "$lang"
         --sub-format "srt/best"
>>>>>>> 40794ae (update yt readme):YT/yt_transcriptv3.sh
         --convert-subs srt
         --retries 2
         --retry-sleep 2
         --sleep-requests 0.5)
    # Append cookies / impersonate
    local arg
    while IFS= read -r -d '' arg; do
        cmd+=("$arg")
    done < <(ytdlp_auth_args)
    if [ "${sleep_s:-0}" -gt 0 ] 2>/dev/null; then
        cmd+=(--sleep-subtitles "$sleep_s")
    fi
    cmd+=("$url")
    echo "  cmd: ${cmd[*]}"
    "${cmd[@]}"
}

for lang in $SUB_LANG_CANDIDATES; do
    sleep_plan="$SLEEP_SUBS $RETRY_SLEEPS"
    attempt=0
    for sleep_s in $sleep_plan; do
        attempt=$((attempt + 1))
        auth_desc="impersonate=${IMPERSONATE:-none}"
        if [ -n "$COOKIES_FILE" ] && [ -f "$COOKIES_FILE" ]; then
            auth_desc="$auth_desc, cookies-file"
        elif [ -n "$COOKIES_BROWSER" ]; then
            auth_desc="$auth_desc, cookies-from-browser=$COOKIES_BROWSER"
        else
            auth_desc="$auth_desc, no-cookies"
        fi
        if [ "$sleep_s" -gt 0 ] 2>/dev/null; then
            echo "Trying lang='$lang' attempt $attempt ($auth_desc, sleep ${sleep_s}s)..."
        else
            echo "Trying lang='$lang' attempt $attempt ($auth_desc, no sleep)..."
        fi

        err_log=$(mktemp)
        if run_ytdlp_subs "$lang" "$sleep_s" 2>&1 | tee "$err_log"; then
            if has_sub_file_for_lang "$lang"; then
                rm -f "$err_log"
                dl_ok=1
                break 2
            fi
        fi

        last_err=$(cat "$err_log")
        if grep -qiE 'HTTP Error 429|Too Many Requests|Sign in to confirm you' "$err_log"; then
            rm -f "$err_log"
            echo "Blocked/rate-limited; escalating short sleep if available..."
            continue
        fi

        rm -f "$err_log"
        # Non-retryable for this lang: try next language
        break
    done

    [ "$dl_ok" -eq 1 ] && break
done

if [ "$dl_ok" -ne 1 ]; then
    echo "Error: Failed to download subtitles after trying: $SUB_LANG_CANDIDATES"
    if printf '%s' "$last_err" | grep -qiE 'HTTP Error 429|Too Many Requests'; then
        echo "YouTube is still rate-limiting timedtext downloads."
    elif printf '%s' "$last_err" | grep -qiE 'Sign in to confirm you'; then
        echo "YouTube still wants bot verification even with cookies/impersonate."
        echo "Try: open youtube.com in Safari while logged in, or export fresh cookies."
        echo "  YT_COOKIES_FROM_BROWSER=chrome $0 URL"
        echo "  YT_COOKIES=~/cookies.txt $0 URL"
    else
        echo "The video may not have subtitles available or may be restricted."
    fi
    if [ -z "$COOKIES_BROWSER" ] && [ -z "$COOKIES_FILE" ]; then
        echo "Hint: re-enable cookies, e.g. YT_COOKIES_FROM_BROWSER=safari"
    fi
    exit 1
fi

# SRT first (de-duplicated by YouTube), VTT only as a last resort.
# Within each format: original-language auto caps, then plain en, then any.
subtitle_file=$({
    find . -maxdepth 1 -name "*$video_id*.en-orig.srt"
    find . -maxdepth 1 -name "*$video_id*.en.srt"
    find . -maxdepth 1 -name "*$video_id*.srt"
    find . -maxdepth 1 -name "*$video_id*.en-orig.vtt"
    find . -maxdepth 1 -name "*$video_id*.en.vtt"
    find . -maxdepth 1 -name "*$video_id*.vtt"
} 2>/dev/null | awk 'NF && !seen[$0]++' | head -1)

if [ -z "$subtitle_file" ]; then
    echo "Error: No subtitle files found for video ID $video_id. The video may not have subtitles available."
    exit 1
fi

echo "Found subtitle file: $subtitle_file"
case "$subtitle_file" in
    *.vtt)
        echo "Warning: fell back to VTT. Auto-caption VTT repeats each line" >&2
        echo "         (rolling captions), so expect duplicated text." >&2
        ;;
esac

# Clean the transcript: one line per cue -> "START_TIME TEXT"
# Supports both SRT and VTT by scanning blocks separated by blank lines
awk 'BEGIN{RS=""; FS="\n"}
{
  start=""; text="";
  for(i=1;i<=NF;i++){
    line=$i;
    # Skip headers and pure cue indices
    if(line ~ /^(WEBVTT|Kind:|Language:|NOTE)/) continue;
    if(line ~ /^[[:space:]]*[0-9]+[[:space:]]*$/) continue;

    # Capture start time from timecode line (SRT or VTT)
    if(line ~ /-->/){
      if (match(line, /[0-9]{2}:[0-9]{2}:[0-9]{2}[,.][0-9]{3}/)){
        start=substr(line, RSTART, RLENGTH);
        gsub(",",".",start);
      }
      continue;
    }

    # Accumulate cue text lines, stripping simple tags like <c> and any <...>
    gsub(/<[^>]*>/, "", line);
    if(length(line) == 0) continue;
    if(text == "") text=line; else text=text " " line;
  }
  if(start != "" && text != ""){
    print start " " text;
  }
}' "$subtitle_file" > clean_transcript.txt

echo "Clean transcript saved to clean_transcript.txt"

# Derive a hyphenated title and finalize file naming, then prepend metadata
# Reuse same auth so title fetch does not trip bot check.
title_cmd=(yt-dlp --skip-download --get-title --sleep-requests 0.5)
while IFS= read -r -d '' arg; do
    title_cmd+=("$arg")
done < <(ytdlp_auth_args)
title_cmd+=("$url")
title=$("${title_cmd[@]}" 2>/dev/null | head -n 1)
if [ -z "$title" ]; then
    title="$video_id"
fi

# Build a safe hyphenated slug
slug=$(printf '%s' "$title" | sed -E 's/[[:space:]]+/-/g; s/[^A-Za-z0-9._-]+//g; s/-{2,}/-/g; s/^-+|-+$//g')
if [ -z "$slug" ]; then
    slug="$video_id"
fi

dest="${slug}.txt"
if [ -e "$dest" ]; then
    n=1
    while [ -e "${slug}-${n}.txt" ]; do
        n=$((n+1))
    done
    dest="${slug}-${n}.txt"
fi

tmpfile=$(mktemp)
{
    printf 'URL: %s\n' "$url"
    printf 'Title: %s\n' "$slug"
    cat clean_transcript.txt
} > "$tmpfile"

mv "$tmpfile" "$dest"
rm -f clean_transcript.txt "$subtitle_file"
echo "Final transcript saved to $dest"
