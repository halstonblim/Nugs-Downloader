#!/usr/bin/env bash

# Script to update album tags in .m4a files based on folder names
# Usage: ./update_album_tags.sh -f <folder_path> [-n <specific_folder_name>] [-j <parallel_jobs>]

# Parse command line arguments
SPECIFIC_FOLDER=""
MAX_PARALLEL_JOBS=8  # Adjust based on your CPU cores
while getopts "f:n:j:" opt; do
  case $opt in
    f)
      BASE_FOLDER="$OPTARG"
      ;;
    n)
      SPECIFIC_FOLDER="$OPTARG"
      ;;
    j)
      MAX_PARALLEL_JOBS="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 -f <folder_path> [-n <specific_folder_name>] [-j <parallel_jobs>]"
      exit 1
      ;;
  esac
done

# Check if folder was specified
if [ -z "$BASE_FOLDER" ]; then
  echo "Error: No folder specified"
  echo "Usage: $0 -f <folder_path> [-n <specific_folder_name>] [-j <parallel_jobs>]"
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

# Determine which folders to process
if [ -n "$SPECIFIC_FOLDER" ]; then
  # Process only the specific folder
  SEARCH_PATH="$BASE_FOLDER/$SPECIFIC_FOLDER"
  if [ ! -d "$SEARCH_PATH" ]; then
    echo "Error: Specific folder '$SPECIFIC_FOLDER' not found in '$BASE_FOLDER'"
    exit 1
  fi
  echo "Processing specific folder: $SPECIFIC_FOLDER"
  echo ""
fi

# Loop through each folder in the base folder
while IFS= read -r -d '' album_folder; do
  # Get the folder name without the path
  folder_name=$(basename "$album_folder")
  
  # Extract artist name (everything before first " - ")
  # Pattern: [Artist] - [Album Info]
  if [[ "$folder_name" =~ ^([^-]+)\ -\ (.*)$ ]]; then
    artist_name="${BASH_REMATCH[1]}"
    album_part="${BASH_REMATCH[2]}"
    
    # Check if there's a trailing " - [Location]" pattern (ends with ", XX" for state/country)
    if [[ "$album_part" =~ ^(.*)\ -\ [^-]+,\ [A-Z]{2}$ ]]; then
      # Remove the " - Location" suffix
      album_name="${BASH_REMATCH[1]}"
    else
      # No location suffix, use the whole album part
      album_name="$album_part"
    fi
    
    # Transform album name: replace underscores with slashes in date pattern (XX_XX_XX)
    if [[ "$album_name" =~ ^([0-9]{2})_([0-9]{2})_([0-9]{2})(.*)$ ]]; then
      # Replace underscores with slashes in the date part
      album_name="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
    fi
    
    # Transform album name: replace underscore after volume number with colon
    # Matches patterns like "Vol. 2_" or "Vol.  2_" and replaces with "Vol. 2:" or "Vol.  2:"
    if [[ "$album_name" =~ (.*)(Vol\.[[:space:]]+[0-9]+)_(.*)$ ]]; then
      album_name="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
    fi
    
    # Transform album name: replace "Road Trips_" with "Road Trips:"
    album_name="${album_name//Road Trips_/Road Trips:}"
    
    # Collapse multiple consecutive spaces into a single space
    while [[ "$album_name" =~ "  " ]]; do
      album_name="${album_name//  / }"
    done
    
    echo "Processing album: $album_name"
    echo "  Artist: $artist_name"
    echo "  Folder: $folder_name"
    
    # Collect all .m4a files into an array (single find pass)
    mapfile -d '' m4a_files < <(find "$album_folder" -maxdepth 1 -type f -name "*.m4a" ! -name "._*" -print0)
    
    if [ ${#m4a_files[@]} -eq 0 ]; then
      echo "  No .m4a files found in this folder"
      echo ""
      continue
    fi
    
    # Process files in parallel
    job_count=0
    for audio_file in "${m4a_files[@]}"; do
      (
        echo "    Updating: $(basename "$audio_file")"
        AtomicParsley "$audio_file" --artist "$artist_name" --album "$album_name" --overWrite &> /dev/null
        if [ $? -ne 0 ]; then
          echo "    Error updating file: $(basename "$audio_file")"
        fi
      ) &
      
      ((job_count++))
      
      # Limit parallel jobs
      if [ $job_count -ge $MAX_PARALLEL_JOBS ]; then
        wait -n  # Wait for any one job to complete
        ((job_count--))
      fi
    done
    
    # Wait for remaining jobs to complete
    wait
    
    ((album_count++))
    echo "  Updated ${#m4a_files[@]} file(s)"
    echo ""
  else
    echo "Skipping folder (doesn't match naming convention): $folder_name"
    echo ""
  fi
done < <(if [ -n "$SPECIFIC_FOLDER" ]; then
  # Process only the specific folder
  find "$BASE_FOLDER/$SPECIFIC_FOLDER" -type d -mindepth 0 -maxdepth 0 -print0
else
  # Process all folders
  find "$BASE_FOLDER" -type d -mindepth 1 -maxdepth 1 -print0
fi)

echo "Complete! Processed $album_count album(s)"