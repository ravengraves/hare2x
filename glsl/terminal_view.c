#include "terminal_view.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/ioctl.h>
#include <unistd.h>

#define TERMINAL_VIEW_CELL_STRIDE 10
#define TERMINAL_VIEW_DIFF_THRESHOLD 0
#define TERMINAL_VIEW_BLOCK_UPPER 0x2580u
#define TERMINAL_VIEW_BLOCK_FULL 0x2588u
#define TERMINAL_VIEW_BRAILLE_BASE 0x2800u

typedef struct {
  unsigned char fg[3];
  unsigned char bg[3];
  unsigned char base_bg[3];
  unsigned int codepoint;
} TerminalBlit;

static void terminal_query_size(int* cols, int* rows) {
  struct winsize ws;
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0 && ws.ws_row > 0) {
    *cols = ws.ws_col;
    *rows = ws.ws_row;
    return;
  }

  const char* env_cols = getenv("COLUMNS");
  const char* env_rows = getenv("LINES");
  if (env_cols && env_rows) {
    int c = atoi(env_cols);
    int r = atoi(env_rows);
    if (c > 0 && r > 0) {
      *cols = c;
      *rows = r;
      return;
    }
  }

  *cols = 80;
  *rows = 24;
}

static void terminal_update_size(TerminalView* view) {
  if (view->override_cols > 0 && view->override_rows > 0) {
    view->cols = view->override_cols;
    view->rows = view->override_rows;
    return;
  }
  if (view->fixed_size && view->cols > 0 && view->rows > 0) {
    return;
  }
  terminal_query_size(&view->cols, &view->rows);
}

void terminal_view_init(TerminalView* view, int cols, int rows,
                        int fixed_size, int clear_rest, int line_mode,
                        int braille_mode, int ascii_mode) {
  if (!view) {
    return;
  }
  memset(view, 0, sizeof(*view));
  view->override_cols = cols;
  view->override_rows = rows;
  view->fixed_size = fixed_size;
  view->clear_rest = clear_rest;
  view->line_mode = line_mode;
  view->braille_mode = braille_mode;
  view->ascii_mode = ascii_mode;
  terminal_update_size(view);
  view->initialized = 1;
  if (!view->line_mode) {
    fprintf(stdout, "\x1b[2J\x1b[H\x1b[?25l");
    fflush(stdout);
  }
}

static void append_color(char* out, size_t* idx, size_t cap,
                         int fr, int fg, int fb,
                         int br, int bg, int bb) {
  int written = snprintf(out + *idx, cap - *idx,
                         "\x1b[38;2;%d;%d;%dm\x1b[48;2;%d;%d;%dm",
                         fr, fg, fb, br, bg, bb);
  if (written < 0) {
    return;
  }
  if ((size_t)written >= cap - *idx) {
    *idx = cap - 1;
    return;
  }
  *idx += (size_t)written;
}

static void append_fg(char* out, size_t* idx, size_t cap,
                      int fr, int fg, int fb) {
  int written = snprintf(out + *idx, cap - *idx,
                         "\x1b[38;2;%d;%d;%dm",
                         fr, fg, fb);
  if (written < 0) {
    return;
  }
  if ((size_t)written >= cap - *idx) {
    *idx = cap - 1;
    return;
  }
  *idx += (size_t)written;
}

static void append_utf8(char* out, size_t* idx, size_t cap, unsigned int codepoint) {
  unsigned char bytes[4];
  size_t count = 0;
  if (codepoint <= 0x7Fu) {
    bytes[0] = (unsigned char)codepoint;
    count = 1;
  } else if (codepoint <= 0x7FFu) {
    bytes[0] = (unsigned char)(0xC0u | (codepoint >> 6));
    bytes[1] = (unsigned char)(0x80u | (codepoint & 0x3Fu));
    count = 2;
  } else if (codepoint <= 0xFFFFu) {
    bytes[0] = (unsigned char)(0xE0u | (codepoint >> 12));
    bytes[1] = (unsigned char)(0x80u | ((codepoint >> 6) & 0x3Fu));
    bytes[2] = (unsigned char)(0x80u | (codepoint & 0x3Fu));
    count = 3;
  } else if (codepoint <= 0x10FFFFu) {
    bytes[0] = (unsigned char)(0xF0u | (codepoint >> 18));
    bytes[1] = (unsigned char)(0x80u | ((codepoint >> 12) & 0x3Fu));
    bytes[2] = (unsigned char)(0x80u | ((codepoint >> 6) & 0x3Fu));
    bytes[3] = (unsigned char)(0x80u | (codepoint & 0x3Fu));
    count = 4;
  }
  if (count == 0) {
    return;
  }
  if (cap - *idx < count) {
    *idx = cap - 1;
    return;
  }
  for (size_t i = 0; i < count; ++i) {
    out[(*idx)++] = (char)bytes[i];
  }
}

static void append_cursor_pos(char* out, size_t* idx, size_t cap, int row, int col) {
  int written = snprintf(out + *idx, cap - *idx, "\x1b[%d;%dH", row, col);
  if (written < 0) {
    return;
  }
  if ((size_t)written >= cap - *idx) {
    *idx = cap - 1;
    return;
  }
  *idx += (size_t)written;
}

static void append_cursor_home(char* out, size_t* idx, size_t cap, int row) {
  append_cursor_pos(out, idx, cap, row, 1);
}

static int channel_close(int a, int b) {
  int diff = a - b;
  if (diff < 0) {
    diff = -diff;
  }
  return diff <= TERMINAL_VIEW_DIFF_THRESHOLD;
}

static int color_similar(const unsigned char* a, const unsigned char* b) {
  return channel_close(a[0], b[0]) &&
         channel_close(a[1], b[1]) &&
         channel_close(a[2], b[2]);
}

static void color_avg2(unsigned char out[3],
                       const unsigned char* a,
                       const unsigned char* b) {
  out[0] = (unsigned char)((a[0] + b[0]) / 2);
  out[1] = (unsigned char)((a[1] + b[1]) / 2);
  out[2] = (unsigned char)((a[2] + b[2]) / 2);
}

static int color_luma(const unsigned char* c) {
  return 2126 * (int)c[0] + 7152 * (int)c[1] + 722 * (int)c[2];
}

static int clamp_int(int value, int lo, int hi) {
  if (value < lo) {
    return lo;
  }
  if (value > hi) {
    return hi;
  }
  return value;
}

static int norm_to_index(float value, int size) {
  if (size <= 1) {
    return 0;
  }
  if (value < 0.0f) {
    value = 0.0f;
  } else if (value > 1.0f) {
    value = 1.0f;
  }
  int idx = (int)lroundf(value * (float)(size - 1));
  return clamp_int(idx, 0, size - 1);
}

static unsigned char braille_bit(int x, int y) {
  if (x == 0) {
    switch (y) {
      case 0: return 1u;
      case 1: return 2u;
      case 2: return 4u;
      case 3: return 64u;
      default: return 0u;
    }
  }
  switch (y) {
    case 0: return 8u;
    case 1: return 16u;
    case 2: return 32u;
    case 3: return 128u;
    default: return 0u;
  }
}

static unsigned char braille_mask_from_samples(const unsigned char* samples,
                                               unsigned char fg[3],
                                               int* max_luma_out) {
  int luma[8];
  int sum_luma = 0;
  int max_luma = 0;
  int sum_r = 0;
  int sum_g = 0;
  int sum_b = 0;
  for (int i = 0; i < 8; ++i) {
    const unsigned char* sample = samples + i * 3;
    luma[i] = color_luma(sample);
    if (luma[i] > max_luma) {
      max_luma = luma[i];
    }
    sum_luma += luma[i];
    sum_r += sample[0];
    sum_g += sample[1];
    sum_b += sample[2];
  }
  int threshold = sum_luma / 8;

  int on_count = 0;
  int on_r = 0;
  int on_g = 0;
  int on_b = 0;
  unsigned char mask_value = 0;
  for (int i = 0; i < 8; ++i) {
    if (luma[i] >= threshold) {
      const unsigned char* sample = samples + i * 3;
      int sx = i % 2;
      int sy = i / 2;
      mask_value |= braille_bit(sx, sy);
      on_r += sample[0];
      on_g += sample[1];
      on_b += sample[2];
      on_count += 1;
    }
  }

  if (on_count > 0) {
    fg[0] = (unsigned char)(on_r / on_count);
    fg[1] = (unsigned char)(on_g / on_count);
    fg[2] = (unsigned char)(on_b / on_count);
  } else {
    fg[0] = (unsigned char)(sum_r / 8);
    fg[1] = (unsigned char)(sum_g / 8);
    fg[2] = (unsigned char)(sum_b / 8);
  }
  if (max_luma_out) {
    *max_luma_out = max_luma;
  }
  return mask_value;
}

static void blit_half(const unsigned char* rgb, int width, int cols,
                      int col, int src_y_top, int src_y_bottom,
                      TerminalBlit* out) {
  int src_x = col * width / cols;
  int top_idx = (src_y_top * width + src_x) * 3;
  int bottom_idx = (src_y_bottom * width + src_x) * 3;
  unsigned char top[3] = {
    rgb[top_idx + 0],
    rgb[top_idx + 1],
    rgb[top_idx + 2],
  };
  unsigned char bot[3] = {
    rgb[bottom_idx + 0],
    rgb[bottom_idx + 1],
    rgb[bottom_idx + 2],
  };

  color_avg2(out->base_bg, top, bot);
  if (color_similar(top, bot)) {
    memcpy(out->fg, out->base_bg, 3);
    memcpy(out->bg, out->base_bg, 3);
    out->codepoint = TERMINAL_VIEW_BLOCK_FULL;
    return;
  }

  memcpy(out->fg, top, 3);
  memcpy(out->bg, bot, 3);
  out->codepoint = TERMINAL_VIEW_BLOCK_UPPER;
}

static void blit_ascii(const unsigned char* rgb, int width, int cols,
                       int col, int src_y_top, int src_y_bottom,
                       TerminalBlit* out) {
  int src_x = col * width / cols;
  int top_idx = (src_y_top * width + src_x) * 3;
  int bottom_idx = (src_y_bottom * width + src_x) * 3;
  unsigned char top[3] = {
    rgb[top_idx + 0],
    rgb[top_idx + 1],
    rgb[top_idx + 2],
  };
  unsigned char bot[3] = {
    rgb[bottom_idx + 0],
    rgb[bottom_idx + 1],
    rgb[bottom_idx + 2],
  };

  color_avg2(out->base_bg, top, bot);
  memcpy(out->fg, out->base_bg, 3);
  memcpy(out->bg, out->base_bg, 3);
  out->codepoint = ' ';
}

static void blit_braille(const unsigned char* rgb, int width, int cols,
                         int col, const int row_y[4],
                         TerminalBlit* out) {
  unsigned char samples[24];
  int sample_index = 0;
  int sample_cols = cols * 2;
  for (int sy = 0; sy < 4; ++sy) {
    int src_y = row_y[sy];
    for (int sx = 0; sx < 2; ++sx) {
      int src_x = (col * 2 + sx) * width / sample_cols;
      int src_idx = (src_y * width + src_x) * 3;
      samples[sample_index++] = rgb[src_idx + 0];
      samples[sample_index++] = rgb[src_idx + 1];
      samples[sample_index++] = rgb[src_idx + 2];
    }
  }

  int max_luma = 0;
  unsigned char mask = braille_mask_from_samples(samples, out->fg, &max_luma);
  out->bg[0] = 0;
  out->bg[1] = 0;
  out->bg[2] = 0;
  out->base_bg[0] = 0;
  out->base_bg[1] = 0;
  out->base_bg[2] = 0;
  if (mask == 0 || max_luma == 0) {
    out->fg[0] = 0;
    out->fg[1] = 0;
    out->fg[2] = 0;
    out->codepoint = ' ';
  } else {
    out->codepoint = TERMINAL_VIEW_BRAILLE_BASE + (unsigned int)mask;
  }
}

static int cell_similar(const unsigned char* a, const unsigned char* b) {
  for (int i = 0; i < 6; ++i) {
    if (!channel_close(a[i], b[i])) {
      return 0;
    }
  }
  for (int i = 6; i < TERMINAL_VIEW_CELL_STRIDE; ++i) {
    if (a[i] != b[i]) {
      return 0;
    }
  }
  return 1;
}

static void overlay_resize_glyphs(TerminalView* view, int cols, int rows) {
  if (!view || cols <= 0 || rows <= 0) {
    return;
  }
  if (view->glyph_cols == cols && view->glyph_rows == rows && view->glyph_cells) {
    return;
  }
  free(view->glyph_cells);
  view->glyph_cells = NULL;
  view->glyph_cols = cols;
  view->glyph_rows = rows;

  size_t cells = (size_t)cols * (size_t)rows;
  view->glyph_cells = (TerminalGlyphCell*)malloc(cells * sizeof(TerminalGlyphCell));
  if (!view->glyph_cells) {
    view->glyph_cols = 0;
    view->glyph_rows = 0;
  }
}

static void overlay_build_glyphs(TerminalView* view, int cols, int rows) {
  if (!view || view->overlay_glyph_count <= 0) {
    return;
  }
  overlay_resize_glyphs(view, cols, rows);
  if (!view->glyph_cells) {
    return;
  }

  size_t cells = (size_t)cols * (size_t)rows;
  memset(view->glyph_cells, 0, cells * sizeof(TerminalGlyphCell));

  for (int i = 0; i < view->overlay_glyph_count; ++i) {
    TerminalOverlayGlyph* glyph = view->overlay_glyphs + i;
    if (glyph->codepoint <= 0) {
      continue;
    }
    int col = norm_to_index(glyph->x, cols);
    int row = norm_to_index(glyph->y, rows);
    size_t idx = (size_t)row * (size_t)cols + (size_t)col;
    TerminalGlyphCell* cell = view->glyph_cells + idx;
    cell->codepoint = glyph->codepoint;
    cell->r = glyph->r;
    cell->g = glyph->g;
    cell->b = glyph->b;
    cell->used = 1;
  }
}

static void append_cell(char* out, size_t* idx, size_t cap,
                        unsigned int codepoint,
                        const unsigned char* fg,
                        const unsigned char* bg) {
  if (codepoint == TERMINAL_VIEW_BLOCK_FULL && color_similar(fg, bg)) {
    append_fg(out, idx, cap, fg[0], fg[1], fg[2]);
    append_utf8(out, idx, cap, codepoint);
    return;
  }
  append_color(out, idx, cap, fg[0], fg[1], fg[2], bg[0], bg[1], bg[2]);
  append_utf8(out, idx, cap, codepoint);
}

void terminal_view_present(TerminalView* view, const unsigned char* rgb,
                           int width, int height) {
  if (!view || !rgb || width <= 0 || height <= 0) {
    return;
  }
  if (!view->initialized) {
    terminal_view_init(view, view->override_cols, view->override_rows,
                       view->fixed_size, view->clear_rest, view->line_mode,
                       view->braille_mode, view->ascii_mode);
  }

  terminal_update_size(view);
  int cols = view->cols;
  int rows = view->rows;
  if (cols <= 0 || rows <= 0) {
    return;
  }

  int ascii_mode = view->ascii_mode != 0;
  int braille_mode = view->braille_mode != 0 && !ascii_mode;
  int sample_rows = rows * (braille_mode ? 4 : 2);
  if (sample_rows <= 0) {
    return;
  }

  size_t backing_size = (size_t)cols * (size_t)rows * TERMINAL_VIEW_CELL_STRIDE;
  if (view->backing_cols != cols || view->backing_rows != rows || !view->backing_cells) {
    free(view->backing_cells);
    view->backing_cells = (unsigned char*)malloc(backing_size);
    view->backing_cols = cols;
    view->backing_rows = rows;
    view->backing_valid = 0;
  }
  TerminalGlyphCell* glyph_cells = NULL;
  int use_backing = view->backing_cells != NULL;
  if (view->overlay_glyph_count > 0) {
    overlay_build_glyphs(view, cols, rows);
    if (view->glyph_cols == cols && view->glyph_rows == rows && view->glyph_cells) {
      glyph_cells = view->glyph_cells;
    }
  }
  int selective = (!view->line_mode && use_backing && view->backing_valid);

  size_t line_cap = (size_t)cols * 80 + 64;
  char* line = (char*)malloc(line_cap);
  if (!line) {
    return;
  }

  int any_output = 0;
  for (int row = 0; row < rows; ++row) {
    size_t idx = 0;
    int emitted = 0;
    int run_active = 0;
    if (!view->line_mode && !selective) {
      append_cursor_home(line, &idx, line_cap, row + 1);
    }
    int row_y[4] = {0, 0, 0, 0};
    int src_y_top = 0;
    int src_y_bottom = 0;
    if (braille_mode) {
      for (int sy = 0; sy < 4; ++sy) {
        int src_y = (row * 4 + sy) * height / sample_rows;
        row_y[sy] = height - 1 - src_y;
      }
    } else {
      src_y_top = (row * 2) * height / sample_rows;
      src_y_bottom = (row * 2 + 1) * height / sample_rows;
      src_y_top = height - 1 - src_y_top;
      src_y_bottom = height - 1 - src_y_bottom;
    }

    for (int col = 0; col < cols; ++col) {
      size_t cell_index = (size_t)row * (size_t)cols + (size_t)col;
      TerminalBlit blit;
      unsigned char cell[TERMINAL_VIEW_CELL_STRIDE];

      if (braille_mode) {
        blit_braille(rgb, width, cols, col, row_y, &blit);
      } else if (ascii_mode) {
        blit_ascii(rgb, width, cols, col, src_y_top, src_y_bottom, &blit);
      } else {
        blit_half(rgb, width, cols, col, src_y_top, src_y_bottom, &blit);
      }

      if (glyph_cells) {
        const TerminalGlyphCell* glyph = glyph_cells + cell_index;
        if (glyph->used) {
          blit.fg[0] = glyph->r;
          blit.fg[1] = glyph->g;
          blit.fg[2] = glyph->b;
          blit.bg[0] = blit.base_bg[0];
          blit.bg[1] = blit.base_bg[1];
          blit.bg[2] = blit.base_bg[2];
          blit.codepoint = (unsigned int)glyph->codepoint;
        }
      }

      cell[0] = blit.fg[0];
      cell[1] = blit.fg[1];
      cell[2] = blit.fg[2];
      cell[3] = blit.bg[0];
      cell[4] = blit.bg[1];
      cell[5] = blit.bg[2];
      cell[6] = (unsigned char)(blit.codepoint & 0xFFu);
      cell[7] = (unsigned char)((blit.codepoint >> 8) & 0xFFu);
      cell[8] = (unsigned char)((blit.codepoint >> 16) & 0xFFu);
      cell[9] = (unsigned char)((blit.codepoint >> 24) & 0xFFu);

      unsigned char* prev = NULL;
      if (use_backing) {
        prev = view->backing_cells + cell_index * TERMINAL_VIEW_CELL_STRIDE;
      }
      int same = selective && prev && cell_similar(prev, cell);
      if (prev) {
        memcpy(prev, cell, TERMINAL_VIEW_CELL_STRIDE);
      }

      if (view->line_mode || !selective) {
        append_cell(line, &idx, line_cap, blit.codepoint, blit.fg, blit.bg);
        emitted = 1;
        continue;
      }

      if (same) {
        run_active = 0;
        continue;
      }

      if (!run_active) {
        append_cursor_pos(line, &idx, line_cap, row + 1, col + 1);
        run_active = 1;
      }
      append_cell(line, &idx, line_cap, blit.codepoint, blit.fg, blit.bg);
      emitted = 1;
    }

    if (emitted) {
      if (idx + 8 < line_cap) {
        line[idx++] = '\x1b';
        line[idx++] = '[';
        line[idx++] = '0';
        line[idx++] = 'm';
      }
      if (view->line_mode && idx + 1 < line_cap) {
        line[idx++] = '\n';
      }
      fwrite(line, 1, idx, stdout);
      any_output = 1;
    }
  }

  if (use_backing) {
    view->backing_valid = 1;
  }
  free(line);
  if (!view->line_mode && view->clear_rest) {
    fprintf(stdout, "\x1b[%d;1H\x1b[0J", rows + 1);
    any_output = 1;
  }
  if (any_output) {
    fflush(stdout);
  }
}

void terminal_view_shutdown(TerminalView* view) {
  if (!view) {
    return;
  }
  fprintf(stdout, "\x1b[0m\x1b[?25h\n");
  fflush(stdout);
  free(view->backing_cells);
  view->backing_cells = NULL;
  view->backing_cols = 0;
  view->backing_rows = 0;
  view->backing_valid = 0;
  free(view->overlay_glyphs);
  view->overlay_glyphs = NULL;
  view->overlay_glyph_count = 0;
  view->overlay_glyph_capacity = 0;
  free(view->glyph_cells);
  view->glyph_cells = NULL;
  view->glyph_cols = 0;
  view->glyph_rows = 0;
  view->initialized = 0;
}

void terminal_view_clear_overlays(TerminalView* view) {
  if (!view) {
    return;
  }
  view->overlay_glyph_count = 0;
  view->backing_valid = 0;
}

void terminal_view_add_glyph(TerminalView* view, float x, float y, int codepoint,
                             unsigned char r, unsigned char g, unsigned char b) {
  if (!view) {
    return;
  }
  if (view->overlay_glyph_count >= view->overlay_glyph_capacity) {
    int next = view->overlay_glyph_capacity > 0 ? view->overlay_glyph_capacity * 2 : 8;
    TerminalOverlayGlyph* glyphs = (TerminalOverlayGlyph*)realloc(
        view->overlay_glyphs, (size_t)next * sizeof(TerminalOverlayGlyph));
    if (!glyphs) {
      return;
    }
    view->overlay_glyphs = glyphs;
    view->overlay_glyph_capacity = next;
  }
  TerminalOverlayGlyph* glyph = view->overlay_glyphs + view->overlay_glyph_count++;
  glyph->x = x;
  glyph->y = y;
  glyph->codepoint = codepoint;
  glyph->r = r;
  glyph->g = g;
  glyph->b = b;
}

static TerminalView g_terminal_view;

void terminal_write_rgb_tiles(const unsigned char* rgb, int width, int height,
                              int cols, int rows) {
  if (!g_terminal_view.initialized ||
      g_terminal_view.override_cols != cols ||
      g_terminal_view.override_rows != rows) {
    terminal_view_shutdown(&g_terminal_view);
    terminal_view_init(&g_terminal_view, cols, rows,
                       g_terminal_view.fixed_size, g_terminal_view.clear_rest,
                       g_terminal_view.line_mode, g_terminal_view.braille_mode,
                       g_terminal_view.ascii_mode);
  }
  terminal_view_present(&g_terminal_view, rgb, width, height);
}

void terminal_write_rgb_tiles_config(int fixed_size, int clear_rest, int line_mode,
                                     int braille_mode, int ascii_mode) {
  g_terminal_view.fixed_size = fixed_size;
  g_terminal_view.clear_rest = clear_rest;
  g_terminal_view.line_mode = line_mode;
  g_terminal_view.braille_mode = braille_mode;
  g_terminal_view.ascii_mode = ascii_mode;
}

void terminal_write_rgb_tiles_shutdown(void) {
  terminal_view_shutdown(&g_terminal_view);
}
