#!/bin/bash

# Directory definitions
BIN_DIR="./bin"
ORIGINAL_DIR="./original"
BETA_DIR="./beta"
OUT_DIR="./out"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Binary paths
VERIFY_BIN="${BIN_DIR}/BlockImageVerify"
UPDATE_BIN="${BIN_DIR}/BlockImageUpdate"
SIMG2IMG_BIN="${BIN_DIR}/simg2img"
LPUNPACK_BIN="${BIN_DIR}/lpunpack"

echo -e "${BOLD}--- Pre-run Checks ---${NC}"

# Ensure directories exist
for DIR in "$BIN_DIR" "$ORIGINAL_DIR" "$BETA_DIR"; do
    if [ ! -d "$DIR" ]; then
        echo -e "${RED}Error: Directory '${DIR}' not found.${NC}"
        exit 1
    fi
done

# Create output directory if it doesn't exist
if [ ! -d "$OUT_DIR" ]; then
    echo -e "Creating output directory: ${OUT_DIR}"
    mkdir -p "$OUT_DIR"
fi

# Ensure binaries exist and are executable
for BIN in "$VERIFY_BIN" "$UPDATE_BIN" "$SIMG2IMG_BIN" "$LPUNPACK_BIN"; do
    if [ ! -f "$BIN" ]; then
        echo -e "${RED}Error: Binary '$(basename "$BIN")' not found in ${BIN_DIR}.${NC}"
        exit 1
    fi
    chmod +x "$BIN" 2>/dev/null
done

# Function to extract beta files if missing
extract_beta_if_needed() {
    # Check if we already have .new.dat files (basic check for beta contents)
    if [ $(ls "${BETA_DIR}"/*.new.dat 2>/dev/null | wc -l) -eq 0 ]; then
        echo -e "No beta files found. Checking for zip in ${BETA_DIR}..."
        local BETA_ZIP=$(ls "${BETA_DIR}"/*.zip 2>/dev/null | head -n 1)
        if [[ -n "$BETA_ZIP" ]]; then
            echo -e "Extracting $(basename "$BETA_ZIP") to ${BETA_DIR}..."
            unzip -o "$BETA_ZIP" -d "$BETA_DIR" > /dev/null
        else
            echo -e "${RED}Warning: No beta zip or files found in ${BETA_DIR}.${NC}"
        fi
    fi
}

# Firmware extraction logic
extract_super_image() {
    local FW_FILE="$1"
    local EXT="${FW_FILE##*.}"
    
    echo -e "Processing firmware file: $(basename "$FW_FILE")"
    
    if [[ "$EXT" == "zip" ]]; then
        # Look for AP file inside zip
        local AP_FILE=$(unzip -l "$FW_FILE" | grep -i "AP_" | awk '{print $NF}' | head -n 1)
        if [[ -n "$AP_FILE" ]]; then
            echo -e "Found AP file: $AP_FILE"
            echo -e "Extracting super.img.lz4 from $AP_FILE..."
            # Extract AP from ZIP, then super.img.lz4 from AP
            unzip -p "$FW_FILE" "$AP_FILE" | tar -Oxvf - super.img.lz4 2>/dev/null > "${ORIGINAL_DIR}/super.img.lz4"
        else
            echo -e "${RED}No AP file found in zip.${NC}"
            return 1
        fi
    elif [[ "$EXT" == "tar" ]] || [[ "$EXT" == "md5" ]]; then
        # Check if it's an AP file directly
        if [[ "$(basename "$FW_FILE")" == AP_* ]]; then
            echo -e "Extracting super.img.lz4 from $(basename "$FW_FILE")..."
            tar -xvf "$FW_FILE" -C "$ORIGINAL_DIR" super.img.lz4 2>/dev/null
        else
            # Try to look inside if it's a collection (less common for tar)
            echo -e "${RED}File is not an AP file.${NC}"
            return 1
        fi
    fi

    if [[ -f "${ORIGINAL_DIR}/super.img.lz4" ]]; then
        echo -e "Decompressing super.img.lz4..."
        lz4 -d "${ORIGINAL_DIR}/super.img.lz4" "${ORIGINAL_DIR}/super.img"
        rm "${ORIGINAL_DIR}/super.img.lz4"
        
        echo -e "Converting super.img to raw (super_raw.img)..."
        "$SIMG2IMG_BIN" "${ORIGINAL_DIR}/super.img" "${ORIGINAL_DIR}/super_raw.img"
        rm "${ORIGINAL_DIR}/super.img"
        
        echo -e "Unpacking super_raw.img..."
        # We need to run lpunpack inside original/ or specify destination
        (cd "$ORIGINAL_DIR" && "../$LPUNPACK_BIN" super_raw.img .)
        
        return 0
    else
        echo -e "${RED}Failed to extract super.img.lz4.${NC}"
        return 1
    fi
}

# Extract beta if needed
extract_beta_if_needed

# Get list of images in original/
IMAGES=($(ls "${ORIGINAL_DIR}"/*.img 2>/dev/null | grep -v "super_raw.img"))

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo -e "No .img files found. Checking for compressed firmware..."
    FW_FILES=($(ls "${ORIGINAL_DIR}"/*.zip "${ORIGINAL_DIR}"/*.tar "${ORIGINAL_DIR}"/*.tar.md5 "${ORIGINAL_DIR}"/*.md5 2>/dev/null))
    
    if [ ${#FW_FILES[@]} -gt 0 ]; then
        for FW in "${FW_FILES[@]}"; do
            if extract_super_image "$FW"; then
                IMAGES=($(ls "${ORIGINAL_DIR}"/*.img 2>/dev/null | grep -v "super_raw.img"))
                break
            fi
        done
    fi
fi

if [ ${#IMAGES[@]} -eq 0 ]; then
    echo -e "${RED}Error: No .img files found and extraction failed or skipped.${NC}"
    exit 1
fi

echo -e "${GREEN}All checks passed. Starting process...${NC}\n"

echo -e "${BOLD}--- Verification Phase ---${NC}"

# Verification Phase
for IMG_PATH in "${IMAGES[@]}"; do
    IMG_NAME=$(basename "$IMG_PATH")
    BASE_NAME="${IMG_NAME%.img}"
    
    TRANSFER_LIST="${BETA_DIR}/${BASE_NAME}.transfer.list"
    NEW_DAT="${BETA_DIR}/${BASE_NAME}.new.dat"
    PATCH_DAT="${BETA_DIR}/${BASE_NAME}.patch.dat"
    
    # Check if necessary files exist in beta/ for this image
    MISSING_FILES=()
    [[ ! -f "$TRANSFER_LIST" ]] && MISSING_FILES+=(".transfer.list")
    [[ ! -f "$NEW_DAT" ]] && MISSING_FILES+=(".new.dat")
    [[ ! -f "$PATCH_DAT" ]] && MISSING_FILES+=(".patch.dat")
    
    if [ ${#MISSING_FILES[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing files for ${IMG_NAME} in ${BETA_DIR}: ${MISSING_FILES[*]}${NC}"
        echo -e "Skipping ${IMG_NAME}..."
        continue
    fi
    
    echo -n "Verifying ${IMG_NAME}... "
    "$VERIFY_BIN" "$IMG_PATH" "$TRANSFER_LIST" "$NEW_DAT" "$PATCH_DAT" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESSFUL${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        exit 1
    fi
done

echo -e "\n${BOLD}--- Update Phase ---${NC}"

# Update Phase
for IMG_PATH in "${IMAGES[@]}"; do
    IMG_NAME=$(basename "$IMG_PATH")
    BASE_NAME="${IMG_NAME%.img}"
    
    TRANSFER_LIST="${BETA_DIR}/${BASE_NAME}.transfer.list"
    NEW_DAT="${BETA_DIR}/${BASE_NAME}.new.dat"
    PATCH_DAT="${BETA_DIR}/${BASE_NAME}.patch.dat"
    OUT_PATH="${OUT_DIR}/${IMG_NAME}"
    
    if [[ ! -f "$TRANSFER_LIST" ]] || [[ ! -f "$NEW_DAT" ]] || [[ ! -f "$PATCH_DAT" ]]; then
        continue
    fi
    
    echo -n "Updating ${IMG_NAME}... "
    
    # Copy original to out
    cp "$IMG_PATH" "$OUT_PATH"
    
    # Update
    "$UPDATE_BIN" "$OUT_PATH" "$TRANSFER_LIST" "$NEW_DAT" "$PATCH_DAT" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SUCCESSFUL${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        exit 1
    fi
done

echo -e "\n${GREEN}${BOLD}Everything completed successfully!${NC}"
