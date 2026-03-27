#!/bin/bash

# ============================================
# gpu_queue.sh - Auto GPU Queue Scheduler
# 
# !!!!! To Use this script, YOU NEED TO DOWNLOAD *NTFY* Application !!!!!
# 
# Monitors GPUs and automatically runs tasks
# when the assigned GPU becomes available.
#
# Usage:
#   bash gpu_queue.sh                          # defaults (no ntfy, 10m interval)
#   bash gpu_queue.sh -n my_topic              # with ntfy notifications
#   bash gpu_queue.sh -n my_topic -i 5m        # ntfy + 5min scan interval
#   bash gpu_queue.sh -i 30s                   # 30sec scan interval
#   bash gpu_queue.sh -r 3                     # retry up to 3 times on failure
#
# Options:
#   -n TOPIC    ntfy.sh topic (no notifications if omitted)
#   -i INTERVAL scan interval (default: 10m, e.g. 30s, 5m, 1h)
#   -r RETRIES  max retries on failure (default: 0)
# ============================================

# ================== CONFIG ==================

# Task definitions: "GPU_ID|COMMAND"
# If the script internally sets CUDA_VISIBLE_DEVICES → use that GPU ID
# If it can run on any GPU → pick the one you want
TASK_QUEUE=(
    # "0|bash run_0.sh > log/run_0.out"
    # "1|bash run_1.sh > log/run_1.out"
    # "2|bash run_2.sh > log/run_2.out"
    # "3|bash run_3.sh > log/run_3.out"
)

# ================== DO NOT EDIT BELOW ==================

NTFY_TOPIC=""
SCAN_INTERVAL="10m"
MAX_RETRIES=0

while getopts "n:i:r:" opt; do
    case $opt in
        n) NTFY_TOPIC="$OPTARG" ;;
        i) SCAN_INTERVAL="$OPTARG" ;;
        r) MAX_RETRIES="$OPTARG" ;;
        *) echo "Usage: $0 [-n ntfy_topic] [-i scan_interval] [-r max_retries]"; exit 1 ;;
    esac
done

notify() {
    local msg="$1"
    echo "$msg"
    if [ -n "$NTFY_TOPIC" ]; then
        curl -s -d "$msg" "ntfy.sh/$NTFY_TOPIC" > /dev/null 2>&1
    fi
}

run_task() {
    local gpu_id="$1"
    local task="$2"
    local attempt=0

    while [ $attempt -le $MAX_RETRIES ]; do
        if [ $attempt -gt 0 ]; then
            notify "[Retry $attempt/$MAX_RETRIES] GPU $gpu_id: $task"
        fi

        eval "$task"
        local exit_code=$?

        if [ $exit_code -eq 0 ]; then
            notify "Done GPU $gpu_id: $task"
            return 0
        else
            notify "Failed GPU $gpu_id (exit=$exit_code): $task"
            attempt=$((attempt + 1))

            if [ $attempt -le $MAX_RETRIES ]; then
                echo "  Retrying in 10s..."
                sleep 10
            fi
        fi
    done

    notify "Gave up GPU $gpu_id after $((MAX_RETRIES+1)) attempts: $task"
    return 1
}

# Empty queue check
if [ ${#TASK_QUEUE[@]} -eq 0 ]; then
    echo "ERROR: TASK_QUEUE is empty."
    echo "Add tasks to the TASK_QUEUE array at the top of this script."
    echo ""
    echo "Example:"
    echo '    "0|bash train.sh > log/train_gpu0.out"'
    echo '    "1|bash eval.sh > log/eval_gpu1.out"'
    exit 1
fi

declare -A TASK_STARTED
TOTAL_TASKS=${#TASK_QUEUE[@]}
STARTED_COUNT=0

echo "============================================"
echo " GPU Auto Queue"
echo "============================================"
echo " Tasks:         $TOTAL_TASKS"
echo " Scan interval: $SCAN_INTERVAL"
echo " Max retries:   $MAX_RETRIES"
echo " ntfy topic:    ${NTFY_TOPIC:-none}"
echo "============================================"
echo ""
echo " Task list:"
for i in "${!TASK_QUEUE[@]}"; do
    GPU_ID="${TASK_QUEUE[$i]%%|*}"
    TASK="${TASK_QUEUE[$i]#*|}"
    echo "  [$i] GPU $GPU_ID -> $TASK"
done
echo "============================================"

notify "GPU queue started: ${TOTAL_TASKS} tasks"

while [ $STARTED_COUNT -lt $TOTAL_TASKS ]; do
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Scanning GPUs... (pending: $((TOTAL_TASKS - STARTED_COUNT)))"

    for i in "${!TASK_QUEUE[@]}"; do
        if [ "${TASK_STARTED[$i]}" == "1" ]; then
            continue
        fi

        GPU_ID="${TASK_QUEUE[$i]%%|*}"
        TASK="${TASK_QUEUE[$i]#*|}"

        PYTHON_COUNT=$(nvidia-smi --id=$GPU_ID --query-compute-apps=process_name --format=csv,noheader 2>/dev/null | grep -i "python" | wc -l)

        if [ "$PYTHON_COUNT" -eq 0 ]; then
            notify "Started GPU $GPU_ID: $TASK"

            (run_task "$GPU_ID" "$TASK") &

            TASK_STARTED[$i]=1
            STARTED_COUNT=$((STARTED_COUNT + 1))
        else
            echo "  GPU $GPU_ID: ${PYTHON_COUNT} process(es) running (waiting)"
        fi
    done

    if [ $STARTED_COUNT -lt $TOTAL_TASKS ]; then
        echo "Next scan in ${SCAN_INTERVAL}..."
        sleep $SCAN_INTERVAL
    fi
done

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] All tasks dispatched. Waiting for completion..."
wait

notify "All GPU tasks completed!"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done."
