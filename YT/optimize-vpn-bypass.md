# keep vpn

- Pass real browser cookies so the request looks like your logged‑in session:
  - Safari (macOS): add `--cookies-from-browser safari`
  - Chrome: `--cookies-from-browser chrome:profile=Default`

The simplest change is to let you pass yt-dlp flags via an env var and (optionally) toggle some safe defaults:

- Add env‑driven flags:
  - YTDLP_OPTS: appended verbatim to the yt-dlp command (e.g., `--cookies-from-browser safari --force-ipv4`)
  - Optional gentle throttling to look less bot‑like: `--sleep-requests 1 --max-sleep-interval 3`
  - Optional IPv4: `--force-ipv4`
  - Optional client override if it helps in your region: `--extractor-args "youtube:player_client=ios"` or `"android"`

How you’d use it (no code changes required if we add YTDLP_OPTS pass‑through):
- One-off run with Safari cookies and IPv4:
  - export YTDLP_OPTS='--cookies-from-browser safari --force-ipv4 --sleep-requests 1 --max-sleep-interval 3'
  - ./yt_transcriptv3.sh 'https://youtu.be/...'
- Chrome profile:
  - export YTDLP_OPTS='--cookies-from-browser chrome:profile=Default --force-ipv4 --sleep-requests 1 --max-sleep-interval 3'
  - ./yt_transcriptv3.sh 'https://youtu.be/...'
- Try a different YouTube client if needed:
  - export YTDLP_OPTS='--extractor-args youtube:player_client=ios --cookies-from-browser safari --force-ipv4'

Optional if you want to try yt-dlp’s impersonation transport (can help with stricter checks):
- Upgrade yt-dlp and install the extra dependency, then run with an impersonated UA (only if needed):
  - brew upgrade yt-dlp
  - python3 -m pip install --upgrade curl_cffi
  - export YTDLP_OPTS='--impersonate safari15_5 --cookies-from-browser safari --force-ipv4'
  - Note: impersonation support and targets vary by yt-dlp version.

If you want me to implement the minimal script change, I’ll:
- Add `YTDLP_OPTS` passthrough to the yt-dlp call.
- Optionally add a commented example line showing common values (Safari/Chrome cookies + IPv4 + gentle sleep).

Say “ACT” to wire this into `YT/yt_transcriptv3.sh`.