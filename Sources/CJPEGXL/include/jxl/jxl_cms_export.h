/* Featherview's stand-in for the header libjxl's CMake generates; libjxl is linked statically. */
#ifndef JXL_CMS_EXPORT_H
#define JXL_CMS_EXPORT_H

#define JXL_CMS_EXPORT
#define JXL_CMS_NO_EXPORT
#define JXL_CMS_DEPRECATED __attribute__((__deprecated__))
#define JXL_CMS_DEPRECATED_EXPORT JXL_CMS_EXPORT JXL_CMS_DEPRECATED
#define JXL_CMS_DEPRECATED_NO_EXPORT JXL_CMS_NO_EXPORT JXL_CMS_DEPRECATED

#endif /* JXL_CMS_EXPORT_H */
