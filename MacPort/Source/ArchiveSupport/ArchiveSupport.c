#include "ArchiveSupport.h"
#include "LibArchiveAPI.h"
#include <sys/stat.h>
#include <sys/fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define AABlockSize (1024 * 1024)

typedef struct { int64_t Offset; ssize_t Count; } AARead;
typedef struct { size_t Step; int64_t Written; } AAOutput;
typedef struct { char *Value; int Directory; } AAPath;
typedef struct {
    AARead *Reads;
    size_t ReadCount, ReadCapacity;
    AAOutput *Outputs;
    size_t OutputCount, OutputCapacity;
    size_t *LastUse, *Heads, *Next;
    size_t BlockCount;
    AAPath *Paths;
    size_t PathCount, PathCapacity;
    struct stat Identity;
} AASchedule;
typedef struct {
    int File;
    int Reclaim;
    int64_t Offset;
    size_t Step;
    AASchedule *Schedule;
    char Buffer[AABlockSize];
} AAInput;

static int AAFail(char *Error, size_t Length, const char *Message) {
    if (Length) snprintf(Error, Length, "%s", Message ? Message : "Could not read the archive.");
    return -1;
}

static int AAGrow(void **Array, size_t *Capacity, size_t Count, size_t ElementSize) {
    if (Count < *Capacity) return 0;
    size_t NewCapacity = *Capacity ? *Capacity * 2 : 128;
    if (NewCapacity > 4000000 || NewCapacity > SIZE_MAX / ElementSize) return -1;
    void *NewArray = realloc(*Array, NewCapacity * ElementSize);
    if (!NewArray) return -1;
    *Array = NewArray; *Capacity = NewCapacity;
    return 0;
}

static int64_t AASeek(struct archive *Archive, void *Context, int64_t Offset, int Origin) {
    AAInput *Input = Context;
    if (Origin != SEEK_SET && Origin != SEEK_CUR && Origin != SEEK_END) return -30;
    int64_t Base = Origin == SEEK_SET ? 0 : Origin == SEEK_CUR ? Input->Offset : Input->Schedule->Identity.st_size;
    if ((Offset > 0 && Base > INT64_MAX - Offset) || (Offset < 0 && (Offset == INT64_MIN || Base < -Offset)) || Base + Offset < 0) {
        archive_set_error(Archive, EINVAL, "Invalid archive seek."); return -30;
    }
    Input->Offset = Base + Offset;
    return Input->Offset;
}

static ssize_t AAReadSource(struct archive *Archive, void *Context, const void **Buffer) {
    AAInput *Input = Context;
    AASchedule *Schedule = Input->Schedule;
    size_t Step = ++Input->Step;
    if (Input->Reclaim) {
        if (Step > Schedule->ReadCount || Schedule->Reads[Step - 1].Offset != Input->Offset) {
            archive_set_error(Archive, EINVAL, "The archive read plan changed."); return -1;
        }
        for (size_t Block = Schedule->Heads[Step]; Block != SIZE_MAX; Block = Schedule->Next[Block]) {
            fpunchhole_t Hole = {0};
            Hole.fp_offset = Block * AABlockSize; Hole.fp_length = AABlockSize;
            if (fcntl(Input->File, F_PUNCHHOLE, &Hole)) {
                archive_set_error(Archive, errno, "Could not reclaim consumed archive blocks."); return -1;
            }
        }
    }
    ssize_t Count;
    do { Count = pread(Input->File, Input->Buffer, AABlockSize, Input->Offset); } while (Count < 0 && errno == EINTR);
    if (Count < 0) { archive_set_error(Archive, errno, "Could not read archive data."); return -1; }
    if (Input->Reclaim) {
        if (Count != Schedule->Reads[Step - 1].Count) { archive_set_error(Archive, EINVAL, "The archive changed during extraction."); return -1; }
    } else {
        if (AAGrow((void **)&Schedule->Reads, &Schedule->ReadCapacity, Schedule->ReadCount, sizeof(AARead))) {
            archive_set_error(Archive, ENOMEM, "The archive needs too much read-plan memory."); return -1;
        }
        Schedule->Reads[Schedule->ReadCount++] = (AARead){Input->Offset, Count};
        if (Count > 0) {
            size_t First = Input->Offset / AABlockSize;
            size_t Last = (Input->Offset + Count - 1) / AABlockSize;
            for (size_t Block = First; Block <= Last && Block < Schedule->BlockCount; Block++) Schedule->LastUse[Block] = Step;
        }
    }
    Input->Offset += Count;
    *Buffer = Input->Buffer;
    return Count;
}

static int AASafePath(const char *Raw, char *Path) {
    if (!Raw || strlen(Raw) >= PATH_MAX || Raw[0] == '/' || Raw[0] == '\\') return -1;
    strcpy(Path, Raw);
    for (char *Position = Path; *Position; Position++) if (*Position == '\\') *Position = '/';
    if (strlen(Path) > 1 && Path[1] == ':') return -1;
    char Copy[PATH_MAX]; strcpy(Copy, Path);
    char *Save, *Component = strtok_r(Copy, "/", &Save);
    Path[0] = 0;
    while (Component) {
        if (!strcmp(Component, "..")) return -1;
        if (strcmp(Component, ".")) {
            if (Path[0]) strcat(Path, "/");
            strcat(Path, Component);
        }
        Component = strtok_r(NULL, "/", &Save);
    }
    return 0;
}

static int AAOpenOutput(int Root, const char *Path, int Directory, mode_t Mode) {
    char Copy[PATH_MAX]; strcpy(Copy, Path);
    int Parent = dup(Root);
    if (Parent < 0) return -1;
    char *Save, *Component = strtok_r(Copy, "/", &Save);
    while (Component) {
        char *Next = strtok_r(NULL, "/", &Save);
        if (Next || Directory) {
            if (mkdirat(Parent, Component, 0755) && errno != EEXIST) { close(Parent); return -1; }
            int Child = openat(Parent, Component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            close(Parent);
            if (Child < 0) return -1;
            Parent = Child;
        } else {
            int File = openat(Parent, Component, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, (Mode & 0755) | 0600);
            close(Parent); return File;
        }
        Component = Next;
    }
    return Parent;
}

static int AARun(const char *Source, const char *Destination, int Reclaim, AASchedule *Schedule,
                 AAArchivePlan *Plan, char *Error, size_t ErrorSize) {
    int Result = -1, Root = -1, Output = -1;
    AAInput *Input = calloc(1, sizeof(AAInput));
    char *Data = malloc(AABlockSize);
    if (!Input || !Data) { free(Input); free(Data); return AAFail(Error, ErrorSize, "Not enough memory to read the archive."); }
    Input->File = open(Source, (Reclaim ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC);
    Input->Reclaim = Reclaim; Input->Schedule = Schedule;
    struct archive *Reader = archive_read_new();
    struct stat Identity;
    if (Input->File < 0 || !Reader || fstat(Input->File, &Identity) || !S_ISREG(Identity.st_mode)) {
        AAFail(Error, ErrorSize, "Could not open the archive."); goto Cleanup;
    }
    if (!Reclaim) {
        Schedule->Identity = Identity;
        Schedule->BlockCount = Identity.st_size / AABlockSize;
        if (Schedule->BlockCount > 4000000) { AAFail(Error, ErrorSize, "The archive is too large for space-saving extraction."); goto Cleanup; }
        Schedule->LastUse = calloc(Schedule->BlockCount + 1, sizeof(size_t));
        if (!Schedule->LastUse) { AAFail(Error, ErrorSize, "Could not allocate the archive read plan."); goto Cleanup; }
    } else if (Identity.st_ino != Schedule->Identity.st_ino || Identity.st_dev != Schedule->Identity.st_dev ||
               Identity.st_size != Schedule->Identity.st_size ||
               Identity.st_mtimespec.tv_sec != Schedule->Identity.st_mtimespec.tv_sec ||
               Identity.st_mtimespec.tv_nsec != Schedule->Identity.st_mtimespec.tv_nsec) {
        AAFail(Error, ErrorSize, "The archive changed after validation."); goto Cleanup;
    }
    archive_read_support_filter_all(Reader);
    archive_read_support_format_all(Reader);
    archive_read_add_passphrase(Reader, "steamrip.com");
    archive_read_set_seek_callback(Reader, AASeek);
    if (archive_read_open(Reader, Input, NULL, AAReadSource, NULL)) { AAFail(Error, ErrorSize, archive_error_string(Reader)); goto Cleanup; }
    if (Destination) {
        Root = open(Destination, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (Root < 0) { AAFail(Error, ErrorSize, "Could not open the extraction folder."); goto Cleanup; }
    }
    int64_t Written = 0, Entries = 0;
    struct archive_entry *Entry;
    int Status;
    while ((Status = archive_read_next_header(Reader, &Entry)) == 0) {
        char Path[PATH_MAX];
        mode_t Type = archive_entry_filetype(Entry);
        if (++Entries > 1000000 || AASafePath(archive_entry_pathname(Entry), Path) ||
            archive_entry_symlink(Entry) || archive_entry_hardlink(Entry) ||
            (Type != 0100000 && Type != 0040000) || (!Path[0] && Type != 0040000)) {
            AAFail(Error, ErrorSize, "The archive contains an unsafe path, link, special file, or too many entries."); goto Cleanup;
        }
        if (!Reclaim && Path[0]) {
            if (AAGrow((void **)&Schedule->Paths, &Schedule->PathCapacity, Schedule->PathCount, sizeof(AAPath))) {
                AAFail(Error, ErrorSize, "Could not validate archive filenames."); goto Cleanup;
            }
            char *Copy = strdup(Path);
            if (!Copy) { AAFail(Error, ErrorSize, "Could not validate archive filenames."); goto Cleanup; }
            Schedule->Paths[Schedule->PathCount++] = (AAPath){Copy, Type == 0040000};
        }
        if (Root >= 0 && Path[0]) {
            Output = AAOpenOutput(Root, Path, Type == 0040000, archive_entry_perm(Entry));
            if (Output < 0) { AAFail(Error, ErrorSize, "Could not create an archive entry. Check for duplicate names or unsafe paths."); goto Cleanup; }
        }
        ssize_t Count;
        while ((Count = archive_read_data(Reader, Data, AABlockSize)) > 0) {
            if (Written > INT64_MAX - Count) { AAFail(Error, ErrorSize, "Archive size overflow."); goto Cleanup; }
            Written += Count;
            if (!Reclaim) {
                if (AAGrow((void **)&Schedule->Outputs, &Schedule->OutputCapacity, Schedule->OutputCount, sizeof(AAOutput))) {
                    AAFail(Error, ErrorSize, "The archive needs too much extraction-plan memory."); goto Cleanup;
                }
                Schedule->Outputs[Schedule->OutputCount++] = (AAOutput){Input->Step, Written};
            }
            if (Output >= 0) {
                ssize_t Position = 0;
                while (Position < Count) {
                    ssize_t Amount = write(Output, Data + Position, Count - Position);
                    if (Amount < 0 && errno == EINTR) continue;
                    if (Amount <= 0) { AAFail(Error, ErrorSize, "Could not write extracted data. Check free space."); goto Cleanup; }
                    Position += Amount;
                }
            }
        }
        if (Count < 0) { AAFail(Error, ErrorSize, archive_error_string(Reader)); goto Cleanup; }
        if (Output >= 0) {
            if (fsync(Output) && errno != EINVAL) { AAFail(Error, ErrorSize, "Could not flush the extracted file."); goto Cleanup; }
            close(Output); Output = -1;
        }
    }
    if (Status != 1 || !Entries) { AAFail(Error, ErrorSize, archive_error_string(Reader)); goto Cleanup; }
    if (Plan) { Plan->ExpandedBytes = Written; Plan->Entries = Entries; }
    Result = 0;
Cleanup:
    if (Output >= 0) close(Output);
    if (Root >= 0) close(Root);
    if (Reader) archive_read_free(Reader);
    if (Input->File >= 0) close(Input->File);
    free(Input); free(Data); return Result;
}

static int AAComparePaths(const void *Left, const void *Right) {
    return strcasecmp(((const AAPath *)Left)->Value, ((const AAPath *)Right)->Value);
}

static int AABuildSchedule(AASchedule *Schedule, AAArchivePlan *Plan) {
    qsort(Schedule->Paths, Schedule->PathCount, sizeof(AAPath), AAComparePaths);
    for (size_t Index = 1; Index < Schedule->PathCount; Index++) {
        AAPath Previous = Schedule->Paths[Index - 1], Current = Schedule->Paths[Index];
        size_t Length = strlen(Previous.Value);
        if ((!strcasecmp(Previous.Value, Current.Value) && (!Previous.Directory || !Current.Directory)) ||
            (!Previous.Directory && strlen(Current.Value) > Length && !strncasecmp(Previous.Value, Current.Value, Length) && Current.Value[Length] == '/')) return -1;
    }
    for (size_t Index = 0; Index < Schedule->PathCount; Index++) {
        char Prefix[PATH_MAX]; strcpy(Prefix, Schedule->Paths[Index].Value);
        for (char *Position = Prefix; *Position; Position++) {
            if (*Position != '/') continue;
            *Position = 0;
            AAPath Key = {Prefix, 0};
            AAPath *Parent = bsearch(&Key, Schedule->Paths, Schedule->PathCount, sizeof(AAPath), AAComparePaths);
            *Position = '/';
            if (Parent && !Parent->Directory) return -1;
        }
    }
    Schedule->Heads = malloc((Schedule->ReadCount + 2) * sizeof(size_t));
    Schedule->Next = malloc((Schedule->BlockCount + 1) * sizeof(size_t));
    int64_t *Released = calloc(Schedule->ReadCount + 2, sizeof(int64_t));
    if (!Schedule->Heads || !Schedule->Next || !Released) { free(Released); return -1; }
    memset(Schedule->Heads, 255, (Schedule->ReadCount + 2) * sizeof(size_t));
    for (size_t Block = 0; Block < Schedule->BlockCount; Block++) {
        size_t Step = Schedule->LastUse[Block] + 1;
        if (Step == 1) continue;
        Schedule->Next[Block] = Schedule->Heads[Step]; Schedule->Heads[Step] = Block;
        Released[Step] += AABlockSize;
    }
    for (size_t Step = 1; Step < Schedule->ReadCount + 2; Step++) Released[Step] += Released[Step - 1];
    Plan->AdditionalBytes = 0;
    for (size_t Index = 0; Index < Schedule->OutputCount; Index++) {
        AAOutput Output = Schedule->Outputs[Index];
        int64_t Required = Output.Written - Released[Output.Step];
        if (Required > Plan->AdditionalBytes) Plan->AdditionalBytes = Required;
    }
    free(Released); return 0;
}

static void AAFreeSchedule(AASchedule *Schedule) {
    free(Schedule->Reads); free(Schedule->Outputs); free(Schedule->LastUse); free(Schedule->Heads); free(Schedule->Next);
    for (size_t Index = 0; Index < Schedule->PathCount; Index++) free(Schedule->Paths[Index].Value);
    free(Schedule->Paths);
}

int AAArchiveInspect(const char *Source, AAArchivePlan *Plan, char *Error, size_t ErrorSize) {
    AASchedule Schedule = {0};
    int Result = AARun(Source, NULL, 0, &Schedule, Plan, Error, ErrorSize);
    if (!Result && AABuildSchedule(&Schedule, Plan)) Result = AAFail(Error, ErrorSize, "Could not allocate the archive read plan.");
    AAFreeSchedule(&Schedule); return Result;
}

int AAArchiveExtract(const char *Source, const char *Destination, int Reclaim, char *Error, size_t ErrorSize) {
    AASchedule Schedule = {0}; AAArchivePlan Plan = {0};
    int Result = 0;
    if (Reclaim) {
        Result = AARun(Source, NULL, 0, &Schedule, &Plan, Error, ErrorSize);
        if (!Result && AABuildSchedule(&Schedule, &Plan)) Result = AAFail(Error, ErrorSize, "Could not allocate the archive read plan.");
    }
    if (!Result) Result = AARun(Source, Destination, Reclaim, &Schedule, NULL, Error, ErrorSize);
    AAFreeSchedule(&Schedule); return Result;
}

int AACanReclaim(const char *Directory) {
    char Path[PATH_MAX];
    int Length = snprintf(Path, sizeof(Path), "%s/.ascendara-space-test-XXXXXX", Directory);
    if (Length < 0 || (size_t)Length >= sizeof(Path)) return 0;
    int File = mkstemp(Path);
    if (File < 0) return 0;
    unlink(Path);
    char *Data = calloc(1, AABlockSize); int Result = 0;
    if (Data && write(File, Data, AABlockSize) == AABlockSize) {
        fpunchhole_t Hole = {0}; Hole.fp_length = AABlockSize;
        Result = fcntl(File, F_PUNCHHOLE, &Hole) == 0;
    }
    free(Data); close(File); return Result;
}

int AAArchiveSize(const char *Source, int64_t *Bytes, char *Error, size_t ErrorSize) {
    struct archive *Reader = archive_read_new();
    if (!Reader) return AAFail(Error, ErrorSize, "Could not inspect the archive.");
    archive_read_support_filter_all(Reader); archive_read_support_format_all(Reader);
    archive_read_add_passphrase(Reader, "steamrip.com");
    int Result = -1;
    if (archive_read_open_filename(Reader, Source, AABlockSize)) { AAFail(Error, ErrorSize, archive_error_string(Reader)); goto Cleanup; }
    int Status; int64_t Total = 0; struct archive_entry *Entry;
    while ((Status = archive_read_next_header(Reader, &Entry)) == 0) {
        int64_t Length = archive_entry_size(Entry);
        if (Length < 0 || Total > INT64_MAX - Length) { AAFail(Error, ErrorSize, "The archive's expanded size is invalid."); goto Cleanup; }
        Total += Length;
    }
    if (Status != 1) { AAFail(Error, ErrorSize, archive_error_string(Reader)); goto Cleanup; }
    *Bytes = Total; Result = 0;
Cleanup:
    archive_read_free(Reader); return Result;
}
