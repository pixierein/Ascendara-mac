#ifndef AscendaraLibArchiveAPI
#define AscendaraLibArchiveAPI
#include <sys/types.h>
#include <stdint.h>
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_all(struct archive *);
int archive_read_add_passphrase(struct archive *, const char *);
int archive_read_set_seek_callback(struct archive *, int64_t (*)(struct archive *, void *, int64_t, int));
int archive_read_open(struct archive *, void *, int (*)(struct archive *, void *), ssize_t (*)(struct archive *, void *, const void **), int (*)(struct archive *, void *));
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_free(struct archive *);
void archive_set_error(struct archive *, int, const char *, ...);
const char *archive_error_string(struct archive *);
mode_t archive_entry_filetype(struct archive_entry *);
mode_t archive_entry_perm(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
#endif
