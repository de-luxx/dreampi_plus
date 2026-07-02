#!/bin/bash

# --- Colors for Terminal Output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- File Paths and URLs ---
DREAMPI_DIR="/home/pi/dreampi"
DREAMPI_FILE="$DREAMPI_DIR/dreampi.py"
STANDARD_FILE="$DREAMPI_DIR/dreampi_standard.py"
WAV_FILE="/home/pi/dial-up.wav"
TEMP_MP3="/home/pi/temp_audio.mp3"
AUDIO_URL="https://cdn.pixabay.com/download/audio/2021/08/04/audio_d6eed67890.mp3"

echo -e "${GREEN}Starting DreamPi audio modification script...${NC}\n"

# 0. Pre-Flight Check
# Make sure the base script actually exists before we do anything
if [ ! -d "$DREAMPI_DIR" ] || [ ! -f "$DREAMPI_FILE" ]; then
    echo -e "${RED}Error: Could not find the base script at $DREAMPI_FILE!${NC}"
    echo "Please ensure DreamPi is installed correctly in /home/pi/dreampi/"
    exit 1
fi

# 1. Download and Convert the Audio File
echo -e "${YELLOW}--- Step 1: Audio Setup ---${NC}"
if [ ! -f "$WAV_FILE" ]; then
    echo "Downloading dial-up sound..."
    wget -q --show-progress -O "$TEMP_MP3" "$AUDIO_URL"

    # Verification check: Did wget actually download data, or did it fail/error out?
    if [ ! -s "$TEMP_MP3" ]; then
        echo -e "${RED}Error: Failed to download the audio file. Check your internet connection.${NC}"
        rm -f "$TEMP_MP3" # Clean up the empty garbage file
        exit 1
    fi

    echo "Converting MP3 to WAV format (required for aplay)..."
    if ! command -v ffmpeg &> /dev/null; then
        echo "ffmpeg not found. Installing it now (this may take a minute)..."
        sudo apt-get update -qq && sudo apt-get install -y ffmpeg -qq
    fi

    # Convert to WAV and clean up the temp MP3
    ffmpeg -y -i "$TEMP_MP3" "$WAV_FILE" -loglevel error
    rm -f "$TEMP_MP3"
    echo -e "${GREEN}Audio file successfully created at $WAV_FILE${NC}\n"
else
    echo -e "${GREEN}Audio file $WAV_FILE already exists. Skipping download.${NC}\n"
fi

# 2. Patch the Python Scripts
echo -e "${YELLOW}--- Step 2: Patching Python Scripts ---${NC}"
TARGETS=("$DREAMPI_FILE" "$STANDARD_FILE")

for TARGET in "${TARGETS[@]}"; do
    
    # If the target file doesn't exist...
    if [ ! -f "$TARGET" ]; then
        # ...and it's the standard file, duplicate it from the base file.
        if [ "$TARGET" == "$STANDARD_FILE" ]; then
            echo "Notice: $STANDARD_FILE not found. Cloning it from $DREAMPI_FILE..."
            cp "$DREAMPI_FILE" "$STANDARD_FILE"
        else
            # This shouldn't trigger due to the pre-flight check, but just in case.
            echo -e "${RED}Error: Could not find $TARGET! Skipping...${NC}"
            continue
        fi
    fi

    # Check to prevent double-patching
    if grep -q "CUSTOM AUDIO TRIGGER" "$TARGET"; then
        echo -e "${GREEN}Success: $TARGET is already patched! Skipping injection.${NC}"
        continue
    fi

    echo "Injecting trigger into $TARGET..."
    
    # Create a backup
    cp "$TARGET" "${TARGET}.bak"

    # Inject the code safely using awk
    awk '
    { print $0 }
    /logger\.info\("Mode detected: %s" % client\)/ {
        print "                        # --- CUSTOM AUDIO TRIGGER ---"
        print "                        subprocess.Popen([\"aplay\", \"/home/pi/dial-up.wav\"])"
        print "                        # ----------------------------"
    }
    ' "${TARGET}.bak" > "$TARGET"

    # Ensure the file remains executable
    chmod +x "$TARGET"
    echo -e "${GREEN}Successfully updated $TARGET${NC}"
    
done

echo -e "\n${GREEN}Modification complete! The DreamPi will now play the classic dial-up sound on connection.${NC}"
