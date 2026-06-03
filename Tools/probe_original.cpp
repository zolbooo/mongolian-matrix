#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

struct Vertex {
    uint16_t x;
    uint16_t y;
    uint16_t z;
    uint8_t tx;
    uint8_t ty;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

static uint64_t deterministicState = 0x123456789abcdef0ULL;
static int deterministicLogRemaining = 0;
static int deterministicCallIndex = 0;

extern "C" uint32_t deterministicArc4Random() {
    deterministicState = deterministicState * 6364136223846793005ULL + 1442695040888963407ULL;
    uint32_t value = static_cast<uint32_t>(deterministicState >> 32);
    if (deterministicLogRemaining > 0) {
        fprintf(stderr, "rng %d arc4random -> %u\n", ++deterministicCallIndex, value);
        --deterministicLogRemaining;
    }
    return value;
}

extern "C" uint32_t deterministicArc4RandomUniform(uint32_t upperBound) {
    if (upperBound == 0) {
        return 0;
    }
    uint32_t raw = deterministicArc4Random();
    uint32_t value = raw % upperBound;
    if (deterministicLogRemaining > 0) {
        fprintf(stderr, "rng %d uniform(%u) raw=%u -> %u\n", deterministicCallIndex, upperBound, raw, value);
    }
    return value;
}

static uintptr_t imageBaseForPath(const char *path) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; ++i) {
        const char *name = _dyld_get_image_name(i);
        if (name && strcmp(name, path) == 0) {
            return (uintptr_t)_dyld_get_image_header(i);
        }
    }
    fprintf(stderr, "loaded image not found for %s\n", path);
    exit(2);
}

static void patchPointer(uintptr_t address, void *replacement) {
    uintptr_t pageSize = static_cast<uintptr_t>(getpagesize());
    uintptr_t page = address & ~(pageSize - 1);
    kern_return_t result = vm_protect(mach_task_self(), page, pageSize, false, VM_PROT_READ | VM_PROT_WRITE);
    if (result != KERN_SUCCESS) {
        fprintf(stderr, "vm_protect write failed at 0x%llx: %d\n", (unsigned long long)address, result);
        exit(2);
    }
    *reinterpret_cast<void **>(address) = replacement;
    result = vm_protect(mach_task_self(), page, pageSize, false, VM_PROT_READ | VM_PROT_WRITE);
    if (result != KERN_SUCCESS) {
        fprintf(stderr, "vm_protect restore failed at 0x%llx: %d\n", (unsigned long long)address, result);
        exit(2);
    }
}

template <typename T>
static T at(uintptr_t base, uintptr_t offset) {
    return reinterpret_cast<T>(base + offset);
}

static uint16_t u16(const uint8_t *p, size_t offset) {
    uint16_t v;
    memcpy(&v, p + offset, sizeof(v));
    return v;
}

static int32_t i32(const uint8_t *p, size_t offset) {
    int32_t v;
    memcpy(&v, p + offset, sizeof(v));
    return v;
}

static uint64_t u64(const uint8_t *p, size_t offset) {
    uint64_t v;
    memcpy(&v, p + offset, sizeof(v));
    return v;
}

static float f32(const uint8_t *p, size_t offset) {
    float v;
    memcpy(&v, p + offset, sizeof(v));
    return v;
}

static double f64(const uint8_t *p, size_t offset) {
    double v;
    memcpy(&v, p + offset, sizeof(v));
    return v;
}

static const uint8_t *ptr(const uint8_t *p, size_t offset) {
    uintptr_t v;
    memcpy(&v, p + offset, sizeof(v));
    return reinterpret_cast<const uint8_t *>(v);
}

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "/Users/flame/Library/Screen Savers/Matrix.saver.backup-20260528-174140/Contents/MacOS/Matrix";
    int ticks = argc > 2 ? atoi(argv[2]) : 1;
    float width = argc > 3 ? atof(argv[3]) : 320.0f;
    float height = argc > 4 ? atof(argv[4]) : 200.0f;
    float scale = argc > 5 ? atof(argv[5]) : 1.0f;
    bool deterministic = argc > 6;
    if (deterministic) {
        deterministicState = strtoull(argv[6], nullptr, 0);
    }
    if (argc > 7) {
        deterministicLogRemaining = atoi(argv[7]);
    }

    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }

    uintptr_t base = imageBaseForPath(path);
    if (deterministic) {
        patchPointer(base + 0x140d8, reinterpret_cast<void *>(&deterministicArc4Random));
        patchPointer(base + 0x140e0, reinterpret_cast<void *>(&deterministicArc4RandomUniform));
    }
    const uint8_t *image = reinterpret_cast<const uint8_t *>(base);
    auto ctor = at<void (*)(void *)>(base, 0x8d24);
    auto dtor = at<void (*)(void *)>(base, 0x8e98);
    auto init = at<void (*)(void *, float, float, float)>(base, 0x8ed8);
    auto tick = at<void (*)(void *)>(base, 0x9248);
    auto drawBufferSize = at<uint64_t (*)(void *)>(base, 0x99ac);
    auto draw = at<void (*)(void *, Vertex *)>(base, 0x99bc);

    alignas(16) uint8_t core[0x200];
    memset(core, 0, sizeof(core));
    ctor(core);
    init(core, width, height, scale);
    for (int i = 0; i < ticks; ++i) {
        tick(core);
    }

    uint64_t bytes = drawBufferSize(core);
    size_t count = bytes / sizeof(Vertex);
    Vertex *vertices = static_cast<Vertex *>(calloc(count ? count : 1, sizeof(Vertex)));
    draw(core, vertices);

    printf("core bytes=%llu vertexCount=%zu\n", (unsigned long long)bytes, count);
    printf("ages=%d,%d,%d,%d stride=%d constBED8=%f\n",
           i32(image, 0x157b0), i32(image, 0x157b4), i32(image, 0x157b8), i32(image, 0x157bc),
           i32(image, 0xbee8), f64(image, 0xbed8));
    printf("cursorConstants dBEB8=%f dBEC0=%f dBEC8=%f dBED0=%f fBEE0=%f\n",
           f64(image, 0xbeb8), f64(image, 0xbec0), f64(image, 0xbec8), f64(image, 0xbed0), f32(image, 0xbee0));
    printf("dims width=%f height=%f scale=%f rows=%d cols=%d cursorGroups=%d active=%d tick=%d fadeState=%d rotate=%f fadeDistance=%f cellSize=%llu drawBytes=%llu\n",
           width, height, scale,
           (int)(int16_t)u16(core, 0x20),
           (int)(int16_t)u16(core, 0x22),
           i32(core, 0x80),
           i32(core, 0xa4),
           i32(core, 0x24),
           i32(core, 0x2c),
           f32(core, 0xa0),
           f64(core, 0x58),
           (unsigned long long)u64(core, 0x18),
           (unsigned long long)u64(core, 0xb0));
    printf("flags rotate=%u 3DFade=%u minorInstability=%u colors=(%.4f %.4f %.4f),(%.4f %.4f %.4f),(%.4f %.4f %.4f)\n",
           core[0x30], core[0x31], core[0x32],
           f32(core, 0x34), f32(core, 0x38), f32(core, 0x3c),
           f32(core, 0x40), f32(core, 0x44), f32(core, 0x48),
           f32(core, 0x4c), f32(core, 0x50), f32(core, 0x54));

    size_t vertexLimit = 16;
    if (const char *limit = getenv("MATRIX_DEBUG_VERTEX_LIMIT")) {
        vertexLimit = strtoull(limit, nullptr, 0);
    }
    for (size_t i = 0; i < count && i < vertexLimit; ++i) {
        printf("v%zu pos=(%u %u %u) tile=(%u %u) color=(%u %u %u %u)\n",
               i,
               vertices[i].x, vertices[i].y, vertices[i].z,
               vertices[i].tx, vertices[i].ty,
               vertices[i].r, vertices[i].g, vertices[i].b, vertices[i].a);
    }

    const uint8_t *cells = ptr(core, 0x68);
    const uint8_t *cellEnd = ptr(core, 0x70);
    const uint8_t *cursors = ptr(core, 0x88);
    const uint8_t *cursorEnd = ptr(core, 0x90);
    size_t cellCount = cells && cellEnd ? (cellEnd - cells) / 0x40 : 0;
    size_t cursorCount = cursors && cursorEnd ? (cursorEnd - cursors) / 0x38 : 0;
    size_t cellLimit = 12;
    if (const char *limit = getenv("MATRIX_DEBUG_CELL_LIMIT")) {
        cellLimit = strtoull(limit, nullptr, 0);
    }
    printf("cellVector count=%zu cursorVector count=%zu\n", cellCount, cursorCount);
    for (size_t i = 0; i < cellCount && i < cellLimit; ++i) {
        const uint8_t *c = cells + i * 0x40;
        printf("cell%zu glyph=%u phase=%d t08=%d t0c=%d wait=%d age=%d f18=%.4f color=(%.4f %.4f %.4f %.4f)\n",
               i, c[0], i32(c, 4), i32(c, 8), i32(c, 0x0c), i32(c, 0x10), i32(c, 0x14),
               f32(c, 0x18), f32(c, 0x1c), f32(c, 0x20), f32(c, 0x24), f32(c, 0x28));
    }
    for (size_t i = 0; i < cursorCount && i < 8; ++i) {
        const uint8_t *c = cursors + i * 0x38;
        printf("cursor%zu row=%d col=%d phase=%d active=%d minCol=%d maxCol=%d textLen=%zu index=%d raw17=%d\n",
               i, (int)(int16_t)u16(c, 0), (int)(int16_t)u16(c, 2), i32(c, 4), c[0x14],
               i32(c, 0x0c), i32(c, 0x10), (size_t)c[0x17], i32(c, 0x18), (int)(int8_t)c[0x17]);
    }

    free(vertices);
    dtor(core);
    dlclose(handle);
    return 0;
}
