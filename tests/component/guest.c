/* This consumer uses only upstream wit-bindgen generated declarations. */
#include "qualification.h"
#include <stdlib.h>
#include <string.h>

/* A freestanding failure path prevents a WASI proc_exit import. */
void abort(void) { __builtin_trap(); }

struct exports_niobium_qualification_guest_counter_t { uint32_t value; };

exports_niobium_qualification_guest_own_counter_t
exports_niobium_qualification_guest_constructor_counter(uint32_t value) {
    exports_niobium_qualification_guest_counter_t *counter = malloc(sizeof(*counter));
    if (!counter) abort();
    counter->value = value;
    return exports_niobium_qualification_guest_counter_new(counter);
}

uint32_t exports_niobium_qualification_guest_method_counter_value(
    exports_niobium_qualification_guest_borrow_counter_t counter) {
    return counter->value;
}

void exports_niobium_qualification_guest_counter_destructor(
    exports_niobium_qualification_guest_counter_t *counter) {
    free(counter);
}

bool exports_niobium_qualification_guest_evaluate(
    exports_niobium_qualification_guest_request_t *input,
    exports_niobium_qualification_guest_response_t *ret,
    exports_niobium_qualification_guest_failure_t *err) {
    if (input->enabled.is_some && !input->enabled.val) {
        err->tag = EXPORTS_NIOBIUM_QUALIFICATION_GUEST_FAILURE_INVALID_INPUT;
        qualification_string_dup(&err->val.invalid_input, "disabled");
        exports_niobium_qualification_guest_request_free(input);
        return false;
    }
    niobium_qualification_host_fact(&ret->name);
    ret->total = 0;
    if (input->values.len > 1024) abort();
    for (size_t i = 0; i < input->values.len; i++) ret->total += input->values.ptr[i];
    exports_niobium_qualification_guest_request_free(input);
    return true;
}

void exports_niobium_qualification_guest_burn(void) {
    /* Intentionally nonterminating: the host must trap on exhausted fuel. */
    for (;;) __asm__ volatile("" ::: "memory");
}

uint32_t exports_niobium_qualification_guest_allocate(uint32_t bytes) {
    return (uint32_t)__builtin_wasm_memory_grow(0, bytes / 65536);
}

void exports_niobium_qualification_guest_output(uint32_t bytes, qualification_string_t *ret) {
    if (bytes > (1 << 20)) abort();
    ret->ptr = malloc(bytes);
    if (!ret->ptr && bytes) abort();
    ret->len = bytes;
    memset(ret->ptr, 'x', bytes);
}

void exports_niobium_qualification_guest_amplify(uint32_t bytes, qualification_list_u8_t *ret) {
    if (bytes > (1 << 20)) abort();
    ret->ptr = malloc(bytes);
    if (!ret->ptr && bytes) abort();
    ret->len = bytes;
    memset(ret->ptr, 1, bytes);
}

void exports_niobium_qualification_guest_many(uint32_t calls) {
    if (calls > 2048) abort();
    for (uint32_t i = 0; i < calls; i++) {
        qualification_string_t result;
        niobium_qualification_host_fact(&result);
        qualification_string_free(&result);
    }
}
