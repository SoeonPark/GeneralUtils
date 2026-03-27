# GeneralUtils

Utility scripts for managing GPU workloads and streamlining ML training workflows.

## Scripts

### - `gpu_queue.sh`
  <details>
  
  Monitors individual GPUs and automatically dispatches tasks as each GPU becomes available. Useful when running multiple training jobs across GPUs with different schedules.
  
  **Features**
  - Per-GPU monitoring via `nvidia-smi` (not all-or-nothing)
  - Parallel dispatch — multiple free GPUs get tasks simultaneously
  - Optional retry on failure
  - Optional [ntfy.sh](https://ntfy.sh) push notifications
  - Configurable scan interval
  
  **Quick Start**
  
  1. Edit `TASK_QUEUE` at the top of the script:
  ```bash
  TASK_QUEUE=(
      "0|bash run_0.sh > log/run_0.out"
      "1|bash run_1.sh > log/run_1.out"
      "2|bash run_2.sh > log/run_2.out"
      "3|bash run_3.sh > log/run_3.out"
  )
  ```
  
  2. Run:
  ```bash
  # Basic
  bash gpu_queue.sh
  
  # With ntfy notifications, 5min scan interval, 2 retries
  bash gpu_queue.sh -n my_topic -i 5m -r 2
  ```
  
  | Option | Description | Default |
  |--------|-------------|---------|
  | `-n TOPIC` | ntfy.sh topic for push notifications | none |
  | `-i INTERVAL` | GPU scan interval (e.g. `30s`, `5m`, `1h`) | `10m` |
  | `-r N` | Max retries on task failure | `0` |
  
  </details> 

## License

MIT
