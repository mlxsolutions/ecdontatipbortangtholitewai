#!/bin/bash

### CONFIG ###################################################################

SOURCE_DIR="$OME_DOCKER_HOME/rec"
DEST_DIR="$OME_DOCKER_HOME/rec-done"


# HLS output settings
HLS_SEGMENT_TIME=6
HLS_PLAYLIST_TYPE="vod"

# Logging
LOG_DIR="$OME_DOCKER_HOME/logs"
LOG_FILE="$LOG_DIR/ome-record-worker.log"
MAX_DAYS=7

# Webhook callback env vars (export in /etc/environment or systemd service)
MLAPI_CALLBACK="https://api.muselink.com/pre/ome/rec"
MLAPI_KEY="MFMD8H2ECHKZ0CDVTUUYOVMQ1V0JBM9Y"

# Rclone bandwidth throttle
RCLONE_BWLIMIT="50M"
BUCKET_NAME="vodstack-destination-1v3nwphy8f3az"
RCLONE_BASE="mys3:vodstack-destination-1v3nwphy8f3az"
RCLONE_CONFIG="/home/ubuntu/.config/rclone/rclone.conf"

mkdir -p "$DEST_DIR"
mkdir -p "$LOG_DIR"

### LOGGING ###################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

rotate_logs() {
    find "$LOG_DIR" -name "ome-record-worker.log.*" -mtime +$MAX_DAYS -delete

    if [[ -f "$LOG_FILE" ]]; then
        cp "$LOG_FILE" "$LOG_FILE.$(date '+%Y-%m-%d')"
        echo "" > "$LOG_FILE"
    fi

    log "Log rotation complete (keeping last $MAX_DAYS days)"
}

rotate_logs
log "HLS watcher starting..."

### PROCESSING FUNCTION ########################################################

process_file() {
    local NEWFILE="$1"
    local BASENAME="$(basename "$NEWFILE" .mp4)"
    local XMLFILE="$SOURCE_DIR/$BASENAME.xml"
    local FINAL_DIR="$DEST_DIR/$BASENAME"

    log "Processing MP4 file: $NEWFILE"

    ###########################################################################
    # STEP 1 — WAIT FOR FILE SIZE STABILIZATION
    ###########################################################################

    log "Waiting for MP4 size to stabilize..."
    local PREV_SIZE=0
    local CURRENT_SIZE
    local FILE_SIZE_BYTES
    while true; do
        CURRENT_SIZE=$(stat -c%s "$NEWFILE" 2>/dev/null || echo 0)
        if [[ "$CURRENT_SIZE" -eq "$PREV_SIZE" && "$CURRENT_SIZE" -gt 0 ]]; then
            log "Size stable at ${CURRENT_SIZE} bytes"
            FILE_SIZE_BYTES="$CURRENT_SIZE"
            break
        fi
        PREV_SIZE="$CURRENT_SIZE"
        sleep 10
    done

    ###########################################################################
    # STEP 2 — BEGIN WEBHOOK CALLBACK
    ###########################################################################
    local KEY_PATH="live/$BASENAME"

local BEGIN_PAYLOAD=$(cat <<EOF
{
  "action": "begin",
  "request": {
    "bucket": "$BUCKET_NAME",
    "key": "$KEY_PATH",
    "fileSizeBytes": $FILE_SIZE_BYTES
  }
}
EOF
)

    log "Sending webhook (begin)"

    local BEGIN_RESPONSE=$(curl -s -o /tmp/wh_resp_begin -w "%{http_code}" \
        -X POST "$MLAPI_CALLBACK" \
        -H "X-API-KEY: $MLAPI_KEY" \
        -H "Content-Type: application/json" \
        --data "$BEGIN_PAYLOAD")

    if [[ "$BEGIN_RESPONSE" -ge 200 && "$BEGIN_RESPONSE" -lt 300 ]]; then
        log "Webhook (begin) OK"
    else
        log "ERROR: Webhook (begin) failed — HTTP $BEGIN_RESPONSE"
        cat /tmp/wh_resp_begin | tee -a "$LOG_FILE"
    fi

    ###########################################################################
    # STEP 3 — MOVE + RENAME FILES
    ###########################################################################

    mkdir -p "$FINAL_DIR"

    mv "$NEWFILE" "$FINAL_DIR/OR.mp4"
    log "Moved MP4 → OR.mp4"

    if [[ -f "$XMLFILE" ]]; then
        mv "$XMLFILE" "$FINAL_DIR/manifest.xml"
        log "Moved XML → manifest.xml"
    else
        log "WARNING: XML file missing"
    fi

    local MOVED_MP4="$FINAL_DIR/OR.mp4"

    ###########################################################################
    # STEP 4 — AUTO AUDIO DETECTION
    ###########################################################################

    local HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_type \
        -of csv=p=0 "$MOVED_MP4")

    if [[ -z "$HAS_AUDIO" ]]; then
        log "No audio track detected — injecting silent audio track"
        FF_AUDIO="-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 -shortest -c:a aac -b:a 128k"
        MAP_AUDIO="-map 1:a"
        MAP_VIDEO="-map 0:v"
        INPUT_ORDER="-i \"$MOVED_MP4\""
    else
        log "Audio track detected — copying audio stream"
        FF_AUDIO="-c:a copy"
        MAP_AUDIO=""
        MAP_VIDEO=""
        INPUT_ORDER="-i \"$MOVED_MP4\""
    fi

    ###########################################################################
    # STEP 5 — GENERATE HLS OUTPUT
    ###########################################################################
    sleep 10
    log "Starting FFmpeg HLS conversion..."

    if [[ -z "$HAS_AUDIO" ]]; then
        ffmpeg -y -i "$MOVED_MP4" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
            -shortest -c:v copy -c:a aac -b:a 128k \
            -map 0:v -map 1:a \
            -hls_time "$HLS_SEGMENT_TIME" \
            -hls_playlist_type "$HLS_PLAYLIST_TYPE" \
            -hls_segment_filename "$FINAL_DIR/segment_%05d.ts" \
            "$FINAL_DIR/index.m3u8" >>"$LOG_FILE" 2>&1
    else
        ffmpeg -y -i "$MOVED_MP4" \
            -c:v copy -c:a copy \
            -hls_time "$HLS_SEGMENT_TIME" \
            -hls_playlist_type "$HLS_PLAYLIST_TYPE" \
            -hls_segment_filename "$FINAL_DIR/segment_%05d.ts" \
            "$FINAL_DIR/index.m3u8" >>"$LOG_FILE" 2>&1
    fi

    if [[ $? -ne 0 ]]; then
        log "ERROR: FFmpeg failed"
        return
    fi

    ###########################################################################
    # STEP 6 — EXTRACT AUDIO FOR ASR
    ###########################################################################

    if [[ -n "$HAS_AUDIO" ]]; then
        local WAV_FILE="$FINAL_DIR/OR.wav"
        log "Extracting audio for ASR..."

        ffmpeg -y -i "$MOVED_MP4" -vn -acodec pcm_s16le \
            -ar 16000 -ac 1 -f wav "$WAV_FILE" >>"$LOG_FILE" 2>&1

        if [[ $? -ne 0 ]]; then
            log "WARNING: Audio extraction failed (continuing anyway)"
        else
            log "Audio extracted → OR.wav"
        fi
    else
        log "Skipping audio extraction (no audio track detected)"
    fi

    ###########################################################################
    # STEP 7 — METADATA EXTRACTION FOR master.m3u8
    ###########################################################################

    local WIDTH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
        -of default=noprint_wrappers=1:nokey=1 "$MOVED_MP4")

    local HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
        -of default=noprint_wrappers=1:nokey=1 "$MOVED_MP4")

    local BITRATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 "$MOVED_MP4")

    if [[ -z "$BITRATE" || "$BITRATE" == "N/A" ]]; then
        local DURATION=$(ffprobe -v error -show_entries format=duration \
            -of default=noprint_wrappers=1:nokey=1 "$MOVED_MP4")
        local FILESIZE=$(stat -c%s "$MOVED_MP4")
        BITRATE=$(awk "BEGIN { printf \"%.0f\", ($FILESIZE * 8) / $DURATION }")
    fi

    local RAW_FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate \
        -of default=noprint_wrappers=1:nokey=1 "$MOVED_MP4")

    local FPS
    [[ "$RAW_FPS" == */* ]] && FPS=$(awk "BEGIN { print $RAW_FPS }") || FPS="$RAW_FPS"
    [[ -z "$FPS" || "$FPS" == "N/A" ]] && FPS="30.0"

cat > "$FINAL_DIR/master.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:3

#EXT-X-STREAM-INF:BANDWIDTH=$BITRATE,RESOLUTION=${WIDTH}x${HEIGHT},FRAME-RATE=$FPS
index.m3u8
EOF

    log "master.m3u8 generated"

    ###########################################################################
    # STEP 8 — UPLOAD TO S3 VIA RCLONE
    ###########################################################################
    sleep 10
    
    local RCLONE_DEST="$RCLONE_BASE/live/$BASENAME"

    log "Base: $RCLONE_BASE"
    log "Uploading folder to $RCLONE_DEST"
    log "Source: $FINAL_DIR"
    log "Destination: $RCLONE_DEST"
    log "Config: $RCLONE_CONFIG"

    rclone copy "$FINAL_DIR" "$RCLONE_DEST" \
        --bwlimit "$RCLONE_BWLIMIT" \
        --log-file="$LOG_DIR/rclone.log" \
        --log-level INFO \
        --transfers=4 \
        --checkers=8 \
        --create-empty-src-dirs=true \
        --config="$RCLONE_CONFIG" \
        --progress 2>&1 | tee -a "$LOG_FILE"

    local RCLONE_EXIT_CODE=$?
    
    if [[ $RCLONE_EXIT_CODE -ne 0 ]]; then
        log "ERROR: rclone upload failed with exit code $RCLONE_EXIT_CODE"
        log "Check $LOG_DIR/rclone.log for details"
        return
    fi

    log "Upload finished successfully"

    ###########################################################################
    # STEP 9 — COMPLETE WEBHOOK CALLBACK
    ###########################################################################

local COMPLETE_PAYLOAD=$(cat <<EOF
{
  "action": "complete",
  "request": {
    "bucket": "$BUCKET_NAME",
    "key": "$KEY_PATH",
    "fileSizeBytes": $FILE_SIZE_BYTES
  }
}
EOF
)

    log "Sending webhook (complete)"

    local COMPLETE_RESPONSE=$(curl -s -o /tmp/wh_resp_complete -w "%{http_code}" \
        -X POST "$MLAPI_CALLBACK" \
        -H "X-API-KEY: $MLAPI_KEY" \
        -H "Content-Type: application/json" \
        --data "$COMPLETE_PAYLOAD")

    if [[ "$COMPLETE_RESPONSE" -ge 200 && "$COMPLETE_RESPONSE" -lt 300 ]]; then
        log "Webhook (complete) OK"
    else
        log "ERROR: Webhook (complete) failed — HTTP $COMPLETE_RESPONSE"
        cat /tmp/wh_resp_complete | tee -a "$LOG_FILE"
    fi

    ###########################################################################
    # STEP 10 — CLEANUP SOURCE + DESTINATION
    ###########################################################################
    sleep 10
    log "Cleaning up local files..."

    rm -rf "$FINAL_DIR"
    rm -f "$SOURCE_DIR/$BASENAME.mp4" "$SOURCE_DIR/$BASENAME.xml"

    find "$SOURCE_DIR" -maxdepth 1 -type f \
        \( -name "*.ts" -o -name "*.m3u8" -o -name "*.tmp" -o -name "*.part" \) \
        -exec rm -f {} \;

    find "$SOURCE_DIR" -mindepth 1 -type d -empty -delete

    log "Processing completed for $BASENAME"
}

### STARTUP: PROCESS EXISTING FILES ###########################################

log "Checking for existing MP4 files to process..."

for EXISTING_FILE in "$SOURCE_DIR"/*.mp4; do
    [[ -f "$EXISTING_FILE" ]] || continue
    log "Found existing file: $EXISTING_FILE"
    process_file "$EXISTING_FILE"
done

log "Existing files processed. Starting file watcher..."

### MAIN PROCESS LOOP #########################################################

inotifywait -m -e create -e moved_to --format '%w%f' "$SOURCE_DIR" |
while read NEWFILE; do
    EXT="${NEWFILE##*.}"

    [[ "$EXT" != "mp4" ]] && continue

    process_file "$NEWFILE"
done
