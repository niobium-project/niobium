/* WAMR owns process-global state. Serialize full initialize/evaluate/destroy cycles.
 * ponytail: one global interpreter lock; persistent isolated engines require a
 * separate upstream allocator/lifecycle design when parallel evaluation matters.
 */
#include "host.h"
#include "wasm_export.h"
#include "wasm_exec_env.h"
#include <pthread.h>
#include <string.h>

static pthread_mutex_t interpreter_lock = PTHREAD_MUTEX_INITIALIZER;

typedef struct {
    const nb_wamr_request *request;
    int32_t fault;
} evaluation;

static evaluation *current(wasm_exec_env_t env) {
    return wasm_runtime_get_custom_data(wasm_runtime_get_module_inst(env));
}

static uint8_t *memory(wasm_exec_env_t env, uint32_t offset, uint32_t length) {
    wasm_module_inst_t instance = wasm_runtime_get_module_inst(env);
    if (!wasm_runtime_validate_app_addr(instance, offset, length)) {
        current(env)->fault = 3;
        return NULL;
    }
    return wasm_runtime_addr_app_to_native(instance, offset);
}

static int32_t read_value(wasm_exec_env_t env, uint32_t kind, uint32_t index,
                          uint32_t offset, uint32_t capacity) {
    evaluation *ev = current(env);
    uint8_t *target = memory(env, offset, capacity);
    if (!target) return -1;
    int32_t result = ev->request->read(ev->request->context, kind, index, target, capacity);
    if (result < 0) ev->fault = 4;
    return result;
}

static int32_t write_value(wasm_exec_env_t env, uint32_t handle,
                           uint32_t offset, uint32_t length) {
    evaluation *ev = current(env);
    const uint8_t *source = memory(env, offset, length);
    if (!source) return -1;
    int32_t result = ev->request->write(ev->request->context, handle, source, length);
    if (result < 0) ev->fault = 4;
    return result;
}

static int32_t write_state(wasm_exec_env_t env, uint32_t offset, uint32_t length) {
    return write_value(env, UINT32_MAX, offset, length);
}

static int32_t invoke(wasm_module_inst_t instance, wasm_exec_env_t env,
                      const char *name, uint32_t count, uint32_t *arguments) {
    wasm_function_inst_t function = wasm_runtime_lookup_function(instance, name);
    if (!function || wasm_func_get_param_count(function, instance) != count
        || wasm_func_get_result_count(function, instance) != 1) return 5;
    wasm_valkind_t parameters[2], result;
    wasm_func_get_param_types(function, instance, parameters);
    wasm_func_get_result_types(function, instance, &result);
    if (result != WASM_I32) return 5;
    for (uint32_t i = 0; i < count; ++i) if (parameters[i] != WASM_I32) return 5;
    if (!wasm_runtime_call_wasm(env, function, count, arguments)) return 3;
    if (current(env)->fault) return current(env)->fault;
    return arguments[0] == 0 ? 0 : 4;
}

static int32_t execute(uint8_t *bytes, uint32_t size, const nb_wamr_request *request) {
    char message[256];
    wasm_module_t module = wasm_runtime_load(bytes, size, message, sizeof(message));
    if (!module) return 2;
    int32_t result = 1;
    wasm_module_inst_t instance = wasm_runtime_instantiate(module, request->stack_size, 0,
                                                        message, sizeof(message));
    if (!instance) goto unload;
    evaluation ev = {request, 0};
    wasm_runtime_set_custom_data(instance, &ev);
    wasm_exec_env_t env = wasm_runtime_create_exec_env(instance, request->stack_size);
    if (!env) goto deinstantiate;
    env->instructions_to_execute = request->instructions;
    uint32_t arguments[2] = {request->from, request->to};
    if (request->migrate) {
        request->phase(request->context, 1);
        result = invoke(instance, env, "nb_migrate_v1", 2, arguments);
        if (result) goto destroy_env;
    }
    request->phase(request->context, 0);
    result = invoke(instance, env, "nb_plan_v1", 0, arguments);
 destroy_env:
    wasm_runtime_destroy_exec_env(env);
 deinstantiate:
    wasm_runtime_deinstantiate(instance);
 unload:
    wasm_runtime_unload(module);
    return result;
}

int32_t nb_wamr_evaluate(uint8_t *bytes, uint32_t size, const nb_wamr_request *request) {
    if (pthread_mutex_lock(&interpreter_lock) != 0) return 1;
    NativeSymbol imports[] = {
        {"read", (void *)read_value, "(iiii)i", NULL},
        {"emit", (void *)write_value, "(iii)i", NULL},
        {"state", (void *)write_state, "(ii)i", NULL},
    };
    RuntimeInitArgs options;
    memset(&options, 0, sizeof(options));
    options.mem_alloc_type = Alloc_With_Pool;
    options.mem_alloc_option.pool.heap_buf = request->heap;
    options.mem_alloc_option.pool.heap_size = request->heap_size;
    options.native_module_name = "niobium_v1";
    options.native_symbols = imports;
    options.n_native_symbols = sizeof(imports) / sizeof(imports[0]);
    options.running_mode = Mode_Interp;
    int32_t result = 1;
    if (wasm_runtime_full_init(&options)) {
        result = execute(bytes, size, request);
        wasm_runtime_destroy();
    }
    if (pthread_mutex_unlock(&interpreter_lock) != 0) return 1;
    return result;
}
