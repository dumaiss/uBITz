set(UBITZ_SRC_DIR "${CMAKE_CURRENT_LIST_DIR}/../src")

idf_component_register(
    SRCS
        "main.c"
        "${UBITZ_SRC_DIR}/ubitz_enumerator.c"
        "${UBITZ_SRC_DIR}/ubitz_cpld_cfg.c"
        "${UBITZ_SRC_DIR}/ubitz_monitor.c"
    INCLUDE_DIRS
        "."
        "${UBITZ_SRC_DIR}"
    REQUIRES
        driver
        esp_system
)
