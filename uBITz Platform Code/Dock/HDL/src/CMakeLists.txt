cmake_minimum_required(VERSION 3.16)
# Dummy language declaration; we only run external tools. If no compiler is
# available, CMake still configures because we do not build C sources.
project(addressdecode_fpga LANGUAGES NONE)

# Paths to sources (top-level only; benches are excluded from synthesis).
set(ADDRDECODE_SRCS
    ${CMAKE_SOURCE_DIR}/addr_decoder.v
    ${CMAKE_SOURCE_DIR}/addr_decoder_cfg.v
    ${CMAKE_SOURCE_DIR}/addr_decoder_match.v
    ${CMAKE_SOURCE_DIR}/addr_decoder_fsm.v
    ${CMAKE_SOURCE_DIR}/addr_decoder_datapath.v
    ${CMAKE_SOURCE_DIR}/irq_router.v
)

# Board/device selection (override with -DFPGA_DEVICE=..., -DFPGA_PACKAGE=..., -DFPGA_PCF=...).
set(FPGA_DEVICE  "hx8k" CACHE STRING "nextpnr-ice40 device (e.g. hx8k, up5k)")
set(FPGA_PACKAGE "cb132" CACHE STRING "Package for the chosen device (e.g. cb132, sg48)")
set(FPGA_PCF     "${CMAKE_SOURCE_DIR}/addr_decoder.pcf" CACHE STRING "Path to constraints PCF file")

if (NOT EXISTS "${FPGA_PCF}")
    message(FATAL_ERROR "PCF file not found: ${FPGA_PCF}")
endif()

set(SYNTH_JSON ${CMAKE_CURRENT_BINARY_DIR}/hardware.json)
set(PNR_ASC   ${CMAKE_CURRENT_BINARY_DIR}/hardware.asc)
set(PNR_RPT   ${CMAKE_CURRENT_BINARY_DIR}/hardware.rpt)
set(BIT_BIN   ${CMAKE_CURRENT_BINARY_DIR}/hardware.bin)

set(YOSYS_SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/synth.ys)
set(YOSYS_FILE_LIST "")
foreach(src IN LISTS ADDRDECODE_SRCS)
    string(APPEND YOSYS_FILE_LIST "\"${src}\" ")
endforeach()
# Generate a yosys script at configure time (handles spaces in paths cleanly).
file(WRITE ${YOSYS_SCRIPT} "read_verilog -sv ${YOSYS_FILE_LIST}\n")
file(APPEND ${YOSYS_SCRIPT} "synth_ice40 -top addr_decoder -json \"${SYNTH_JSON}\"\n")

# Target: synthesize to JSON with yosys (SystemVerilog enabled).
add_custom_command(
    OUTPUT ${SYNTH_JSON}
    COMMAND yosys -q -s ${YOSYS_SCRIPT}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${ADDRDECODE_SRCS}
    COMMENT "Running yosys (addr_decoder -> JSON)"
    VERBATIM
)
add_custom_target(synth_json DEPENDS ${SYNTH_JSON})

# Target: place and route with nextpnr-ice40.
add_custom_command(
    OUTPUT ${PNR_ASC} ${PNR_RPT}
    COMMAND nextpnr-ice40 --${FPGA_DEVICE} --package ${FPGA_PACKAGE} --json ${SYNTH_JSON} --pcf ${FPGA_PCF} --asc ${PNR_ASC} --report ${PNR_RPT} -q
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${SYNTH_JSON} ${FPGA_PCF}
    COMMENT "Running nextpnr-ice40 (place & route)"
    VERBATIM
)
add_custom_target(pnr DEPENDS ${PNR_ASC} ${PNR_RPT})
add_dependencies(pnr synth_json)

# Target: pack bitstream with icepack.
add_custom_command(
    OUTPUT ${BIT_BIN}
    COMMAND icepack ${PNR_ASC} ${BIT_BIN}
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    DEPENDS ${PNR_ASC}
    COMMENT "Packing bitstream (icepack)"
    VERBATIM
)
add_custom_target(bitstream ALL DEPENDS ${BIT_BIN})
add_dependencies(bitstream pnr)

# Convenience target to clean generated FPGA outputs.
add_custom_target(fpga_clean
    COMMAND ${CMAKE_COMMAND} -E rm -f ${SYNTH_JSON} ${PNR_ASC} ${PNR_RPT} ${BIT_BIN}
    COMMENT "Removing generated FPGA build artifacts"
)
