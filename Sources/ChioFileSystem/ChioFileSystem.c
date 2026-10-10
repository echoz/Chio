#include "ChioFileSystem.h"
#include <sys/file.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
int chio_cache_try_lock(int descriptor) {
    return flock(descriptor, LOCK_EX | LOCK_NB);
}
void *chio_cache_directory_stream(int descriptor) {
    int copy = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (copy < 0) return NULL;
    DIR *stream = fdopendir(copy);
    if (!stream) { int failure = errno; close(copy); errno = failure; }
    return stream;
}
int chio_cache_next_name(void *stream, char *name, size_t capacity) {
    errno = 0;
    struct dirent *entry = readdir((DIR *)stream);
    if (!entry) return errno == 0 ? 0 : -1;
    size_t length = strlen(entry->d_name);
    if (length >= capacity) { errno = ENAMETOOLONG; return -1; }
    memcpy(name, entry->d_name, length + 1);
    return 1;
}
int chio_cache_close_stream(void *stream) { return closedir((DIR *)stream); }
