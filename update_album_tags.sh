#!/bin/bash

# Script to update album tags in .m4a files based on folder names
# Usage: ./update_album_tags.sh -f <folder_path>

# Parse command line arguments
while getopts "f:" opt; do
  case $opt in
    f)
      BASE_FOLDER="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 -f <folder_path>"
      exit 1
      ;;
  esac
done

# Check if folder was specified
if [ -z "$BASE_FOLDER" ]; then
  echo "Error: No folder specified"
  echo "Usage: $0 -f <folder_path>"
  exit 1
fi

# Check if folder exists
if [ ! -d "$BASE_FOLDER" ]; then
  echo "Error: Folder '$BASE_FOLDER' does not exist"
  exit 1
fi

# Check if AtomicParsley is installed
if ! command -v AtomicParsley &> /dev/null; then
  echo "Error: AtomicParsley is not installed or not in PATH"
  exit 1
fi

# Counter for processed albums
album_count=0

# Loop through each folder in the base folder
while IFS= read -r -d '' album_folder; do
  # Get the folder name without the path
  folder_name=$(basename "$album_folder")
  
  # Extract album name (everything after " - ")
  if [[ "$folder_name" =~ ^.*\ -\ (.*)$ ]]; then
    album_name="${BASH_REMATCH[1]}"
    
    echo "Processing album: $album_name"
    echo "  Folder: $folder_name"
    
    # Count .m4a files in this folder (excluding ._ files)
    m4a_files=$(find "$album_folder" -maxdepth 1 -type f -name "*.m4a" ! -name "._*" | wc -l)
    
    if [ "$m4a_files" -eq 0 ]; then
      echo "  No .m4a files found in this folder"
      echo ""
      continue
    fi
    
    # Process each .m4a file in the folder
    find "$album_folder" -maxdepth 1 -type f -name "*.m4a" ! -name "._*" | while read -r audio_file; do
      echo "    Updating: $(basename "$audio_file")"
      
      # Update the album tag
      AtomicParsley "$audio_file" --album "$album_name" --overWrite &> /dev/null
      
      if [ $? -ne 0 ]; then
        echo "    Error updating file: $(basename "$audio_file")"
      fi
    done
    
    ((album_count++))
    echo "  Updated $m4a_files file(s)"
    echo ""
  else
    echo "Skipping folder (doesn't match naming convention): $folder_name"
    echo ""
  fi
done < <(find "$BASE_FOLDER" -type d -mindepth 1 -maxdepth 1 -print0)

echo "Complete! Processed $album_count album(s)"
