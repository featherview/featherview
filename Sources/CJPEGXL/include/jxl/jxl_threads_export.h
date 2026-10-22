/* Featherview's stand-in for the header libjxl's CMake generates; libjxl is linked statically. */
#ifndef JXL_THREADS_EXPORT_H
#define JXL_THREADS_EXPORT_H

#define JXL_THREADS_EXPORT
#define JXL_THREADS_NO_EXPORT
#define JXL_THREADS_DEPRECATED __attribute__((__deprecated__))
#define JXL_THREADS_DEPRECATED_EXPORT JXL_THREADS_EXPORT JXL_THREADS_DEPRECATED
#define JXL_THREADS_DEPRECATED_NO_EXPORT JXL_THREADS_NO_EXPORT JXL_THREADS_DEPRECATED

#endif /* JXL_THREADS_EXPORT_H */
