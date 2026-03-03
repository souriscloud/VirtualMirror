#ifndef FAIRPLAY_PLAYFAIR_H
#define FAIRPLAY_PLAYFAIR_H

#include <stdint.h>
#include <stddef.h>

/// Handle FairPlay phase 1: given a mode byte (0-3),
/// writes a 142-byte response into out_response.
/// Returns 0 on success, -1 on error.
int fairplay_setup_phase1(uint8_t mode, uint8_t *out_response, size_t out_len);

/// Handle FairPlay phase 3: given the 164-byte request body,
/// writes a 32-byte response into out_response.
/// Returns 0 on success, -1 on error.
int fairplay_setup_phase3(const uint8_t *request, size_t request_len,
                          uint8_t *out_response, size_t out_len);

#endif /* FAIRPLAY_PLAYFAIR_H */
