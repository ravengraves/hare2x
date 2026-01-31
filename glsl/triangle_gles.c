#include <GLES2/gl2.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "terminal_view.h"

static volatile sig_atomic_t g_exit_signal = 0;
static int g_terminal_active = 0;
static int g_terminal_cleanup_done = 0;
static TerminalView* g_terminal_view_ptr = NULL;

static char* load_text_file(const char* path) {
  if (!path) {
    return NULL;
  }
  FILE* f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "Failed to open shader file: %s\n", path);
    return NULL;
  }
  if (fseek(f, 0, SEEK_END) != 0) {
    fclose(f);
    fprintf(stderr, "Failed to seek shader file: %s\n", path);
    return NULL;
  }
  long size = ftell(f);
  if (size < 0) {
    fclose(f);
    fprintf(stderr, "Failed to stat shader file: %s\n", path);
    return NULL;
  }
  if (fseek(f, 0, SEEK_SET) != 0) {
    fclose(f);
    fprintf(stderr, "Failed to rewind shader file: %s\n", path);
    return NULL;
  }
  char* buffer = (char*)malloc((size_t)size + 1u);
  if (!buffer) {
    fclose(f);
    fprintf(stderr, "Out of memory reading shader file: %s\n", path);
    return NULL;
  }
  size_t read_size = fread(buffer, 1u, (size_t)size, f);
  fclose(f);
  buffer[read_size] = '\0';
  return buffer;
}

static void terminal_cleanup(void) {
  if (!g_terminal_active || g_terminal_cleanup_done) {
    return;
  }
  g_terminal_cleanup_done = 1;
  if (g_terminal_view_ptr) {
    terminal_view_shutdown(g_terminal_view_ptr);
  } else {
    fprintf(stdout, "\x1b[0m\x1b[?25h\n");
    fflush(stdout);
  }
}

static void handle_signal(int signum) {
  g_exit_signal = signum;
}

static void install_signal_handlers(void) {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = handle_signal;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);
  sigaction(SIGHUP, &sa, NULL);
}

static GLuint compile_shader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
  GLint status = GL_FALSE;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
  if (status != GL_TRUE) {
    char log[1024];
    GLsizei len = 0;
    glGetShaderInfoLog(shader, sizeof(log), &len, log);
    fprintf(stderr, "Shader compile error: %s\n", log);
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

static GLuint create_program(const char* vs_src, const char* fs_src) {
  GLuint vs = compile_shader(GL_VERTEX_SHADER, vs_src);
  GLuint fs = compile_shader(GL_FRAGMENT_SHADER, fs_src);
  if (vs == 0 || fs == 0) {
    if (vs != 0) {
      glDeleteShader(vs);
    }
    if (fs != 0) {
      glDeleteShader(fs);
    }
    return 0;
  }
  GLuint program = glCreateProgram();
  glAttachShader(program, vs);
  glAttachShader(program, fs);
  glLinkProgram(program);
  GLint status = GL_FALSE;
  glGetProgramiv(program, GL_LINK_STATUS, &status);
  if (status != GL_TRUE) {
    char log[1024];
    GLsizei len = 0;
    glGetProgramInfoLog(program, sizeof(log), &len, log);
    fprintf(stderr, "Program link error: %s\n", log);
    glDeleteProgram(program);
    program = 0;
  }
  glDeleteShader(vs);
  glDeleteShader(fs);
  return program;
}

static void draw_triangle(GLuint program, GLuint vbo, GLint attr_pos,
                          GLint attr_color, GLint uni_angle, float angle) {
  glUseProgram(program);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glEnableVertexAttribArray(attr_pos);
  glEnableVertexAttribArray(attr_color);
  glVertexAttribPointer(attr_pos, 2, GL_FLOAT, GL_FALSE,
                        sizeof(GLfloat) * 5, (void*)0);
  glVertexAttribPointer(attr_color, 3, GL_FLOAT, GL_FALSE,
                        sizeof(GLfloat) * 5, (void*)(sizeof(GLfloat) * 2));
  glUniform1f(uni_angle, angle);
  glDrawArrays(GL_TRIANGLES, 0, 3);
}

static void rgba_to_rgb(unsigned char* dst, const unsigned char* src,
                        size_t pixel_count) {
  for (size_t i = 0; i < pixel_count; ++i) {
    dst[i * 3 + 0] = src[i * 4 + 0];
    dst[i * 3 + 1] = src[i * 4 + 1];
    dst[i * 3 + 2] = src[i * 4 + 2];
  }
}

static void print_usage(const char* prog) {
  printf("Usage: %s [--seconds N] [--headless] [--width N] [--height N]\n", prog);
  printf("       %s [--terminal] [--terminal-fps N] [--term-cols N] [--term-rows N]\n", prog);
  printf("       %s [--term-fixed] [--term-clear]\n", prog);
  printf("       %s [--term-cursor] [--term-braille] [--term-ascii]\n", prog);
  printf("       %s --vertex PATH --fragment PATH\n", prog);
}

int main(int argc, char** argv) {
  double seconds = 10.0;
  int headless = 0;
  int width = 640;
  int height = 480;
  int terminal = 0;
  double terminal_fps = 0.0;
  int term_cols = 0;
  int term_rows = 0;
  int term_fixed = 0;
  int term_clear = 0;
  int term_line_mode = 1;
  int term_braille = 0;
  int term_ascii = 0;
  const char* vertex_path = NULL;
  const char* fragment_path = NULL;
  int exit_code = 0;

  install_signal_handlers();

  for (int i = 1; i < argc; ++i) {
    if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
      seconds = atof(argv[++i]);
    } else if (strcmp(argv[i], "--headless") == 0) {
      headless = 1;
    } else if (strcmp(argv[i], "--terminal") == 0) {
      terminal = 1;
    } else if (strcmp(argv[i], "--terminal-fps") == 0 && i + 1 < argc) {
      terminal_fps = atof(argv[++i]);
    } else if (strcmp(argv[i], "--term-cols") == 0 && i + 1 < argc) {
      term_cols = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--term-rows") == 0 && i + 1 < argc) {
      term_rows = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--term-fixed") == 0) {
      term_fixed = 1;
    } else if (strcmp(argv[i], "--term-clear") == 0) {
      term_clear = 1;
    } else if (strcmp(argv[i], "--term-cursor") == 0) {
      term_line_mode = 0;
    } else if (strcmp(argv[i], "--term-braille") == 0) {
      term_braille = 1;
    } else if (strcmp(argv[i], "--term-ascii") == 0) {
      term_ascii = 1;
    } else if (strcmp(argv[i], "--width") == 0 && i + 1 < argc) {
      width = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--height") == 0 && i + 1 < argc) {
      height = atoi(argv[++i]);
    } else if (strcmp(argv[i], "--vertex") == 0 && i + 1 < argc) {
      vertex_path = argv[++i];
    } else if (strcmp(argv[i], "--fragment") == 0 && i + 1 < argc) {
      fragment_path = argv[++i];
    } else {
      print_usage(argv[0]);
      return 1;
    }
  }

  if (terminal && terminal_fps <= 0.0) {
    terminal_fps = 1.0;
  }

  if (!glfwInit()) {
    fprintf(stderr, "Failed to initialize GLFW.\n");
    return 1;
  }

  glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);
  glfwWindowHint(GLFW_DOUBLEBUFFER, GLFW_TRUE);
  glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);
  if (headless) {
    glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
  }

  GLFWwindow* window = glfwCreateWindow(width, height, "GLES Triangle", NULL, NULL);
  if (!window) {
    fprintf(stderr, "Failed to create GLFW window.\n");
    glfwTerminate();
    return 1;
  }

  glfwMakeContextCurrent(window);
  glfwSwapInterval(1);

  if (!vertex_path || !fragment_path) {
    fprintf(stderr, "Missing shader paths (use --vertex and --fragment).\n");
    print_usage(argv[0]);
    glfwTerminate();
    return 1;
  }

  char* vertex_src = load_text_file(vertex_path);
  if (!vertex_src) {
    glfwTerminate();
    return 1;
  }
  char* fragment_src = load_text_file(fragment_path);
  if (!fragment_src) {
    free(vertex_src);
    glfwTerminate();
    return 1;
  }
  GLuint program = create_program(vertex_src, fragment_src);
  if (program == 0) {
    free(vertex_src);
    free(fragment_src);
    glfwDestroyWindow(window);
    glfwTerminate();
    return 1;
  }
  GLint attr_pos = glGetAttribLocation(program, "a_pos");
  GLint attr_color = glGetAttribLocation(program, "a_color");
  GLint uni_angle = glGetUniformLocation(program, "u_angle");

  const GLfloat vertices[] = {
      0.0f,  0.6f,  1.0f, 0.0f, 0.0f,
     -0.5f, -0.4f, 0.0f, 1.0f, 0.0f,
      0.5f, -0.4f, 0.0f, 0.0f, 1.0f,
  };

  GLuint vbo = 0;
  glGenBuffers(1, &vbo);
  glBindBuffer(GL_ARRAY_BUFFER, vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

  int render_width = width;
  int render_height = height;
  int fbw = 0;
  int fbh = 0;
  glfwGetFramebufferSize(window, &fbw, &fbh);
  if (fbw > 0 && fbh > 0) {
    render_width = fbw;
    render_height = fbh;
  }

  int use_fbo = terminal;
  GLuint fbo = 0;
  GLuint color_rb = 0;
  if (use_fbo) {
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &color_rb);
    glBindRenderbuffer(GL_RENDERBUFFER, color_rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4, render_width, render_height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER, color_rb);
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      fprintf(stderr, "FBO incomplete: 0x%04x\n", (unsigned)status);
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
      glDeleteRenderbuffers(1, &color_rb);
      glDeleteFramebuffers(1, &fbo);
      color_rb = 0;
      fbo = 0;
      use_fbo = 0;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  }

  TerminalView term_view;
  memset(&term_view, 0, sizeof(term_view));
  unsigned char* frame_rgb = NULL;
  size_t frame_rgb_size = 0;
  unsigned char* readback_rgba = NULL;
  size_t readback_rgba_size = 0;
  double next_frame = 0.0;
  if (terminal) {
    terminal_view_init(&term_view, term_cols, term_rows, term_fixed, term_clear,
                       term_line_mode, term_braille, term_ascii);
    g_terminal_active = 1;
    g_terminal_view_ptr = &term_view;
    atexit(terminal_cleanup);
  }

  double start = glfwGetTime();
  while (!glfwWindowShouldClose(window)) {
    double now = glfwGetTime();
    if (g_exit_signal != 0) {
      break;
    }
    if (seconds > 0.0 && (now - start) >= seconds) {
      break;
    }

    int draw_w = render_width;
    int draw_h = render_height;
    if (!use_fbo) {
      glfwGetFramebufferSize(window, &draw_w, &draw_h);
    }

    if (draw_w <= 0 || draw_h <= 0) {
      glfwPollEvents();
      continue;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, use_fbo ? fbo : 0);
    glViewport(0, 0, draw_w, draw_h);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    float angle = (float)((now - start) * 1.5);
    draw_triangle(program, vbo, attr_pos, attr_color, uni_angle, angle);

    int need_readback = (terminal && now >= next_frame);
    if (need_readback) {
      size_t pixel_count = (size_t)draw_w * (size_t)draw_h;
      size_t rgba_needed = pixel_count * 4u;
      size_t rgb_needed = pixel_count * 3u;
      if (rgba_needed > readback_rgba_size) {
        unsigned char* next = (unsigned char*)realloc(readback_rgba, rgba_needed);
        if (next) {
          readback_rgba = next;
          readback_rgba_size = rgba_needed;
        }
      }
      if (rgb_needed > frame_rgb_size) {
        unsigned char* next = (unsigned char*)realloc(frame_rgb, rgb_needed);
        if (next) {
          frame_rgb = next;
          frame_rgb_size = rgb_needed;
        }
      }
      if (readback_rgba && frame_rgb) {
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadPixels(0, 0, draw_w, draw_h, GL_RGBA, GL_UNSIGNED_BYTE,
                     readback_rgba);
        rgba_to_rgb(frame_rgb, readback_rgba, pixel_count);
        if (terminal && now >= next_frame) {
          terminal_view_present(&term_view, frame_rgb, draw_w, draw_h);
          next_frame = now + 1.0 / terminal_fps;
        }
      }
    }

    if (use_fbo && !headless) {
      int win_w = 0;
      int win_h = 0;
      glfwGetFramebufferSize(window, &win_w, &win_h);
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
      glViewport(0, 0, win_w, win_h);
      glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
      draw_triangle(program, vbo, attr_pos, attr_color, uni_angle, angle);
    }

    if (!headless || !use_fbo) {
      glfwSwapBuffers(window);
    }
    glfwPollEvents();
  }

  terminal_cleanup();
  free(frame_rgb);
  free(readback_rgba);
  if (color_rb) {
    glDeleteRenderbuffers(1, &color_rb);
  }
  if (fbo) {
    glDeleteFramebuffers(1, &fbo);
  }
  glDeleteBuffers(1, &vbo);
  glDeleteProgram(program);

  glfwDestroyWindow(window);
  glfwTerminate();
  free(vertex_src);
  free(fragment_src);
  if (g_exit_signal != 0) {
    exit_code = 128 + g_exit_signal;
  }
  return exit_code;
}
