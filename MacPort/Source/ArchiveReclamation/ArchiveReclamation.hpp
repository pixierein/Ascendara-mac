#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <mutex>
#include <string>
#include <vector>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

class ArchiveReclamationState {
    static constexpr uint64_t BlockSize = 1024 * 1024;
    static constexpr uint64_t Magic = 0x415343504C414E31;
    struct Identity { uint64_t Device, Inode, Size, Seconds, Nanoseconds; };
    struct Source {
        int File;
        Identity Value;
        std::vector<uint64_t> LastUse;
    };
    struct Read { uint64_t SourceIndex, Offset, Requested, Count; };
    struct Output { uint64_t Step, Written; };
    struct Release { uint64_t Step, SourceIndex, Block; };
    struct Header { uint64_t Signature, SourceCount, ReadCount, ExpandedBytes, AdditionalBytes; };
    std::vector<Source> Sources;
    std::vector<Read> Reads;
    std::vector<Output> Outputs;
    std::vector<Release> Releases;
    std::mutex Lock;
    std::string Plan;
    bool Enabled = false;
    bool Replay = false;
    uint64_t Step = 0;
    uint64_t Written = 0;
    uint64_t Expanded = 0;
    size_t Released = 0;

    [[noreturn]] static void Fail(const char *Message) {
        fprintf(stderr, "Archive reclamation: %s\n", Message);
        _Exit(2);
    }

    static Identity Identify(int File) {
        struct stat Value;
        if (fstat(File, &Value) || !S_ISREG(Value.st_mode) || Value.st_nlink != 1 || Value.st_size <= 0)
            Fail("Each archive volume must be a nonempty regular file without hard links.");
        return {uint64_t(Value.st_dev), Value.st_ino, uint64_t(Value.st_size),
                uint64_t(Value.st_mtimespec.tv_sec), uint64_t(Value.st_mtimespec.tv_nsec)};
    }

    static bool Same(const Identity &Left, const Identity &Right) {
        return Left.Device == Right.Device && Left.Inode == Right.Inode && Left.Size == Right.Size &&
               Left.Seconds == Right.Seconds && Left.Nanoseconds == Right.Nanoseconds;
    }

    void BuildReleases() {
        for (size_t Index = 0; Index < Reads.size(); Index++) {
            const Read &Value = Reads[Index];
            if (Value.SourceIndex >= Sources.size()) Fail("Invalid archive read plan.");
            Source &Input = Sources[Value.SourceIndex];
            if (Value.Offset > Input.Value.Size || Value.Count > Input.Value.Size - Value.Offset || Value.Count > Value.Requested)
                Fail("Invalid archive read range.");
            if (!Value.Count) continue;
            uint64_t End = (Value.Offset + Value.Count - 1) / BlockSize;
            for (uint64_t Block = Value.Offset / BlockSize; Block <= End && Block < Input.LastUse.size(); Block++)
                Input.LastUse[Block] = Index + 1;
        }
        for (size_t Index = 0; Index < Sources.size(); Index++) {
            const Source &Input = Sources[Index];
            for (size_t Block = 0; Block < Input.LastUse.size(); Block++)
                if (Input.LastUse[Block]) Releases.push_back({Input.LastUse[Block], Index, Block});
        }
        std::sort(Releases.begin(), Releases.end(), [](const Release &Left, const Release &Right) { return Left.Step < Right.Step; });
    }

public:
    ArchiveReclamationState() {
        const char *Mode = getenv("ASCENDARA_ARCHIVE_MODE");
        if (!Mode) return;
        Enabled = true;
        Replay = !strcmp(Mode, "replay");
        if (!Replay && strcmp(Mode, "inspect")) Fail("Invalid extraction mode.");
        const char *Manifest = getenv("ASCENDARA_ARCHIVE_SOURCES");
        const char *PlanPath = getenv("ASCENDARA_ARCHIVE_PLAN");
        if (!Manifest || !PlanPath) Fail("The archive manifest or plan is missing.");
        Plan = PlanPath;
        std::ifstream Input(Manifest);
        if (!Input) Fail("Could not read the archive manifest.");
        std::string Path;
        uint64_t Blocks = 0;
        while (std::getline(Input, Path)) {
            if (Path.empty() || Path[0] != '/' || Sources.size() >= 4096) Fail("Invalid archive manifest.");
            int File = open(Path.c_str(), (Replay ? O_RDWR : O_RDONLY) | O_NOFOLLOW | O_CLOEXEC);
            if (File < 0) Fail("Could not open every archive volume.");
            Identity Value = Identify(File);
            for (const Source &Existing : Sources)
                if (Existing.Value.Device == Value.Device && Existing.Value.Inode == Value.Inode) Fail("Duplicate archive volume.");
            Blocks += Value.Size / BlockSize;
            if (Blocks > 4000000) Fail("The archive requires too much read-plan memory.");
            Sources.push_back({File, Value, std::vector<uint64_t>(Value.Size / BlockSize)});
        }
        if (Sources.empty()) Fail("The archive manifest is empty.");
        if (Replay) {
            std::ifstream Saved(Plan, std::ios::binary);
            Header Value = {};
            Saved.read(reinterpret_cast<char *>(&Value), sizeof(Value));
            if (!Saved || Value.Signature != Magic || Value.SourceCount != Sources.size() || Value.ReadCount > 4000000)
                Fail("Invalid archive plan.");
            for (const Source &Current : Sources) {
                Identity Expected = {};
                Saved.read(reinterpret_cast<char *>(&Expected), sizeof(Expected));
                if (!Saved || !Same(Current.Value, Expected)) Fail("An archive volume changed after validation.");
            }
            Reads.resize(Value.ReadCount);
            Saved.read(reinterpret_cast<char *>(Reads.data()), Reads.size() * sizeof(Read));
            if (!Saved || Saved.peek() != std::char_traits<char>::eof()) Fail("The archive plan is incomplete.");
            Expanded = Value.ExpandedBytes;
            BuildReleases();
        }
    }

    ~ArchiveReclamationState() {
        if (!Enabled) return;
        if (Replay) {
            if (Step != Reads.size() || Written != Expanded) Fail("The extraction did not complete its validated plan.");
        } else {
            BuildReleases();
            uint64_t Required = 0, Reclaimed = 0;
            size_t Position = 0;
            for (const Output &Value : Outputs) {
                while (Position < Releases.size() && Releases[Position].Step < Value.Step) { Reclaimed += BlockSize; Position++; }
                if (Value.Written > Reclaimed) Required = std::max(Required, Value.Written - Reclaimed);
            }
            std::ofstream Saved(Plan, std::ios::binary | std::ios::trunc);
            Header Value = {Magic, Sources.size(), Reads.size(), Written, Required};
            Saved.write(reinterpret_cast<const char *>(&Value), sizeof(Value));
            for (const Source &Current : Sources) Saved.write(reinterpret_cast<const char *>(&Current.Value), sizeof(Identity));
            Saved.write(reinterpret_cast<const char *>(Reads.data()), Reads.size() * sizeof(Read));
            Saved.close();
            if (!Saved) Fail("Could not save the archive read plan.");
            std::ofstream Summary(Plan + ".json");
            Summary << "{\"ExpandedBytes\":" << Written << ",\"AdditionalBytes\":" << Required << "}";
            Summary.close();
            if (!Summary) Fail("Could not save the archive space estimate.");
        }
        for (const Source &Value : Sources) close(Value.File);
    }

    ssize_t ReadSource(int File, void *Data, size_t Size) {
        if (!Enabled) return ::read(File, Data, Size);
        std::lock_guard<std::mutex> Guard(Lock);
        struct stat Current;
        if (fstat(File, &Current)) Fail("Could not identify an archive volume.");
        size_t Index = 0;
        while (Index < Sources.size() && (Sources[Index].Value.Device != uint64_t(Current.st_dev) || Sources[Index].Value.Inode != Current.st_ino)) Index++;
        if (Index == Sources.size()) Fail("The decoder requested a volume outside the archive manifest.");
        off_t Offset = lseek(File, 0, SEEK_CUR);
        if (Offset < 0) Fail("Could not locate the archive read position.");
        Step++;
        if (Replay) {
            if (Step > Reads.size()) Fail("The archive read plan changed.");
            const Read &Expected = Reads[Step - 1];
            if (Expected.SourceIndex != Index || Expected.Offset != uint64_t(Offset) || Expected.Requested != Size)
                Fail("The archive read plan changed.");
            while (Released < Releases.size() && Releases[Released].Step < Step) {
                const Release &Value = Releases[Released++];
                fpunchhole_t Hole = {};
                Hole.fp_offset = Value.Block * BlockSize; Hole.fp_length = BlockSize;
                if (fcntl(Sources[Value.SourceIndex].File, F_PUNCHHOLE, &Hole)) Fail("Could not reclaim consumed archive blocks.");
            }
        }
        ssize_t Count;
        do { Count = ::read(File, Data, Size); } while (Count < 0 && errno == EINTR);
        if (Count < 0) Fail("Could not read archive data.");
        if (Replay) {
            if (uint64_t(Count) != Reads[Step - 1].Count) Fail("An archive volume changed during extraction.");
        } else {
            if (Reads.size() >= 4000000) Fail("The archive requires too much read-plan memory.");
            Reads.push_back({Index, uint64_t(Offset), Size, uint64_t(Count)});
        }
        return Count;
    }

    ssize_t WriteOutput(int File, const void *Data, size_t Size) {
        if (!Enabled) return ::write(File, Data, Size);
        std::lock_guard<std::mutex> Guard(Lock);
        if (Written > uint64_t(INT64_MAX) - Size) Fail("The expanded archive size is too large.");
        if (!Replay) {
            if (lseek(File, Size, SEEK_CUR) < 0) Fail("Could not validate an output file.");
            Written += Size;
            if (Outputs.size() >= 4000000) Fail("The archive requires too much output-plan memory.");
            Outputs.push_back({Step, Written});
            return Size;
        }
        struct statvfs Space;
        if (fstatvfs(File, &Space) || static_cast<long double>(Space.f_bavail) * Space.f_frsize < Size + 16 * BlockSize)
            Fail("Not enough free space to continue extraction.");
        ssize_t Count = ::write(File, Data, Size);
        if (Count > 0) Written += Count;
        return Count;
    }
};

static ArchiveReclamationState &ArchiveReclamation() {
    static ArchiveReclamationState Value;
    return Value;
}

static ssize_t ArchiveRead(int File, void *Data, size_t Size) { return ArchiveReclamation().ReadSource(File, Data, Size); }
static ssize_t ArchiveWrite(int File, const void *Data, size_t Size) { return ArchiveReclamation().WriteOutput(File, Data, Size); }
