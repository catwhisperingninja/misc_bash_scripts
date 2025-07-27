# YouTube Transcript Extractor

A simple bash script to extract auto-generated transcripts from YouTube videos using `yt-dlp`.

## Overview

This standalone script downloads auto-generated subtitles from YouTube videos and outputs them in VTT (WebVTT) format. It was created as a lightweight alternative for extracting YouTube transcripts without requiring complex frameworks.

*Note: The script references the [fabric repo](https://github.com/danielmiessler/fabric) as inspiration, but this is a standalone tool that doesn't require fabric.ai installation.*

## Prerequisites

### Required
- **yt-dlp**: A YouTube downloader tool
- **bash**: Standard on macOS and Linux systems

### Installation

#### macOS (using Homebrew)
```bash
brew install yt-dlp
```

#### macOS (using pip)
```bash
pip3 install yt-dlp
```

#### Linux (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install yt-dlp
```

#### Linux (using pip)
```bash
pip3 install yt-dlp
```

## Usage

### Basic Usage

1. **Edit the script** to set your target YouTube video:
   ```bash
   VideoURL="https://www.youtube.com/watch?v=YOUR_VIDEO_ID"
   ```

2. **Run the script**:
   ```bash
   chmod +x yt_transcript.sh
   ./yt_transcript.sh
   ```

3. **View the transcript** output directly in your terminal

### Configuration

The script has two main configuration variables at the top:

```bash
VideoURL="https://www.youtube.com/watch?v=FtnGiI9MGgA"  # Change this to your target video
LANG="en"                                               # Language code for subtitles
```

#### Supported Languages
Common language codes include:
- `en` - English
- `es` - Spanish  
- `fr` - French
- `de` - German
- `it` - Italian
- `pt` - Portuguese
- `ru` - Russian
- `ja` - Japanese
- `ko` - Korean
- `zh` - Chinese

*Note: Not all videos have subtitles in all languages. The script will fail if the requested language isn't available.*

## Output Format

The script outputs transcripts in **VTT (WebVTT)** format, which includes:
- Timestamp markers
- Subtitle text
- Formatting information

### Example Output
```
WEBVTT
Kind: captions
Language: en

00:00:01.200 --> 00:00:04.800
Welcome to this tutorial on YouTube transcripts

00:00:05.000 --> 00:00:08.500
Today we'll learn how to extract subtitles automatically
```

## How It Works

1. **Creates temporary file**: Uses `mktemp` to create a secure temporary file
2. **Downloads subtitles**: Uses `yt-dlp` to extract auto-generated subtitles without downloading the video
3. **Outputs content**: Displays the VTT transcript content to stdout
4. **Cleanup**: Comments show optional secure deletion of temporary files

## Troubleshooting

### Common Issues

**"No video found"**
- Verify the YouTube URL is correct and accessible
- Check if the video is public (private videos won't work)

**"No subtitles available"**
- Not all videos have auto-generated subtitles
- Try changing the language code (`LANG` variable)
- Some videos only have manually-added subtitles in specific languages

**"yt-dlp command not found"**
- Install yt-dlp using the installation instructions above
- Verify installation: `yt-dlp --version`

**Permission denied**
- Make the script executable: `chmod +x yt_transcript.sh`

### Advanced Usage

**Save transcript to file:**
```bash
./yt_transcript.sh > transcript.vtt
```

**Extract multiple languages:**
```bash
# Modify the script or create copies with different LANG values
LANG="en" ./yt_transcript.sh > transcript_en.vtt
LANG="es" ./yt_transcript.sh > transcript_es.vtt
```

**Check available subtitle languages:**
```bash
yt-dlp --list-subs "https://www.youtube.com/watch?v=VIDEO_ID"
```

## Security Notes

- The script uses temporary files that are automatically cleaned up by the system
- The commented `srm` command can be uncommented for secure file deletion on systems that have it installed
- Always verify YouTube URLs before running to avoid downloading unintended content

## Examples

### Extract transcript from a specific video
```bash
# Edit the VideoURL in the script
VideoURL="https://www.youtube.com/watch?v=dQw4w9WgXcQ"
LANG="en"

# Run the script
./yt_transcript.sh
```

### Batch processing multiple videos
Create multiple script copies or modify the script to accept URL as parameter:

```bash
#!/bin/bash
VideoURL="$1"  # First command line argument
LANG="${2:-en}"  # Second argument or default to 'en'
# ... rest of script
```

Then use:
```bash
./yt_transcript.sh "https://www.youtube.com/watch?v=VIDEO1" "en"
./yt_transcript.sh "https://www.youtube.com/watch?v=VIDEO2" "es"
```

## Contributing

This is a simple utility script. Feel free to modify it for your specific needs:
- Add error handling
- Support for different output formats
- Batch processing capabilities
- Integration with other tools

## License

This script is provided as-is for educational and personal use.
