#!/bin/zsh
###############################################################################
# compress_acrobat_pdfs_sm.zsh
#
# Batch-compress selected PDFs with Adobe Acrobat on macOS.
#
# Default scope:
#   - PDF filenames containing "System Card"
#   - PDF filenames containing "Emotion Concepts and their Function in a Large
#     Language Model"
#   - skips existing *_sm.pdf files
#   - skips files smaller than --min-mib, default 10 MiB
#
# Output:
#   <input-dir>/<input-dir-name>_pdfs_sm/<pdf-filename>_sm.pdf
#
# Requirements:
#   - Adobe Acrobat Pro installed
#   - Accessibility permission for the terminal app running this script
#
###############################################################################

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

SCRIPT_NAME="${0:t}"
MIN_MIB=10
DRY_RUN=0
FORCE=0
ALL_LARGE=0
ACROBAT_APP="${ACROBAT_APP:-Adobe Acrobat}"

usage() {
    cat <<USAGE
Usage:
  ${SCRIPT_NAME} [options] <pdf-directory>

Options:
  --dry-run          List matching PDFs and exit without opening Acrobat.
  --min-mib N        Only process PDFs >= N MiB. Default: ${MIN_MIB}.
                     Use --min-mib 0 to disable the size filter.
  --all-large        Ignore the default Anthropic/system-card/emotion-paper
                     filename scope and process every PDF over --min-mib.
  --force            Allow overwriting existing *_sm.pdf outputs.
  --acrobat NAME     App name for Acrobat. Default: "${ACROBAT_APP}".
  -h, --help         Show this help.

Examples:
  ${SCRIPT_NAME} --dry-run "01_sources/a_text/04_research/AI/data"
  ${SCRIPT_NAME} --min-mib 10 "01_sources/a_text/04_research/AI/data"
  ${SCRIPT_NAME} --min-mib 100 "01_sources/a_text/04_research/AI/academic_papers/ant"

Notes:
  This uses macOS UI scripting to choose Acrobat's default Reduced Size PDF /
  Compress PDF flow. Keep Acrobat in the foreground while it runs.
USAGE
}

die() {
    print -ru2 -- "error: $*"
    exit 1
}

human_size() {
    local bytes="$1"
    /usr/bin/awk -v b="$bytes" 'BEGIN {
        split("B KiB MiB GiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 4) { b /= 1024; i++ }
        printf "%.2f %s", b, u[i];
    }'
}

should_include_pdf() {
    local pdf_file="$1"
    local base="${pdf_file:t}"
    local lower

    lower="$(printf '%s' "$base" | /usr/bin/tr '[:upper:]' '[:lower:]')"

    [[ "$lower" == *_sm.pdf ]] && return 1

    if (( ALL_LARGE )); then
        return 0
    fi

    [[ "$lower" == *"system card"* ]] && return 0
    [[ "$lower" == *"emotion concepts and their function in a large language model"* ]] && return 0

    return 1
}

clickable_size_threshold() {
    local mib="$1"
    [[ "$mib" == <-> ]] || die "--min-mib must be a non-negative integer"
    print -- $(( mib * 1024 * 1024 ))
}

input_dir=""

while (( $# > 0 )); do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --force)
            FORCE=1
            ;;
        --all-large)
            ALL_LARGE=1
            ;;
        --min-mib)
            shift
            (( $# > 0 )) || die "--min-mib requires a value"
            MIN_MIB="$1"
            ;;
        --acrobat)
            shift
            (( $# > 0 )) || die "--acrobat requires an application name"
            ACROBAT_APP="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            [[ -z "$input_dir" ]] || die "only one PDF directory may be provided"
            input_dir="$1"
            ;;
    esac
    shift
done

[[ -n "$input_dir" ]] || {
    usage
    exit 2
}

src_dir="${input_dir:A}"
[[ -d "$src_dir" ]] || die "not a directory: $input_dir"

threshold_bytes="$(clickable_size_threshold "$MIN_MIB")"
dir_name="${src_dir:t}"
out_dir="${src_dir}/${dir_name}_pdfs_sm"

typeset -a selected_files
selected_files=()

while IFS= read -r -d '' pdf_file; do
    should_include_pdf "$pdf_file" || continue

    size_bytes="$(/usr/bin/stat -f '%z' "$pdf_file")"
    if (( threshold_bytes > 0 && size_bytes < threshold_bytes )); then
        continue
    fi

    selected_files+=("$pdf_file")
done < <(/usr/bin/find "$src_dir" -maxdepth 1 -type f -iname '*.pdf' -print0)

if (( ${#selected_files[@]} == 0 )); then
    print -- "No matching PDFs found in: $src_dir"
    print -- "Scope: $([[ $ALL_LARGE -eq 1 ]] && print 'all PDFs' || print 'System Card PDFs + AI emotion paper')"
    print -- "Minimum size: ${MIN_MIB} MiB"
    exit 0
fi

print -- "Input directory:  $src_dir"
print -- "Output directory: $out_dir"
print -- "Minimum size:    ${MIN_MIB} MiB"
print -- "Acrobat app:     $ACROBAT_APP"
print -- ""
print -- "Selected PDFs:"

for pdf_file in "${selected_files[@]}"; do
    size_bytes="$(/usr/bin/stat -f '%z' "$pdf_file")"
    print -- "  - ${pdf_file:t} ($(human_size "$size_bytes"))"
done

if (( DRY_RUN )); then
    print -- ""
    print -- "Dry run complete; Acrobat was not opened."
    exit 0
fi

/usr/bin/open -Ra "$ACROBAT_APP" >/dev/null 2>&1 || die "Adobe Acrobat was not found as \"$ACROBAT_APP\". Install Acrobat Pro or pass --acrobat with the exact app name."

ui_enabled="$(/usr/bin/osascript -e 'tell application "System Events" to UI elements enabled')"
[[ "$ui_enabled" == "true" ]] || die "Enable Accessibility permission for Warp/Terminal in System Settings > Privacy & Security > Accessibility, then rerun."

/bin/mkdir -p "$out_dir"

compress_one_pdf() {
    local pdf_file="$1"
    local base="${pdf_file:t}"
    local stem="${base:r}"
    local dest_file="${out_dir}/${stem}_sm.pdf"

    if [[ -e "$dest_file" && "$FORCE" -ne 1 ]]; then
        print -- "Skipping existing output: ${dest_file:t} (use --force to overwrite)"
        return 0
    fi

    print -- ""
    print -- "Compressing: $base"
    print -- "Output:      ${dest_file:t}"

    /usr/bin/osascript - "$pdf_file" "$dest_file" "$out_dir" "${dest_file:t}" "$ACROBAT_APP" <<'APPLESCRIPT'
on run argv
    set sourcePath to item 1 of argv
    set destPath to item 2 of argv
    set destDir to item 3 of argv
    set destName to item 4 of argv
    set acrobatName to item 5 of argv

    tell application acrobatName
        activate
        open POSIX file sourcePath
    end tell

    delay 2
    my chooseReducedSizeMenu(acrobatName)
    my clickDefaultOKIfPresent(acrobatName)
    my saveDialogTo(acrobatName, destDir, destName)

    delay 1
    tell application acrobatName
        activate
        try
            close active doc saving no
        end try
    end tell
end run

on chooseReducedSizeMenu(acrobatName)
    set menuPaths to {¬
        {"File", "Save as Other", "Reduced Size PDF..."}, ¬
        {"File", "Save As Other", "Reduced Size PDF..."}, ¬
        {"File", "Save as Other", "Reduced Size PDF…"}, ¬
        {"File", "Save As Other", "Reduced Size PDF…"}, ¬
        {"File", "Compress PDF"}}

    repeat with menuPath in menuPaths
        try
            my clickMenuPath(acrobatName, menuPath)
            delay 1
            return
        end try
    end repeat

    error "Could not find Acrobat's Reduced Size PDF / Compress PDF menu item."
end chooseReducedSizeMenu

on clickMenuPath(acrobatName, menuPath)
    tell application "System Events"
        tell process acrobatName
            set frontmost to true
            set topMenuName to item 1 of menuPath
            click menu bar item topMenuName of menu bar 1
            delay 0.2
            set currentMenu to menu 1 of menu bar item topMenuName of menu bar 1

            repeat with i from 2 to count of menuPath
                set menuName to item i of menuPath
                if i = count of menuPath then
                    click menu item menuName of currentMenu
                else
                    set currentMenu to menu 1 of menu item menuName of currentMenu
                end if
                delay 0.2
            end repeat
        end tell
    end tell
end clickMenuPath

on clickDefaultOKIfPresent(acrobatName)
    tell application "System Events"
        tell process acrobatName
            set frontmost to true
            repeat 80 times
                try
                    if exists button "OK" of window 1 then
                        click button "OK" of window 1
                        delay 1
                        return
                    end if
                end try

                try
                    if exists button "Save" of window 1 then
                        return
                    end if
                end try

                delay 0.25
            end repeat
        end tell
    end tell
end clickDefaultOKIfPresent

on saveDialogTo(acrobatName, destDir, destName)
    tell application "System Events"
        tell process acrobatName
            set frontmost to true

            repeat 120 times
                if my hasSaveButton(acrobatName) then exit repeat
                delay 0.25
            end repeat

            if not my hasSaveButton(acrobatName) then
                error "Save dialog did not appear."
            end if

            keystroke "g" using {command down, shift down}
            delay 0.5
            keystroke destDir
            key code 36
            delay 0.8

            keystroke "a" using {command down}
            delay 0.1
            keystroke destName
            delay 0.2

            my clickSaveButton(acrobatName)
            delay 0.8
            my clickReplaceIfPresent(acrobatName)
        end tell
    end tell
end saveDialogTo

on hasSaveButton(acrobatName)
    tell application "System Events"
        tell process acrobatName
            try
                if exists button "Save" of sheet 1 of window 1 then return true
            end try
            try
                if exists button "Save" of window 1 then return true
            end try
        end tell
    end tell
    return false
end hasSaveButton

on clickSaveButton(acrobatName)
    tell application "System Events"
        tell process acrobatName
            try
                click button "Save" of sheet 1 of window 1
                return
            end try
            try
                click button "Save" of window 1
                return
            end try
        end tell
    end tell
    error "Could not click Save."
end clickSaveButton

on clickReplaceIfPresent(acrobatName)
    tell application "System Events"
        tell process acrobatName
            repeat 20 times
                try
                    if exists button "Replace" of sheet 1 of window 1 then
                        click button "Replace" of sheet 1 of window 1
                        return
                    end if
                end try
                try
                    if exists button "Replace" of window 1 then
                        click button "Replace" of window 1
                        return
                    end if
                end try
                delay 0.25
            end repeat
        end tell
    end tell
end clickReplaceIfPresent
APPLESCRIPT

    if [[ ! -f "$dest_file" ]]; then
        die "Acrobat did not create expected output: $dest_file"
    fi

    local old_size
    local new_size
    old_size="$(/usr/bin/stat -f '%z' "$pdf_file")"
    new_size="$(/usr/bin/stat -f '%z' "$dest_file")"

    print -- "Done: ${base} ($(human_size "$old_size") -> $(human_size "$new_size"))"
}

for pdf_file in "${selected_files[@]}"; do
    compress_one_pdf "$pdf_file"
done

print -- ""
print -- "Compressed PDFs written to: $out_dir"
