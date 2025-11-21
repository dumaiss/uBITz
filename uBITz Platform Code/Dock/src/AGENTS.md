# Repository Guidelines

## Project Structure & Module Organization
- `addr_decoder.v` is the current top-level module; `addr_decoder_tb.v` provides the simulation testbench; `apio.ini` sets `board = Alchitry-Cu` and `top-module = addr_decoder`.
- Keep new Verilog modules alongside `addr_decoder.v`; update `apio.ini` if the top module changes and add matching constraints.
- Pin mappings live in `addr_decoder.pcf`; add `set_io` entries there when introducing signals.

## Build, Flash, and Run
- `apio clean` — remove previous build artifacts.
- `apio build` — synthesize, place, and route the design for the configured board.
- `apio upload` — flash the generated bitstream to the Alchitry Cu.
- Run commands from the repo root; ensure Apio toolchain dependencies (yosys/nextpnr/arachne) are installed via `apio install`.

## Coding Style & Naming Conventions
- Use 4-space indentation; prefer one signal declaration per line.
- Signals and modules in `lower_snake_case`; keep short, descriptive names (e.g., `pmod_0`, `led_0`).
- Favor simple continuous assigns (`assign signal = ...;`) and minimal inline `//` comments that clarify hardware intent.

## Testing Guidelines
- From `uBITz Platform Code/Dock/src`, run `iverilog -g2012 -s addr_decoder_tb -o sim.out addr_decoder.v addr_decoder_tb.v` then `vvp sim.out` (prints `All addr_decoder tests passed.` and emits `addr_decoder_tb.vcd`). If your shell cannot see a system `iverilog`, use the vendored toolchain at `../../../iverilog-local/bin/iverilog` and `../../../iverilog-local/bin/vvp`.
- `addr_decoder_tb` writes `addr_decoder_tb.vcd` for waveform viewing in GTKWave.
- Add new tests or benches near the module they target; name them `<module>_tb.v`.

## Commit & Pull Request Guidelines
- No existing history here; use a concise convention like `<type>: <summary>` (e.g., `feat: add debounce for inputs`).
- In PRs, describe behavior changes, list commands/tests run (`apio build`, `apio upload`, sims), and note hardware verification (e.g., “verified on Alchitry Cu”). Include updated pin mappings if constraints change.
