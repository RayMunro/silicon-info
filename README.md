# Silicon Info

A floating desktop widget for Apple Silicon Macs that splits system activity into its parts: CPU performance and efficiency cores, the GPU, the Neural Engine, unified memory (DRAM), and total power. Click any card to expand it into a detailed view.

Full documentation: [docs/Silicon-Info-Documentation.pdf](docs/Silicon-Info-Documentation.pdf)

## Requirements

- A Mac with Apple Silicon
- macOS 14 or later
- Xcode command line tools (Swift 5.9 or later)

## Build and run

```bash
./build.sh
open "Silicon Info.app"
```

On launch the widget asks for your administrator password through the standard macOS dialog. This is needed to read power, frequency and per-process figures from `powermetrics`. If you decline, the widget still runs but shows `n/a` for the values that need it.

To quit the widget:

```bash
pkill SiliconWidget
```

## What you see

| Card | Overview | Expanded |
| --- | --- | --- |
| CPU | Per-core bars grouped as performance and efficiency cores, power, history | Cluster frequency and residency, per-core user and system load with clock speed, top processes, power history |
| GPU | Utilization ring, render and tiler load, power | Frequency, residency by clock step, engines, memory, top GPU processes |
| Neural Engine | Power ring and history | Average and peak power, session energy, activity state |
| Memory | Used and total memory with a breakdown bar and pressure level | Breakdown (app, wired, compressed, cached, free), pressure, swap, paging rates, top processes, history |
| Power | CPU, GPU and Neural Engine share of total | Live split, stacked two-minute history, average, peak and energy per block |

## Limits

macOS does not expose some figures on this hardware, so the widget does not show them:

- Neural Engine utilization, frequency or per-process use (only its power draw is available)
- Per-cluster CPU power (only the CPU total)
- DRAM bandwidth and DRAM power (macOS refuses access even with admin rights)
- Media engine power

## Project layout

- `Sources/SiliconWidget/Sampler.swift` collects per-core load, GPU statistics and history
- `Sources/SiliconWidget/Memory.swift` reads unified memory usage, pressure and swap
- `Sources/SiliconWidget/PowerFeed.swift` runs and parses `powermetrics`
- `Sources/SiliconWidget/Views.swift` and `Detail.swift` hold the interface
- `Sources/SiliconWidget/main.swift` creates the floating window
- `scripts/make_icon.swift` draws the app icon
- `build.sh` builds the app bundle

## License

Copyright (c) 2026 Ray Munro. All rights reserved.
