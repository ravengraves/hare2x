#ifndef TERMINAL_VIEW_H_
#define TERMINAL_VIEW_H_

typedef struct {
  float x;
  float y;
  int codepoint;
  unsigned char r;
  unsigned char g;
  unsigned char b;
} TerminalOverlayGlyph;

typedef struct {
  int codepoint;
  unsigned char r;
  unsigned char g;
  unsigned char b;
  unsigned char used;
} TerminalGlyphCell;

typedef struct {
  int cols;
  int rows;
  int override_cols;
  int override_rows;
  int initialized;
  int fixed_size;
  int clear_rest;
  int line_mode;
  int braille_mode;
  int ascii_mode;
  int backing_cols;
  int backing_rows;
  int backing_valid;
  unsigned char* backing_cells;
  int overlay_glyph_count;
  int overlay_glyph_capacity;
  TerminalOverlayGlyph* overlay_glyphs;
  int glyph_cols;
  int glyph_rows;
  TerminalGlyphCell* glyph_cells;
} TerminalView;

void terminal_view_init(TerminalView* view, int cols, int rows,
                        int fixed_size, int clear_rest, int line_mode,
                        int braille_mode, int ascii_mode);
void terminal_view_present(TerminalView* view, const unsigned char* rgb,
                           int width, int height);
void terminal_view_shutdown(TerminalView* view);
void terminal_view_clear_overlays(TerminalView* view);
void terminal_view_add_glyph(TerminalView* view, float x, float y, int codepoint,
                             unsigned char r, unsigned char g, unsigned char b);

// Convenience API: write an RGB buffer directly to the terminal using Unicode tiles.
// cols/rows override the detected terminal size when > 0.
void terminal_write_rgb_tiles(const unsigned char* rgb, int width, int height,
                              int cols, int rows);
void terminal_write_rgb_tiles_config(int fixed_size, int clear_rest, int line_mode,
                                     int braille_mode, int ascii_mode);
void terminal_write_rgb_tiles_shutdown(void);

#endif  // TERMINAL_VIEW_H_
