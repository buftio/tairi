#ifndef TAIRI_GHOSTTY_DYN_H
#define TAIRI_GHOSTTY_DYN_H

#include "ghostty.h"

#ifdef __cplusplus
extern "C" {
#endif

const char *tairi_ghostty_load(const char *binary_path);
int tairi_ghostty_is_loaded(void);

int tairi_ghostty_init(uintptr_t argc, char **argv);
ghostty_info_s tairi_ghostty_info(void);

ghostty_config_t tairi_ghostty_config_new(void);
void tairi_ghostty_config_free(ghostty_config_t config);
void tairi_ghostty_config_load_file(ghostty_config_t config, const char *path);
void tairi_ghostty_config_load_default_files(ghostty_config_t config);
void tairi_ghostty_config_load_recursive_files(ghostty_config_t config);
void tairi_ghostty_config_finalize(ghostty_config_t config);
bool tairi_ghostty_config_get_color(
    ghostty_config_t config,
    const char *key,
    ghostty_config_color_s *value
);
bool tairi_ghostty_config_get_palette(
    ghostty_config_t config,
    ghostty_config_palette_s *value
);
bool tairi_ghostty_config_get_palette_color(
    ghostty_config_t config,
    uint8_t index,
    ghostty_config_color_s *value
);

ghostty_app_t tairi_ghostty_app_new(
    const ghostty_runtime_config_s *runtime_config,
    ghostty_config_t config
);
void tairi_ghostty_app_free(ghostty_app_t app);
void tairi_ghostty_app_tick(ghostty_app_t app);
void tairi_ghostty_app_set_focus(ghostty_app_t app, bool focused);
void tairi_ghostty_app_keyboard_changed(ghostty_app_t app);
void tairi_ghostty_app_update_config(ghostty_app_t app, ghostty_config_t config);
void *tairi_ghostty_app_userdata(ghostty_app_t app);

ghostty_surface_config_s tairi_ghostty_surface_config_new(void);
ghostty_surface_config_s tairi_ghostty_surface_inherited_config(
    ghostty_surface_t surface,
    ghostty_surface_context_e context
);
ghostty_surface_t tairi_ghostty_surface_new(
    ghostty_app_t app,
    const ghostty_surface_config_s *config
);
void tairi_ghostty_surface_update_config(ghostty_surface_t surface, ghostty_config_t config);
void tairi_ghostty_surface_free(ghostty_surface_t surface);
void *tairi_ghostty_surface_userdata(ghostty_surface_t surface);
ghostty_surface_size_s tairi_ghostty_surface_size(ghostty_surface_t surface);
void tairi_ghostty_surface_set_content_scale(
    ghostty_surface_t surface,
    double x,
    double y
);
void tairi_ghostty_surface_set_focus(ghostty_surface_t surface, bool focused);
void tairi_ghostty_surface_set_size(
    ghostty_surface_t surface,
    uint32_t width,
    uint32_t height
);
bool tairi_ghostty_surface_key(
    ghostty_surface_t surface,
    ghostty_input_key_s event
);
void tairi_ghostty_surface_text(
    ghostty_surface_t surface,
    const char *text,
    uintptr_t len
);
bool tairi_ghostty_surface_mouse_button(
    ghostty_surface_t surface,
    ghostty_input_mouse_state_e state,
    ghostty_input_mouse_button_e button,
    ghostty_input_mods_e mods
);
void tairi_ghostty_surface_mouse_pos(
    ghostty_surface_t surface,
    double x,
    double y,
    ghostty_input_mods_e mods
);
void tairi_ghostty_surface_mouse_scroll(
    ghostty_surface_t surface,
    double x,
    double y,
    ghostty_input_scroll_mods_t mods
);
void tairi_ghostty_surface_complete_clipboard_request(
    ghostty_surface_t surface,
    const char *value,
    void *state,
    bool confirmed
);
bool tairi_ghostty_surface_binding_action(
    ghostty_surface_t surface,
    const char *action,
    uintptr_t len
);
void tairi_ghostty_surface_split(
    ghostty_surface_t surface,
    ghostty_action_split_direction_e direction
);
void tairi_ghostty_surface_split_focus(
    ghostty_surface_t surface,
    ghostty_action_goto_split_e direction
);
void tairi_ghostty_surface_split_resize(
    ghostty_surface_t surface,
    ghostty_action_resize_split_direction_e direction,
    uint16_t amount
);
void tairi_ghostty_surface_split_equalize(ghostty_surface_t surface);
bool tairi_ghostty_surface_process_exited(ghostty_surface_t surface);

#ifdef __APPLE__
void tairi_ghostty_surface_set_display_id(ghostty_surface_t surface, uint32_t display_id);
#endif

#ifdef __cplusplus
}
#endif

#endif
