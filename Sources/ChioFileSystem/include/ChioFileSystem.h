#ifndef CHIO_FILE_SYSTEM_H
#define CHIO_FILE_SYSTEM_H
#include <stddef.h>
/* Private implementation bridge; the Chio product exports only Swift API. */
int chio_cache_try_lock(int descriptor);
void *chio_cache_directory_stream(int descriptor);
int chio_cache_next_name(void *stream, char *name, size_t capacity);
int chio_cache_close_stream(void *stream);
#endif
