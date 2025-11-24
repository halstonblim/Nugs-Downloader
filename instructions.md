# Nugs Auto Downloader & Tagger

This tool wraps the existing `nugs_dl_fixed` downloader and automatically runs `update_album_tags.sh` **only** for downloads that are detected as "HLS-only" (where tags are unsupported).

## Usage

1.  **Compile the wrapper** (already done if you see `nugs_auto`):
    ```bash
    go build -o nugs_auto nugs_auto.go
    ```

2.  **Run the wrapper** instead of `nugs_dl_fixed`. Pass arguments exactly as you would to the original downloader:
    ```bash
    ./nugs_auto "https://play.nugs.net/release/..."
    ```
    or multiple URLs:
    ```bash
    ./nugs_auto "url1" "url2"
    ```

## How it Works

1.  It reads your `config.json` to find the download output path (`outPath`).
2.  It runs `./nugs_dl_fixed` with your arguments.
3.  It monitors the output in real-time.
4.  If it detects the warning: `HLS-only track. Only AAC is available, tags currently unsupported.`
    - It remembers the folder name for that album.
5.  After the downloader finishes, it automatically runs:
    ```bash
    ./update_album_tags.sh -f "YOUR_OUT_PATH" -n "ALBUM_FOLDER_NAME"
    ```
    for each affected album.
6.  If tags were supported (ALAC/FLAC/etc), the tagger script is **not** run, preserving existing tags.

## Requirements

-   `nugs_dl_fixed` must be in the same directory.
-   `update_album_tags.sh` must be in the same directory.
-   `config.json` must be in the same directory.


