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
BOOT_CONFIG="/boot/config.txt"

echo -e "${GREEN}Starting DreamPi audio modification script...${NC}\n"

# 0. Pre-Flight Check
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

    if [ ! -s "$TEMP_MP3" ]; then
        echo -e "${RED}Error: Failed to download the audio file. Check your internet connection.${NC}"
        rm -f "$TEMP_MP3"
        exit 1
    fi

    echo "Converting MP3 to WAV format (required for aplay)..."
    if ! command -v ffmpeg &> /dev/null; then
        echo "ffmpeg not found. Installing it now (this may take a minute)..."
        sudo apt-get update -qq && sudo apt-get install -y ffmpeg -qq
    fi

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
    if [ ! -f "$TARGET" ]; then
        if [ "$TARGET" == "$STANDARD_FILE" ]; then
            echo "Notice: $STANDARD_FILE not found. Cloning it from $DREAMPI_FILE..."
            cp "$DREAMPI_FILE" "$STANDARD_FILE"
        else
            echo -e "${RED}Error: Could not find $TARGET! Skipping...${NC}"
            continue
        fi
    fi

    if grep -q "CUSTOM AUDIO TRIGGER" "$TARGET"; then
        echo -e "${GREEN}Success: $TARGET is already patched! Skipping injection.${NC}"
        continue
    fi

    echo "Injecting trigger into $TARGET..."
    cp "$TARGET" "${TARGET}.bak"

    awk '
    { print $0 }
    /logger\.info\("Mode detected: %s" % client\)/ {
        print "                        # --- CUSTOM AUDIO TRIGGER ---"
        print "                        subprocess.Popen([\"aplay\", \"/home/pi/dial-up.wav\"])"
        print "                        # ----------------------------"
    }
    ' "${TARGET}.bak" > "$TARGET"

    chmod +x "$TARGET"
    echo -e "${GREEN}Successfully updated $TARGET${NC}"
done
echo ""

# 3. Configure Boot Parameters (Hardware Audio)
echo -e "${YELLOW}--- Step 3: Configuring Boot Parameters (/boot/config.txt) ---${NC}"

BOOT_PARAMS=(
    "config_hdmi_boost=4"
    "hdmi_force_hotplug=1"
    "hdmi_drive=2"
    "dtparam=audio=on"
)

for param in "${BOOT_PARAMS[@]}"; do
    # Check if the exact line is already active
    if grep -qxF "$param" "$BOOT_CONFIG"; then
        echo -e "${GREEN}Already set: $param${NC}"
    # Check if it exists but is commented out (with or without spaces after the #)
    elif grep -qE "^#[[:space:]]*$param" "$BOOT_CONFIG"; then
        echo "Uncommenting: $param"
        sudo sed -i "s/^#[[:space:]]*$param/$param/" "$BOOT_CONFIG"
    else
        # Append to the end of the file
        echo "Adding: $param"
        echo "$param" | sudo tee -a "$BOOT_CONFIG" > /dev/null
    fi
done
echo ""

# 4. Configure ALSA (Software Audio)
echo -e "${YELLOW}--- Step 4: Configuring ALSA Audio Settings ---${NC}"
echo "Select your default audio output:"
echo "--------------------------------------------------"
echo "1) 3.5mm Analog Jack (Card 0)"
echo "2) HDMI (Card 1)"
echo "--------------------------------------------------"

read -p "Enter your choice (1 or 2): " user_choice

if [ "$user_choice" == "1" ]; then
    card_num=0
    output_name="3.5mm Analog Jack"
elif [ "$user_choice" == "2" ]; then
    card_num=1
    output_name="HDMI"
else
    echo -e "${RED}Error: Invalid selection. Skipping ALSA configuration.${NC}"
    card_num=""
fi

if [ -n "$card_num" ]; then
    echo "Configuring ALSA to use $output_name (Card $card_num)..."
    
    cat <<EOF | sudo tee /etc/asound.conf > /dev/null
defaults.pcm.card $card_num
defaults.ctl.card $card_num
EOF

    echo -e "${GREEN}Configuration saved successfully!${NC}"
fi

echo -e "\n${GREEN}Modification complete! The DreamPi is configured to play the dial-up sound.${NC}"
echo "To test the ALSA audio manually, run: speaker-test -c2 -twav"

# 5. Reboot Prompt
echo -e "\n${YELLOW}A system reboot is required for the /boot/config.txt hardware changes to take effect.${NC}"
read -p "Would you like to reboot the Raspberry Pi now? (y/n): " reboot_choice

if [[ "$reboot_choice" == [Yy]* ]]; then
    echo "Rebooting..."
    sudo reboot
else
    echo "Please remember to reboot later to apply the hardware audio settings!"
fi