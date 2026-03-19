#include "GhosttyDyn.h"

#include <assert.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void *ghostty_handle = NULL;
static char ghostty_error[4096] = {0};

#define DECLARE_SYM(name, ret, args) \
    static ret (*p_##name) args = NULL

#define LOAD_SYM(name)                                                         \
    do {                                                                       \
        p_##name = dlsym(ghostty_handle, #name);                               \
        if (p_##name == NULL) return dlerror();                                \
    } while (0)

DECLARE_SYM(ghostty_init, int, (uintptr_t, char **));
DECLARE_SYM(ghostty_info, ghostty_info_s, (void));
DECLARE_SYM(ghostty_config_new, ghostty_config_t, (void));
DECLARE_SYM(ghostty_config_free, void, (ghostty_config_t));
DECLARE_SYM(ghostty_config_load_file, void, (ghostty_config_t, const char *));
DECLARE_SYM(ghostty_config_load_default_files, void, (ghostty_config_t));
DECLARE_SYM(ghostty_config_load_recursive_files, void, (ghostty_config_t));
DECLARE_SYM(ghostty_config_finalize, void, (ghostty_config_t));
DECLARE_SYM(ghostty_config_get, bool, (ghostty_config_t, void *, const char *, uintptr_t));
DECLARE_SYM(ghostty_app_new, ghostty_app_t, (const ghostty_runtime_config_s *, ghostty_config_t));
DECLARE_SYM(ghostty_app_free, void, (ghostty_app_t));
DECLARE_SYM(ghostty_app_tick, void, (ghostty_app_t));
DECLARE_SYM(ghostty_app_set_focus, void, (ghostty_app_t, bool));
DECLARE_SYM(ghostty_app_update_config, void, (ghostty_app_t, ghostty_config_t));
DECLARE_SYM(ghostty_app_userdata, void *, (ghostty_app_t));
DECLARE_SYM(ghostty_surface_config_new, ghostty_surface_config_s, (void));
DECLARE_SYM(ghostty_surface_inherited_config, ghostty_surface_config_s, (ghostty_surface_t, ghostty_surface_context_e));
DECLARE_SYM(ghostty_surface_new, ghostty_surface_t, (ghostty_app_t, const ghostty_surface_config_s *));
DECLARE_SYM(ghostty_surface_update_config, void, (ghostty_surface_t, ghostty_config_t));
DECLARE_SYM(ghostty_surface_free, void, (ghostty_surface_t));
DECLARE_SYM(ghostty_surface_userdata, void *, (ghostty_surface_t));
DECLARE_SYM(ghostty_surface_size, ghostty_surface_size_s, (ghostty_surface_t));
DECLARE_SYM(ghostty_surface_set_content_scale, void, (ghostty_surface_t, double, double));
DECLARE_SYM(ghostty_surface_set_focus, void, (ghostty_surface_t, bool));
DECLARE_SYM(ghostty_surface_set_size, void, (ghostty_surface_t, uint32_t, uint32_t));
DECLARE_SYM(ghostty_surface_key, bool, (ghostty_surface_t, ghostty_input_key_s));
DECLARE_SYM(ghostty_surface_text, void, (ghostty_surface_t, const char *, uintptr_t));
DECLARE_SYM(ghostty_surface_mouse_button, bool, (ghostty_surface_t, ghostty_input_mouse_state_e, ghostty_input_mouse_button_e, ghostty_input_mods_e));
DECLARE_SYM(ghostty_surface_mouse_pos, void, (ghostty_surface_t, double, double, ghostty_input_mods_e));
DECLARE_SYM(ghostty_surface_mouse_scroll, void, (ghostty_surface_t, double, double, ghostty_input_scroll_mods_t));
DECLARE_SYM(ghostty_surface_complete_clipboard_request, void, (ghostty_surface_t, const char *, void *, bool));
DECLARE_SYM(ghostty_surface_binding_action, bool, (ghostty_surface_t, const char *, uintptr_t));
DECLARE_SYM(ghostty_surface_split, void, (ghostty_surface_t, ghostty_action_split_direction_e));
DECLARE_SYM(ghostty_surface_split_focus, void, (ghostty_surface_t, ghostty_action_goto_split_e));
DECLARE_SYM(ghostty_surface_split_resize, void, (ghostty_surface_t, ghostty_action_resize_split_direction_e, uint16_t));
DECLARE_SYM(ghostty_surface_split_equalize, void, (ghostty_surface_t));
DECLARE_SYM(ghostty_surface_process_exited, bool, (ghostty_surface_t));
#ifdef __APPLE__
DECLARE_SYM(ghostty_surface_set_display_id, void, (ghostty_surface_t, uint32_t));
#endif

static void require_loaded(void) {
    assert(ghostty_handle != NULL && "tairi_ghostty_load must succeed before use");
}

static const char *set_errorf(const char *message) {
    snprintf(ghostty_error, sizeof(ghostty_error), "%s", message);
    fprintf(stderr, "[tairi] %s\n", ghostty_error);
    return ghostty_error;
}

static const char *set_dlerror(const char *prefix) {
    const char *err = dlerror();
    if (err == NULL) err = "unknown dlopen error";
    snprintf(ghostty_error, sizeof(ghostty_error), "%s: %s", prefix, err);
    fprintf(stderr, "[tairi] %s\n", ghostty_error);
    return ghostty_error;
}

static void preload_adjacent_sparkle(const char *binary_path) {
    const char *marker = strstr(binary_path, "/Contents/MacOS/");
    if (marker == NULL) return;

    size_t prefix_len = (size_t)(marker - binary_path);
    char sparkle_path[4096] = {0};
    snprintf(
        sparkle_path,
        sizeof(sparkle_path),
        "%.*s/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
        (int)prefix_len,
        binary_path
    );

    void *sparkle = dlopen(sparkle_path, RTLD_NOW | RTLD_GLOBAL);
    if (sparkle == NULL) {
        fprintf(stderr, "[tairi] Sparkle preload failed: %s\n", dlerror());
    } else {
        fprintf(stderr, "[tairi] Sparkle preloaded from %s\n", sparkle_path);
    }
}

const char *tairi_ghostty_load(const char *binary_path) {
    if (ghostty_handle != NULL) return NULL;

    const char *path = binary_path;
    if (path == NULL || path[0] == '\0') {
        path = getenv("TAIRI_GHOSTTY_BIN");
    }
    if (path == NULL || path[0] == '\0') {
        path = getenv("TAIRI_BUNDLED_GHOSTTY_BIN");
    }
    if (path == NULL || path[0] == '\0') {
        return set_errorf("No bundled Ghostty runtime configured");
    }

    preload_adjacent_sparkle(path);
    ghostty_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (ghostty_handle == NULL) return set_dlerror("Ghostty dlopen failed");

    LOAD_SYM(ghostty_init);
    LOAD_SYM(ghostty_info);
    LOAD_SYM(ghostty_config_new);
    p_ghostty_config_free = dlsym(ghostty_handle, "ghostty_config_free");
    LOAD_SYM(ghostty_config_load_file);
    LOAD_SYM(ghostty_config_load_default_files);
    LOAD_SYM(ghostty_config_load_recursive_files);
    LOAD_SYM(ghostty_config_finalize);
    LOAD_SYM(ghostty_config_get);
    LOAD_SYM(ghostty_app_new);
    LOAD_SYM(ghostty_app_free);
    LOAD_SYM(ghostty_app_tick);
    LOAD_SYM(ghostty_app_set_focus);
    LOAD_SYM(ghostty_app_update_config);
    LOAD_SYM(ghostty_app_userdata);
    LOAD_SYM(ghostty_surface_config_new);
    LOAD_SYM(ghostty_surface_inherited_config);
    LOAD_SYM(ghostty_surface_new);
    LOAD_SYM(ghostty_surface_update_config);
    LOAD_SYM(ghostty_surface_free);
    LOAD_SYM(ghostty_surface_userdata);
    LOAD_SYM(ghostty_surface_size);
    LOAD_SYM(ghostty_surface_set_content_scale);
    LOAD_SYM(ghostty_surface_set_focus);
    LOAD_SYM(ghostty_surface_set_size);
    LOAD_SYM(ghostty_surface_key);
    LOAD_SYM(ghostty_surface_text);
    LOAD_SYM(ghostty_surface_mouse_button);
    LOAD_SYM(ghostty_surface_mouse_pos);
    LOAD_SYM(ghostty_surface_mouse_scroll);
    LOAD_SYM(ghostty_surface_complete_clipboard_request);
    LOAD_SYM(ghostty_surface_binding_action);
    LOAD_SYM(ghostty_surface_split);
    LOAD_SYM(ghostty_surface_split_focus);
    LOAD_SYM(ghostty_surface_split_resize);
    LOAD_SYM(ghostty_surface_split_equalize);
    LOAD_SYM(ghostty_surface_process_exited);
#ifdef __APPLE__
    LOAD_SYM(ghostty_surface_set_display_id);
#endif

    return NULL;
}

int tairi_ghostty_is_loaded(void) {
    return ghostty_handle != NULL;
}

int tairi_ghostty_init(uintptr_t argc, char **argv) {
    require_loaded();
    return p_ghostty_init(argc, argv);
}

ghostty_info_s tairi_ghostty_info(void) {
    require_loaded();
    return p_ghostty_info();
}

ghostty_config_t tairi_ghostty_config_new(void) {
    require_loaded();
    return p_ghostty_config_new();
}

void tairi_ghostty_config_free(ghostty_config_t config) {
    require_loaded();
    if (p_ghostty_config_free != NULL) {
        p_ghostty_config_free(config);
    }
}

void tairi_ghostty_config_load_file(ghostty_config_t config, const char *path) {
    require_loaded();
    p_ghostty_config_load_file(config, path);
}

void tairi_ghostty_config_load_default_files(ghostty_config_t config) {
    require_loaded();
    p_ghostty_config_load_default_files(config);
}

void tairi_ghostty_config_load_recursive_files(ghostty_config_t config) {
    require_loaded();
    p_ghostty_config_load_recursive_files(config);
}

void tairi_ghostty_config_finalize(ghostty_config_t config) {
    require_loaded();
    p_ghostty_config_finalize(config);
}

bool tairi_ghostty_config_get_color(
    ghostty_config_t config,
    const char *key,
    ghostty_config_color_s *value
) {
    require_loaded();
    if (key == NULL || value == NULL) return false;
    return p_ghostty_config_get(config, value, key, strlen(key));
}

bool tairi_ghostty_config_get_palette(
    ghostty_config_t config,
    ghostty_config_palette_s *value
) {
    static const char *key = "palette";

    require_loaded();
    if (value == NULL) return false;
    return p_ghostty_config_get(config, value, key, strlen(key));
}

bool tairi_ghostty_config_get_palette_color(
    ghostty_config_t config,
    uint8_t index,
    ghostty_config_color_s *value
) {
    ghostty_config_palette_s palette;

    require_loaded();
    if (value == NULL) return false;
    if (!tairi_ghostty_config_get_palette(config, &palette)) return false;

    *value = palette.colors[index];
    return true;
}

ghostty_app_t tairi_ghostty_app_new(
    const ghostty_runtime_config_s *runtime_config,
    ghostty_config_t config
) {
    require_loaded();
    return p_ghostty_app_new(runtime_config, config);
}

void tairi_ghostty_app_free(ghostty_app_t app) {
    require_loaded();
    p_ghostty_app_free(app);
}

void tairi_ghostty_app_tick(ghostty_app_t app) {
    require_loaded();
    p_ghostty_app_tick(app);
}

void tairi_ghostty_app_set_focus(ghostty_app_t app, bool focused) {
    require_loaded();
    p_ghostty_app_set_focus(app, focused);
}

void tairi_ghostty_app_update_config(ghostty_app_t app, ghostty_config_t config) {
    require_loaded();
    p_ghostty_app_update_config(app, config);
}

void *tairi_ghostty_app_userdata(ghostty_app_t app) {
    require_loaded();
    return p_ghostty_app_userdata(app);
}

ghostty_surface_config_s tairi_ghostty_surface_config_new(void) {
    require_loaded();
    return p_ghostty_surface_config_new();
}

ghostty_surface_config_s tairi_ghostty_surface_inherited_config(
    ghostty_surface_t surface,
    ghostty_surface_context_e context
) {
    require_loaded();
    return p_ghostty_surface_inherited_config(surface, context);
}

ghostty_surface_t tairi_ghostty_surface_new(
    ghostty_app_t app,
    const ghostty_surface_config_s *config
) {
    require_loaded();
    return p_ghostty_surface_new(app, config);
}

void tairi_ghostty_surface_update_config(ghostty_surface_t surface, ghostty_config_t config) {
    require_loaded();
    p_ghostty_surface_update_config(surface, config);
}

void tairi_ghostty_surface_free(ghostty_surface_t surface) {
    require_loaded();
    p_ghostty_surface_free(surface);
}

void *tairi_ghostty_surface_userdata(ghostty_surface_t surface) {
    require_loaded();
    return p_ghostty_surface_userdata(surface);
}

ghostty_surface_size_s tairi_ghostty_surface_size(ghostty_surface_t surface) {
    require_loaded();
    return p_ghostty_surface_size(surface);
}

void tairi_ghostty_surface_set_content_scale(
    ghostty_surface_t surface,
    double x,
    double y
) {
    require_loaded();
    p_ghostty_surface_set_content_scale(surface, x, y);
}

void tairi_ghostty_surface_set_focus(ghostty_surface_t surface, bool focused) {
    require_loaded();
    p_ghostty_surface_set_focus(surface, focused);
}

void tairi_ghostty_surface_set_size(
    ghostty_surface_t surface,
    uint32_t width,
    uint32_t height
) {
    require_loaded();
    p_ghostty_surface_set_size(surface, width, height);
}

bool tairi_ghostty_surface_key(
    ghostty_surface_t surface,
    ghostty_input_key_s event
) {
    require_loaded();
    return p_ghostty_surface_key(surface, event);
}

void tairi_ghostty_surface_text(
    ghostty_surface_t surface,
    const char *text,
    uintptr_t len
) {
    require_loaded();
    p_ghostty_surface_text(surface, text, len);
}

bool tairi_ghostty_surface_mouse_button(
    ghostty_surface_t surface,
    ghostty_input_mouse_state_e state,
    ghostty_input_mouse_button_e button,
    ghostty_input_mods_e mods
) {
    require_loaded();
    return p_ghostty_surface_mouse_button(surface, state, button, mods);
}

void tairi_ghostty_surface_mouse_pos(
    ghostty_surface_t surface,
    double x,
    double y,
    ghostty_input_mods_e mods
) {
    require_loaded();
    p_ghostty_surface_mouse_pos(surface, x, y, mods);
}

void tairi_ghostty_surface_mouse_scroll(
    ghostty_surface_t surface,
    double x,
    double y,
    ghostty_input_scroll_mods_t mods
) {
    require_loaded();
    p_ghostty_surface_mouse_scroll(surface, x, y, mods);
}

void tairi_ghostty_surface_complete_clipboard_request(
    ghostty_surface_t surface,
    const char *value,
    void *state,
    bool confirmed
) {
    require_loaded();
    p_ghostty_surface_complete_clipboard_request(surface, value, state, confirmed);
}

bool tairi_ghostty_surface_binding_action(
    ghostty_surface_t surface,
    const char *action,
    uintptr_t len
) {
    require_loaded();
    return p_ghostty_surface_binding_action(surface, action, len);
}

void tairi_ghostty_surface_split(
    ghostty_surface_t surface,
    ghostty_action_split_direction_e direction
) {
    require_loaded();
    p_ghostty_surface_split(surface, direction);
}

void tairi_ghostty_surface_split_focus(
    ghostty_surface_t surface,
    ghostty_action_goto_split_e direction
) {
    require_loaded();
    p_ghostty_surface_split_focus(surface, direction);
}

void tairi_ghostty_surface_split_resize(
    ghostty_surface_t surface,
    ghostty_action_resize_split_direction_e direction,
    uint16_t amount
) {
    require_loaded();
    p_ghostty_surface_split_resize(surface, direction, amount);
}

void tairi_ghostty_surface_split_equalize(ghostty_surface_t surface) {
    require_loaded();
    p_ghostty_surface_split_equalize(surface);
}

bool tairi_ghostty_surface_process_exited(ghostty_surface_t surface) {
    require_loaded();
    return p_ghostty_surface_process_exited(surface);
}

#ifdef __APPLE__
void tairi_ghostty_surface_set_display_id(ghostty_surface_t surface, uint32_t display_id) {
    require_loaded();
    p_ghostty_surface_set_display_id(surface, display_id);
}
#endif
