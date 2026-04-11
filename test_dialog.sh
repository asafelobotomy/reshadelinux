#!/bin/bash
export TERM=xterm-256color
FIFO=/tmp/dialog_test_fifo
OUT=/tmp/dialog_test_out

cleanup() {
    rm -f "$FIFO" "$OUT"
}
trap cleanup EXIT

mkfifo "$FIFO"
touch "$OUT"

test_variant() {
    local name=$1
    local seq=$2
    echo "--- Testing Variant $name ---"
    
    # Run dialog in background
    # Redirecting stdin/stdout to avoid terminal interference
    dialog --clear --title ReShade --radiolist 'What would you like to do?' 12 70 2 install 'Install ReShade for a game' ON uninstall 'Uninstall ReShade for a game' OFF --output-fd 8 --input-fd 9 8>"$OUT" 9<>"$FIFO" < /dev/shm/dummy_in > /dev/shm/dummy_out 2>&1 &
    DPID=$!
    
    # Send keys
    printf "$seq" > "$FIFO"
    
    # Wait for completion
    wait $DPID
    EXIT_CODE=$?
    
    RESULT=$(cat "$OUT")
    echo "Exit Code: $EXIT_CODE"
    echo "Selected: '$RESULT'"
    truncate -s 0 "$OUT"
}

# Create dummy streams to keep dialog from stealing real terminal
touch /dev/shm/dummy_in
touch /dev/shm/dummy_out

test_variant "A (Tab+Enter)" "\t\n"
test_variant "B (Enter)" "\n"
test_variant "C (Tab, Sleep, Enter)" "\t"
sleep 1
printf "\n" > "$FIFO"
# Note: Variant C logic is slightly split above but test_variant waits for DPID. 
# Better to do C manually or adjust.

# Manual C
echo "--- Testing Variant C ---"
dialog --clear --title ReShade --radiolist 'What would you like to do?' 12 70 2 install 'Install ReShade for a game' ON uninstall 'Uninstall ReShade for a game' OFF --output-fd 8 --input-fd 9 8>"$OUT" 9<>"$FIFO" < /dev/shm/dummy_in > /dev/shm/dummy_out 2>&1 &
DPID=$!
printf "\t" > "$FIFO"
sleep 1
printf "\n" > "$FIFO"
wait $DPID
echo "Exit Code: $?"
echo "Selected: '$(cat "$OUT")'"
truncate -s 0 "$OUT"

test_variant "D (Space+Tab+Enter)" " \t\n"

rm /dev/shm/dummy_in /dev/shm/dummy_out
