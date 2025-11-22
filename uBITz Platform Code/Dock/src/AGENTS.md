# Repository Guidelines

## Project Structure & Module Organization
- Top module: `addr_decoder.v` (Dock address decoder/bus arbiter with Mode-2 vector steering).
- Supporting modules: `addr_decoder_cfg.v`, `addr_decoder_match.v`, `addr_decoder_fsm.v`, `addr_decoder_datapath.v`, `irq_router.v`.
- Testbenches live in this directory (e.g., `addr_decoder_tb.v`, `addr_decoder_complex_tb.v`, `addr_decoder_worked_example_tb.v`, `irq_router_tb.v`). Keep new benches near their targets and name them `<module>_tb.v`.
- Pin constraints: `addr_decoder.pcf` (HX8K cb132). Add/update `set_io` entries when interfaces change.
- Build scripts: `CMakeLists.txt` drives yosys/nextpnr/icepack; `util_report.sh` summarizes utilization from `hardware.rpt`.
- Legacy/unused modules have been pruned; avoid reintroducing `addr_decoder_irq.v`.

## Build, Flash, and Run (CMake flow)
- From `uBITz Platform Code/Dock/src`:
  - Configure once: `cmake -S . -B build`
  - Build: `cmake --build build` (runs yosys → nextpnr-ice40 → icepack; outputs in `build/`).
  - Utilization: `./util_report.sh build/hardware.rpt` (JSON summary).
- Toolchain: yosys/nextpnr-ice40/icepack must be available (OSS CAD Suite via Apio works).
- If you need Apio instead, add/update `apio.ini` with `board = Alchitry-Cu` and `top-module = addr_decoder`, then use `apio clean/build/upload`. The repo currently uses CMake by default.

## Coding Style & Naming Conventions
- Use 4-space indentation; prefer one signal declaration per line.
- Signals and modules in `lower_snake_case`; keep short, descriptive names (e.g., `pmod_0`, `led_0`).
- Favor simple continuous assigns (`assign signal = ...;`) and minimal inline `//` comments that clarify hardware intent.

## Testing Guidelines
- Quick regression (from `uBITz Platform Code/Dock/src`):
  - `iverilog -g2012 -s addr_decoder_tb -o sim.out addr_decoder.v addr_decoder_cfg.v addr_decoder_match.v addr_decoder_fsm.v addr_decoder_datapath.v irq_router.v addr_decoder_tb.v` then `vvp sim.out` (expects “All addr_decoder tests passed.”).
  - For integration vector tests: `iverilog -g2012 -s addr_decoder_irq_vec_tb -o irq_vec_sim.out addr_decoder.v addr_decoder_cfg.v addr_decoder_match.v addr_decoder_fsm.v addr_decoder_datapath.v irq_router.v addr_decoder_irq_vec_tb.v` then `vvp irq_vec_sim.out`.
  - If `iverilog` is not on PATH, use the vendored tools at `../../../iverilog-local/bin/iverilog` and `../../../iverilog-local/bin/vvp`.
- Waveforms: benches write `*.vcd` for GTKWave.
- Add new benches alongside their target module.

## Commit & Pull Request Guidelines
- No existing history here; use a concise convention like `<type>: <summary>` (e.g., `feat: add debounce for inputs`).
- In PRs, describe behavior changes, list commands/tests run (`apio build`, `apio upload`, sims), and note hardware verification (e.g., “verified on Alchitry Cu”). Include updated pin mappings if constraints change.
- Keep the markdown docs in this directory (`README.md`, `Test Suite.md`, `Mode-2-Interrupt-Test.md`) in sync with code changes; update them whenever behavior, build steps, or test plans shift.
