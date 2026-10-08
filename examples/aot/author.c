/* Equivalent typed C author for author.zig and toolchain.star. */
#include "compiler.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static nbc_view text(const char *value) {
    return (nbc_view){(const uint8_t *)value, strlen(value)};
}

static int check(nbc_builder *builder, int32_t status) {
    if (status == NBC_OK) return 0;
    nbc_view message = {0};
    if (nbc_last_error(builder, &message) == NBC_OK) {
        fprintf(stderr, "authoring: %.*s\n", (int)message.len, message.data);
    }
    return -1;
}

static int populate(nbc_builder *builder, nbc_view wasm, uint32_t version) {
    if (check(builder, nbc_add_library(builder, text("environment"), wasm))) return -1;
    if (check(builder, nbc_add_input(builder, text("sdk"), text("stable")))) return -1;
    if (check(builder, nbc_add_resource(builder, text("environment"), text("toolchain.env"))))
        return -1;
    if (check(builder, nbc_add_instance(
            builder, text("environment"), text("environment"), version)))
        return -1;
    if (check(builder, nbc_bind(builder, text("environment"), NBC_INPUT, text("sdk")))) return -1;
    if (check(builder, nbc_bind(builder, text("environment"), NBC_RESOURCE, text("environment"))))
        return -1;
    if (version == 2) {
        const char *owners[] = {"", "environment"};
        for (size_t i = 0; i < 2; ++i) {
            if (check(builder, nbc_add_migration(
                    builder, text(owners[i]), text("upgrade-1-2"), 1, 2)))
                return -1;
        }
    }
    return 0;
}

static int generate(const char *path, nbc_view wasm, uint32_t version) {
    nbc_builder *builder = NULL;
    int32_t status = nbc_create(
        NBC_ABI_VERSION, text("example.toolchain"), version, version, &builder);
    if (status != NBC_OK) return 1;
    nbc_buffer output = {0};
    int result = populate(builder, wasm, version);
    if (result == 0) result = check(builder, nbc_emit(builder, &output));
    if (result == 0) {
        FILE *file = fopen(path, "wbx");
        if (file == NULL) result = -1;
        else {
            if (fwrite(output.data, 1, output.len, file) != output.len) result = -1;
            if (fclose(file) != 0) result = -1;
        }
    }
    nbc_buffer_free(&output);
    nbc_destroy(builder);
    return result == 0 ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc != 4 || (strcmp(argv[3], "1") && strcmp(argv[3], "2"))) return 2;
    FILE *file = fopen(argv[1], "rb");
    if (file == NULL) return 1;
    unsigned char wasm[256 * 1024 + 1];
    size_t length = fread(wasm, 1, sizeof(wasm), file);
    int read_failed = ferror(file);
    int close_failed = fclose(file);
    if (read_failed || close_failed || length == sizeof(wasm)) return 1;
    return generate(argv[2], (nbc_view){wasm, length}, (uint32_t)(argv[3][0] - '0'));
}
