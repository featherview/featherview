// Featherview's entry points into jxrlib: open from memory, decode the first frame, convert to 8 bits.
#include "CJPEGXR.h"
#include <stdlib.h>
#include <JXRGlue.h>

static int open_decoder(const void *data, size_t size, struct WMPStream **stream, PKImageDecode **decoder) {
    const uint8_t *bytes = data;
    // "II", 0xBC, then the version: the HD Photo / JPEG XR container.
    if (size < 4 || bytes[0] != 'I' || bytes[1] != 'I' || bytes[2] != 0xBC) return FVJXR_NOT_JXR;
    if (CreateWS_Memory(stream, (void *)data, size) != WMP_errSuccess) return FVJXR_NOT_JXR;
    if (PKImageDecode_Create_WMP(decoder) != WMP_errSuccess) {
        CloseWS_Memory(stream);
        return FVJXR_NOT_JXR;
    }
    if ((*decoder)->Initialize(*decoder, *stream) != WMP_errSuccess) {
        (*decoder)->Release(decoder);
        CloseWS_Memory(stream);
        return FVJXR_NOT_JXR;
    }
    return FVJXR_OK;
}

static void close_decoder(struct WMPStream **stream, PKImageDecode **decoder) {
    (*decoder)->Release(decoder);
    CloseWS_Memory(stream);
}

int fv_jxr_size(const void *data, size_t size, int *width, int *height) {
    struct WMPStream *stream = NULL;
    PKImageDecode *decoder = NULL;
    int result = open_decoder(data, size, &stream, &decoder);
    if (result != FVJXR_OK) return result;
    I32 w = 0, h = 0;
    decoder->GetSize(decoder, &w, &h);
    *width = w;
    *height = h;
    close_decoder(&stream, &decoder);
    return FVJXR_OK;
}

int fv_jxr_decode(const void *data, size_t size, size_t maxBytes, uint8_t **pixels, int *width, int *height,
                  int *channels, int *premultiplied, size_t *stride) {
    struct WMPStream *stream = NULL;
    PKImageDecode *decoder = NULL;
    PKFormatConverter *converter = NULL;
    uint8_t *buffer = NULL;
    int result = open_decoder(data, size, &stream, &decoder);
    if (result != FVJXR_OK) return result;

    PKPixelInfo source = {0};
    source.pGUIDPixFmt = &decoder->guidPixFormat;
    if (PixelFormatLookup(&source, LOOKUP_FORWARD) != WMP_errSuccess) { result = FVJXR_UNSUPPORTED; goto done; }

    // Ask for 8-bit RGBA, RGB or grey; jxrlib's converters take every other format there in one step.
    PKPixelFormatGUID target = GUID_PKPixelFormat24bppRGB;
    *channels = 3;
    *premultiplied = 0;
    if (source.grBit & PK_pixfmtPreMul) {
        target = GUID_PKPixelFormat32bppPRGBA;  // Office's HD Photo files store premultiplied BGRA
        *channels = 4;
        *premultiplied = 1;
    } else if (source.grBit & PK_pixfmtHasAlpha) {
        target = GUID_PKPixelFormat32bppRGBA;
        *channels = 4;
    } else if (source.cfColorFormat == Y_ONLY) {
        target = GUID_PKPixelFormat8bppGray;
        *channels = 1;
    } else if (decoder->WMP.wmiI.cfColorFormat == CMYK) {
        // The decoder itself turns CMYK into RGB when asked for it.
        decoder->WMP.wmiI.cfColorFormat = CF_RGB;
        decoder->guidPixFormat = target;
        decoder->WMP.wmiI.bRGB = 1;
        source.pGUIDPixFmt = &decoder->guidPixFormat;
        PixelFormatLookup(&source, LOOKUP_FORWARD);
    }

    decoder->WMP.wmiSCP.uAlphaMode = (source.grBit & PK_pixfmtHasAlpha) ? 2 : 0;
    decoder->WMP.wmiSCP.sbSubband = SB_ALL;
    decoder->WMP.wmiI.cfColorFormat = source.cfColorFormat;
    decoder->WMP.wmiI.bdBitDepth = source.bdBitDepth;
    decoder->WMP.wmiI.cBitsPerUnit = source.cbitUnit;
    decoder->WMP.wmiI.cThumbnailWidth = decoder->WMP.wmiI.cWidth;
    decoder->WMP.wmiI.cThumbnailHeight = decoder->WMP.wmiI.cHeight;
    decoder->WMP.wmiI.bSkipFlexbits = FALSE;
    decoder->WMP.wmiI.cROILeftX = 0;
    decoder->WMP.wmiI.cROITopY = 0;
    decoder->WMP.wmiI.cROIWidth = decoder->WMP.wmiI.cWidth;
    decoder->WMP.wmiI.cROIHeight = decoder->WMP.wmiI.cHeight;
    decoder->WMP.wmiI.cPostProcStrength = 0;
    decoder->WMP.wmiSCP.bVerbose = FALSE;

    if (PKCodecFactory_CreateFormatConverter(&converter) != WMP_errSuccess
        || converter->Initialize(converter, decoder, NULL, target) != WMP_errSuccess) {
        result = FVJXR_UNSUPPORTED;
        goto done;
    }

    PKRect rect = {0, 0, 0, 0};
    decoder->GetSize(decoder, &rect.Width, &rect.Height);
    if (rect.Width <= 0 || rect.Height <= 0) { result = FVJXR_CORRUPT; goto done; }
    // The converter works in place, so each row must hold the decoded pixels as well as the 8-bit ones.
    size_t unitBytes = (source.cbitUnit + 7) / 8;
    size_t bytesPerPixel = unitBytes > 4 ? unitBytes : 4;
    size_t rowBytes = ((size_t)rect.Width * bytesPerPixel + 127) & ~(size_t)127;
    if ((size_t)rect.Height > maxBytes / rowBytes) { result = FVJXR_TOO_BIG; goto done; }
    buffer = calloc((size_t)rect.Height, rowBytes);  // lazily zeroed pages: a false size claim costs nothing
    if (buffer == NULL) { result = FVJXR_TOO_BIG; goto done; }
    if (converter->Copy(converter, &rect, buffer, (U32)rowBytes) != WMP_errSuccess) {
        result = FVJXR_CORRUPT;
        goto done;
    }
    *pixels = buffer;
    buffer = NULL;
    *width = rect.Width;
    *height = rect.Height;
    *stride = rowBytes;

done:
    free(buffer);
    if (converter != NULL) converter->Release(&converter);
    close_decoder(&stream, &decoder);
    return result;
}
