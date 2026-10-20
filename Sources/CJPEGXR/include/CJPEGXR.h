#ifndef CJPEGXR_H
#define CJPEGXR_H

#include <stddef.h>
#include <stdint.h>

/// Outcome of a call: 0 is success.
enum {
    FVJXR_OK = 0,
    FVJXR_NOT_JXR = 1,      ///< not a JPEG XR file, or a header jxrlib can't read
    FVJXR_UNSUPPORTED = 2,  ///< a pixel format we don't convert (n-channel, CMYK with alpha)
    FVJXR_CORRUPT = 3,      ///< decoding failed part way
    FVJXR_TOO_BIG = 4,      ///< the decode buffer would exceed `maxBytes`
};

/// The upright size of a JPEG XR (HD Photo, Windows Media Photo) file, from its header.
int fv_jxr_size(const void *data, size_t size, int *width, int *height);

/// Decodes the first frame to 8 bits per channel, top row first: `channels` is 1 (grey), 3 (RGB) or
/// 4 (RGBA; `premultiplied` says whether colour is multiplied by alpha). On success `*pixels` holds rows
/// `*stride` bytes apart; release it with `free`.
int fv_jxr_decode(const void *data, size_t size, size_t maxBytes, uint8_t **pixels, int *width, int *height,
                  int *channels, int *premultiplied, size_t *stride);

#endif
