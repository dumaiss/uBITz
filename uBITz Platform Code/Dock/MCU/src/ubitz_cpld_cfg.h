#pragma once
#include <stdint.h>
#include "esp_err.h"
#include "ubitz_enumerator.h"
#include "ubitz_pins.h"

esp_err_t ubitz_cpld_cfg_init(void);
void ubitz_cpld_program_decoder(const ubitz_decode_binding_t *wins, int count);
void ubitz_cpld_program_irq_router(const ubitz_irq_binding_t *irqs, int count);
