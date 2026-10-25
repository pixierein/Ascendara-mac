#ifndef AscendaraArchiveSupport
#define AscendaraArchiveSupport
#include <stdint.h>
#include <stddef.h>
typedef struct { int64_t ExpandedBytes; int64_t AdditionalBytes; int64_t Entries; } AAArchivePlan;
int AAArchiveInspect(const char *Source, AAArchivePlan *Plan, char *Error, size_t ErrorSize);
int AAArchiveExtract(const char *Source, const char *Destination, int Reclaim, char *Error, size_t ErrorSize);
int AACanReclaim(const char *Directory);
int AAArchiveSize(const char *Source, int64_t *Bytes, char *Error, size_t ErrorSize);
#endif
