/* Featherview's stand-in for the header libjxl's CMake generates; libjxl is linked statically. */
#ifndef JXL_EXPORT_H
#define JXL_EXPORT_H

#define JXL_EXPORT
#define JXL_NO_EXPORT
#define JXL_DEPRECATED __attribute__((__deprecated__))
#define JXL_DEPRECATED_EXPORT JXL_EXPORT JXL_DEPRECATED
#define JXL_DEPRECATED_NO_EXPORT JXL_NO_EXPORT JXL_DEPRECATED

#endif /* JXL_EXPORT_H */
