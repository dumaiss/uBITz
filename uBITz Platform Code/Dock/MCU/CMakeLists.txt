cmake_minimum_required(VERSION 3.16)

# ESP-IDF project entry point. Builds the Dock MCU app and the uBITz enumerator
# component (source lives in src/).
set(PROJECT_PARTITION_TABLE "partitions.csv")
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(ubitz_dock_mcu)
