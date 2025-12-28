#!/usr/bin/env python3
"""
Hare-to-C11 Transpiler - OMeta-style Edition

Pattern-matching transformations:
1. AST → Typed AST (add type info)
2. Typed AST → C code (using rewrite rules)

Key patterns:
- return TYPE_NAME in tagged union → return Union_from_TYPE_NAME()
- return EXPR in tagged union → return Union_from_type(EXPR)
- match case TYPE => body → case TAG: { ... }
"""

import re
import sys

# =============================================================================
# TOKENIZER
# =============================================================================

TOKENS = [
    ('COMMENT', r'//[^\n]*'), ('FLOAT', r'\d+\.\d+(?:f32|f64)?'),
    ('INT', r'(?:0x[0-9a-fA-F_]+|0o[0-7_]+|0b[01_]+|\d[0-9_]*)(?:i8|i16|i32|i64|u8|u16|u32|u64|z)?'),
    ('STR', r'"(?:[^"\\]|\\.)*"'), ('RUNE', r"'(?:[^'\\]|\\.)'"),
    ('...', r'\.\.\.'), ('..', r'\.\.'), ('=>',
                                          r'=>'), ('==', r'=='), ('!=', r'!='),
    ('<=', r'<='), ('>=', r'>='), ('<<', r'<<'), ('>>', r'>>'),
    ('&&', r'&&'), ('||', r'\|\|'), ('^^', r'\^\^'),
    ('+=', r'\+='), ('-=', r'-='), ('*=', r'\*='), ('/=', r'/='), ('%=', r'%='),
    ('&=', r'&='), ('|=', r'\|='), ('^=', r'\^='),
    ('OP', r'[+\-*/%&|^~!<>=@?:;,.\[\](){}#]'), ('ID',
                                                 r'[a-zA-Z_]\w*'), ('WS', r'\s+'),
]

KEYWORDS = set('fn let const type struct union return if else for break continue match switch '
               'case yield defer export use true false null void bool str rune '
               'i8 i16 i32 i64 u8 u16 u32 u64 int uint f32 f64 size uintptr '
               'nullable static alloc free append insert delete len assert abort _'.split())

TOKEN_RE = re.compile('|'.join(f'(?P<{n.replace(".", "DOT").replace("+","PLUS").replace("-","MINUS").replace("*","STAR").replace("/","SLASH").replace("%","PCT").replace("&","AMP").replace("|","PIPE").replace("^","CARET").replace("=","EQ").replace("<","LT").replace(">","GT").replace("!","BANG")}>{p})' for n, p in TOKENS))


def tokenize(src):
    toks, ln, col = [], 1, 1
    for m in TOKEN_RE.finditer(src):
        k, v = m.lastgroup, m.group()
        k = k.replace('DOT', '.').replace('PLUS', '+').replace('MINUS', '-').replace('STAR', '*').replace('SLASH', '/').replace('PCT', '%').replace(
            'AMP', '&').replace('PIPE', '|').replace('CARET', '^').replace('EQ', '=').replace('LT', '<').replace('GT', '>').replace('BANG', '!')
        if k == 'WS':
            ln += v.count('\n')
            col = len(v) - v.rfind('\n') if '\n' in v else col + len(v)
            continue
        if k == 'COMMENT':
            ln += 1
            col = 1
            continue
        if k == 'ID' and v in KEYWORDS:
            k = 'KW'
        toks.append((k, v, ln, col))
        col += len(v)
    toks.append(('EOF', '', ln, col))
    return toks

# =============================================================================
# PARSER (minimal, same as before)
# =============================================================================


class P:
    def __init__(s, t): s.t, s.i = t, 0
    def pk(s, n=0): return s.t[min(s.i+n, len(s.t)-1)]
    def at(s, *k): t = s.pk(); return t[0] in k or t[1] in k

    def eat(s, *k): return (s.t[s.i], setattr(s,
                                              'i', s.i+1))[0] if s.at(*k) else None

    def need(s, k):
        if not s.at(k):
            raise SyntaxError(f"Expected {k}, got {s.pk()}")
        return s.eat(k)

    def val(s, k): return s.need(k)[1]


def p_type(p):
    if p.eat('!'):
        return ('T:err', p_type(p))
    if p.eat('nullable'):
        p.need('*')
        return ('T:ptr', p_type(p), True)
    if p.eat('*'):
        return ('T:ptr', p_type(p), False)
    if p.eat('['):
        if p.eat(']'):
            return ('T:slice', p_type(p))
        if p.eat('_'):
            p.need(']')
            return ('T:arr', p_type(p), None, True)
        if p.eat('*'):
            p.need(']')
            return ('T:uarr', p_type(p))
        sz = p_expr(p)
        p.need(']')
        return ('T:arr', p_type(p), sz[1] if sz[0] == 'lit' else None, False)
    if p.eat('struct'):
        return p_struct_type(p)
    if p.eat('fn'):
        return p_fn_type(p)
    if p.eat('('):
        return p_tuple_or_tagged(p)
    if p.at('KW'):
        return ('T:prim', p.eat('KW')[1])
    if p.at('ID'):
        return p_type_path(p)
    raise SyntaxError(f"Expected type at {p.pk()}")


def p_struct_type(p):
    p.need('{')
    fs = []
    while not p.eat('}'):
        n = p.val('ID')
        p.need(':')
        fs.append((n, p_type(p)))
        if not p.eat(','):
            p.need('}')
            break
    return ('T:struct', fs)


def p_fn_type(p):
    p.need('(')
    ps = []
    while not p.eat(')'):
        if ps:
            p.need(',')
        n = p.val('ID') if p.pk(1)[1] == ':' else '_'
        if n != '_':
            p.need(':')
        ps.append((n, p_type(p)))
    return ('T:fn', ps, p_type(p))


def p_tuple_or_tagged(p):
    sp = bool(p.eat('...'))
    t1 = p_type(p)
    ts = [(t1, sp)]
    if p.eat('|'):
        while True:
            sp = bool(p.eat('...'))
            ts.append((p_type(p), sp))
            if not p.eat('|'):
                break
        p.need(')')
        return ('T:tagged', [t for t, _ in ts], [s for _, s in ts])
    while p.eat(','):
        if p.at(')'):
            break
        ts.append((p_type(p), False))
    p.need(')')
    return ts[0][0] if len(ts) == 1 else ('T:tuple', [t for t, _ in ts])


def p_type_path(p):
    ps = [p.val('ID')]
    while p.at(':') and p.pk(1)[1] == ':':
        p.eat(':')
        p.eat(':')
        ps.append(p.val('ID'))
    return ('T:alias', '::'.join(ps))


PREC = {'||': 1, '^^': 2, '&&': 3, '==': 4, '!=': 4, '<': 5, '>': 5, '<=': 5, '>=': 5,
        '|': 6, '^': 7, '&': 8, '<<': 9, '>>': 9, '+': 10, '-': 10, '*': 11, '/': 11, '%': 11}


def p_expr(p, mp=0):
    l = p_unary(p)
    while True:
        t = p.pk()
        op = t[1] if t[0] == 'OP' else t[0]
        pr = PREC.get(op, -1)
        if pr < mp:
            break
        p.eat(t[0], t[1])
        l = ('bin', op, l, p_expr(p, pr+1))
    return l


def p_unary(p):
    if op := p.eat('-', '!', '~', '*', '&'):
        return ('un', op[1], p_unary(p))
    if p.eat('match'):
        return p_match(p)
    if p.eat('switch'):
        return p_switch(p)
    return p_postfix(p)


COMPOUND = {'+=': 1, '-=': 1, '*=': 1, '/=': 1,
            '%=': 1, '&=': 1, '|=': 1, '^=': 1}


def p_postfix(p):
    l = p_primary(p)
    while True:
        if p.eat('('):
            args = []
            while not p.eat(')'):
                if args:
                    p.need(',')
                a = p_expr(p)
                if p.eat('...'):
                    a = ('spread', a)
                args.append(a)
            l = ('call', l, args)
        elif p.eat('['):
            if p.eat('..'):
                e = None if p.at(']') else p_expr(p)
                p.need(']')
                l = ('slice', l, None, e)
            else:
                s = p_expr(p)
                if p.eat('..'):
                    e = None if p.at(']') else p_expr(p)
                    p.need(']')
                    l = ('slice', l, s, e)
                else:
                    p.need(']')
                    l = ('idx', l, s)
        elif p.eat('.'):
            l = ('fld', l, p.val('INT') if p.at('INT') else p.val('ID'))
        elif p.eat('?'):
            l = ('prop', l)
        elif p.eat('!'):
            l = ('unwrap', l)
        elif p.eat(':'):
            l = ('cast', l, p_type(p))
        elif p.eat('as'):
            l = ('cast', l, p_type(p))
        elif p.eat('is'):
            l = ('is', l, p_type(p))
        elif (op := p.pk()) and op[1] in COMPOUND:
            p.eat(op[0], op[1])
            l = ('asgn_e', l, op[1], p_expr(p))
        else:
            break
    return l


def p_len(p): p.need('('); e = p_expr(p); p.need(')'); return ('len', e)
def p_size(p): p.need('('); t = p_type(p); p.need(')'); return ('size', t)
def p_free(p): p.need('('); e = p_expr(p); p.need(')'); return ('free', e)


def p_alloc(p):
    p.need('(')
    e = p_expr(p)
    if p.eat('...'):
        p.need(')')
        return ('alloc_cp', e)
    if p.eat(','):
        c = p_expr(p)
        p.need(')')
        return ('alloc_sl', e, c)
    p.need(')')
    return ('alloc', e)


def p_append(p, st):
    p.need('(')
    t = p_expr(p)
    p.need(',')
    v = p_expr(p)
    va = bool(p.eat('...'))
    p.need(')')
    return ('append', t, v, va, st)


def p_insert(p, st):
    p.need('(')
    t = p_expr(p)
    p.need(',')
    v = p_expr(p)
    va = bool(p.eat('...'))
    p.need(')')
    return ('insert', t, v, va, st)


def p_delete(p, st): p.need('('); t = p_expr(
    p); p.need(')'); return ('delete', t, st)


def p_assert_b(p):
    p.need('(')
    c = p_expr(p)
    m = p_expr(p) if p.eat(',') else None
    p.need(')')
    return ('assert_b', c, m)


def p_abort(p):
    p.need('(')
    m = p_expr(p) if not p.at(')') else None
    p.need(')')
    return ('abort', m)


BUILTINS = {
    'len': p_len, 'size': p_size, 'free': p_free, 'alloc': p_alloc,
    'assert': p_assert_b, 'abort': p_abort,
    'append': lambda p: p_append(p, False), 'insert': lambda p: p_insert(p, False),
    'delete': lambda p: p_delete(p, False),
}


def p_int(s):
    suf = None
    for sf in ['i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'z']:
        if s.endswith(sf):
            suf, s = sf, s[:-len(sf)]
            break
    s = s.replace('_', '')
    return (int(s, 16) if s.startswith('0x') else int(s, 8) if s.startswith('0o') else
            int(s, 2) if s.startswith('0b') else int(s)), suf


def p_primary(p):
    if t := p.eat('INT'):
        v, sf = p_int(t[1])
        return ('lit', v, sf)
    if t := p.eat('FLOAT'):
        return ('lit', float(t[1].rstrip('f32f64')), 'f32' if 'f32' in t[1] else 'f64' if 'f64' in t[1] else None)
    if t := p.eat('STR'):
        return ('lit', t[1][1:-1], 'str')
    if t := p.eat('RUNE'):
        return ('lit', ord(t[1][1]) if len(t[1]) == 3 else ord(t[1][2]), 'rune')
    if p.eat('true'):
        return ('lit', True, 'bool')
    if p.eat('false'):
        return ('lit', False, 'bool')
    if p.eat('null'):
        return ('lit', None, 'null')
    if p.eat('void'):
        return ('lit', None, 'void')
    for kw, fn in BUILTINS.items():
        if p.eat(kw):
            return fn(p)
    if p.eat('static'):
        if p.eat('append'):
            return p_append(p, True)
        if p.eat('insert'):
            return p_insert(p, True)
        if p.eat('delete'):
            return p_delete(p, True)
    if p.eat('offset'):
        p.need('(')
        e = p_expr(p)
        p.need(')')
        return ('call', ('id', 'offset'), [e])
    if p.eat('{'):
        return p_block(p)
    if p.eat('['):
        return p_array_lit(p)
    if p.eat('('):
        e = p_expr(p)
        p.need(')')
        return e
    if p.eat('struct'):
        return p_struct_lit(p, None)
    if p.eat('if'):
        return p_if(p)
    if p.eat('for'):
        return p_for(p)
    if p.eat('yield'):
        return ('yield', p_expr(p))
    if p.at('ID'):
        n = p_type_path(p)
        if n[0] == 'T:alias' and p.at('{'):
            return p_struct_lit(p, n[1])
        return ('id', n[1]) if n[0] == 'T:alias' else n
    raise SyntaxError(f"Unexpected {p.pk()}")


def p_block(p):
    ss, r = [], None
    while not p.at('}'):
        if p.eat('yield'):
            r = p_expr(p)
            p.need(';')
        else:
            ss.append(p_stmt(p))
    p.need('}')
    return ('block', ss, r)


def p_array_lit(p):
    es, fill = [], None
    while not p.eat(']'):
        if es:
            p.need(',')
        if p.at(']'):
            break
        e = p_expr(p)
        if p.eat('...'):
            fill = e
            p.need(']')
            return ('arr_lit', es, fill)
        es.append(e)
    return ('arr_lit', es, fill)


def p_struct_lit(p, name):
    p.need('{')
    fs = []
    while not p.eat('}'):
        fn = p.val('ID')
        if p.eat(':'):
            p_type(p)
        p.need('=')
        fs.append((fn, p_expr(p)))
        if not p.eat(','):
            p.need('}')
            break
    return ('struct_lit', name, fs)


def p_if(p):
    p.need('(')
    c = p_expr(p)
    p.need(')')
    t = p_expr(p)
    e = p_expr(p) if p.eat('else') else None
    return ('if', c, t, e)


def p_for(p):
    p.need('(')
    init = None
    if not p.at(';', ')'):
        init = p_let_nosemi(p, True) if p.eat('let') else p_expr(p)
    if p.at(')'):
        p.need(')')
        return ('for', None, init, None, p_expr(p))
    p.need(';')
    cond = p_expr(p) if not p.at(';') else None
    p.need(';')
    after = p_expr(p) if not p.at(')') else None
    p.need(')')
    return ('for', init, cond, after, p_expr(p))


def p_match(p):
    p.need('(')
    v = p_expr(p)
    p.need(')')
    p.need('{')
    cs = []
    while not p.eat('}'):
        if p.eat('case'):
            bind = None
            if p.eat('let'):
                bind = p.val('ID')
                p.need(':')
            ty = p_type(p)
            p.need('=>')
            if p.at('{'):
                body = p_expr(p)
                p.need(';')
            else:
                ss = []
                while not p.at('case', '}'):
                    ss.append(p_stmt(p))
                body = ('block', ss, None) if len(
                    ss) > 1 else ss[0] if ss else ('lit', None, 'void')
            cs.append(('case', ty, bind, body))
    return ('match', v, cs)


def p_switch(p):
    p.need('(')
    v = p_expr(p)
    p.need(')')
    p.need('{')
    cs = []
    while not p.eat('}'):
        if p.eat('case'):
            if p.at('=>'):
                p.need('=>')
                body = p_expr(p)
                p.need(';')
                cs.append(('default', [], body))
            else:
                vs = [p_expr(p)]
                while p.eat(','):
                    vs.append(p_expr(p))
                p.need('=>')
                body = p_expr(p)
                p.need(';')
                cs.append(('case', vs, body))
    return ('switch', v, cs)


def p_let(p, mut):
    bs = []
    while True:
        n = p.val('ID')
        ty = p_type(p) if p.eat(':') else None
        init = p_expr(p) if p.eat('=') else None
        bs.append((n, ty, init))
        if not p.eat(','):
            break
    p.need(';')
    return ('let', bs[0][0], bs[0][1], bs[0][2], mut) if len(bs) == 1 else ('mlet', bs, mut)


def p_let_nosemi(p, mut):
    n = p.val('ID')
    ty = p_type(p) if p.eat(':') else None
    init = p_expr(p) if p.eat('=') else None
    return ('let', n, ty, init, mut)


def p_static_let(p, mut):
    n = p.val('ID')
    ty = p_type(p) if p.eat(':') else None
    init = p_expr(p) if p.eat('=') else None
    p.need(';')
    return ('slet', n, ty, init, mut)


def p_stmt(p):
    if p.eat('let'):
        return p_let(p, True)
    if p.eat('const'):
        return p_let(p, False)
    if p.eat('static'):
        if p.eat('let'):
            return p_static_let(p, True)
        if p.eat('const'):
            return p_static_let(p, False)
        if p.eat('append'):
            e = p_append(p, True)
            p.need(';')
            return ('expr', e)
        if p.eat('insert'):
            e = p_insert(p, True)
            p.need(';')
            return ('expr', e)
        if p.eat('delete'):
            e = p_delete(p, True)
            p.need(';')
            return ('expr', e)
    if p.eat('return'):
        v = p_expr(p) if not p.at(';') else None
        p.need(';')
        return ('ret', v)
    if p.eat('break'):
        lb = p.val('ID') if p.at('ID') else None
        p.need(';')
        return ('break', lb)
    if p.eat('continue'):
        lb = p.val('ID') if p.at('ID') else None
        p.need(';')
        return ('cont', lb)
    if p.eat('defer'):
        e = p_expr(p)
        p.need(';')
        return ('defer', e)
    if p.eat('yield'):
        v = p_expr(p)
        p.need(';')
        return ('yield', v)
    if p.eat('if'):
        r = p_if(p)
        p.eat(';')
        return r
    if p.eat('for'):
        r = p_for(p)
        p.eat(';')
        return r
    e = p_expr(p)
    if op := p.eat('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^='):
        v = p_expr(p)
        p.need(';')
        return ('asgn', e, op[1], v)
    p.need(';')
    return ('expr', e)


def p_fn(p, exp, fn_eaten=False):
    attrs = []
    while p.eat('@'):
        attrs.append(p.val('ID'))
    if not fn_eaten:
        p.need('fn')
    name = p.val('ID')
    p.need('(')
    ps, va = [], False
    while not p.eat(')'):
        if ps:
            p.need(',')
        pn = p.val('ID')
        p.need(':')
        pt = p_type(p)
        if p.eat('...'):
            va = True
            pt = ('T:slice', pt)
        df = p_expr(p) if p.eat('=') else None
        ps.append((pn, pt, df))
    ret = p_type(p)
    p.need('=')
    body = p_expr(p)
    p.need(';')
    return ('fn', name, ps, ret, body, exp, va, attrs)


def p_typedef(p, exp):
    name = p.val('ID')
    p.need('=')
    ty = p_type(p)
    p.need(';')
    return ('typedef', name, ty, exp)


def p_global(p, exp, mut):
    name = p.val('ID')
    p.need(':')
    ty = p_type(p)
    init = p_expr(p) if p.eat('=') else None
    p.need(';')
    return ('global', name, ty, init, exp, mut)


def p_def(p):
    name = p.val('ID')
    ty = p_type(p) if p.eat(':') else None
    p.need('=')
    v = p_expr(p)
    p.need(';')
    return ('def', name, ty, v)


def p_decl(p):
    exp = bool(p.eat('export'))
    # Handle @attribute decorated functions
    if p.at('@'):
        return p_fn(p, exp, fn_eaten=False)
    if p.eat('fn'):
        return p_fn(p, exp, fn_eaten=True)
    if p.eat('type'):
        return p_typedef(p, exp)
    if p.eat('let'):
        return p_global(p, exp, True)
    if p.eat('const'):
        return p_global(p, exp, False)
    if p.eat('def'):
        return p_def(p)
    if p.eat('use'):
        while not p.eat(';'):
            p.i += 1
        return None
    raise SyntaxError(f"Expected decl at {p.pk()}")


def p_unit(p):
    ds = []
    while not p.at('EOF'):
        if d := p_decl(p):
            ds.append(d)
    return ds

# =============================================================================
# TYPE REGISTRY & CONTEXT
# =============================================================================


class Ctx:
    """Compilation context for type tracking."""

    def __init__(self):
        self.types = {}      # name -> underlying type
        self.tagged = {}     # name -> list of variant types
        self.vars = {}       # name -> type
        self.funcs = {}      # name -> {params, variadic}
        self.needed_slice_typedefs = {}  # name -> (inner_type, arr_size)
        self.ret_type = None  # current function return type
        self.ret_name = None  # current function return type name (for tagged)
        self.expected_type = None  # expected type for current expression

    def register_type(self, name, ty):
        self.types[name] = ty
        # If tagged union, also register variants
        if ty[0] == 'T:tagged':
            self.tagged[name] = ty[1]  # list of variant types

    def is_type_name(self, name):
        return name in self.types

    def is_tagged_return(self):
        return self.ret_name and self.ret_name in self.tagged

    def get_variant_types(self, name):
        return self.tagged.get(name, [])

    def find_variant_index(self, type_name):
        """Find which variant index a type name corresponds to."""
        if not self.ret_name or self.ret_name not in self.tagged:
            return -1
        variants = self.tagged[self.ret_name]
        for i, v in enumerate(variants):
            if v[0] == 'T:alias' and v[1] == type_name:
                return i
            if v[0] == 'T:prim' and v[1] == type_name:
                return i
        return -1

    def register_fn(self, name, params, variadic):
        """Register function with its parameter info."""
        self.funcs[name] = {'params': params, 'variadic': variadic}

    def get_fn_info(self, name):
        """Get function info if registered."""
        return self.funcs.get(name)


CTX = Ctx()

# =============================================================================
# CODE GENERATOR
# =============================================================================

TYPE_MAP = {
    'int': 'intptr_t', 'uint': 'uintptr_t', 'i8': 'int8_t', 'i16': 'int16_t', 'i32': 'int32_t',
    'i64': 'int64_t', 'u8': 'uint8_t', 'u16': 'uint16_t', 'u32': 'uint32_t', 'u64': 'uint64_t',
    'f32': 'float', 'f64': 'double', 'bool': '_Bool', 'void': 'void', 'size': 'size_t',
    'uintptr': 'uintptr_t', 'str': 'hare_str', 'rune': 'uint32_t', 'never': 'void',
    'null': 'void*', 'done': 'int', 'nomem': 'int',
}

INT_SUF = {'i64': 'LL', 'u8': 'U', 'u16': 'U',
           'u32': 'U', 'u64': 'ULL', 'z': 'UL'}

PRELUDE = '''/* Generated by hare2c */
#include <stdint.h>
#include <stddef.h>
typedef struct { uint8_t* data; size_t len; } hare_str;
#define HARE_DEFINE_SLICE(T, name) typedef struct { T* data; size_t len; size_t cap; } name
HARE_DEFINE_SLICE(uint8_t, hare_slice_uint8_t);
HARE_DEFINE_SLICE(int32_t, hare_slice_int32_t);
HARE_DEFINE_SLICE(intptr_t, hare_slice_intptr_t);
#define HARE_ARRAY_LEN(x) (sizeof(x)/sizeof((x)[0]))
#define HARE_SLICE(c,s,e) (hare_slice_intptr_t){.data=(intptr_t*)(c)+(s),.len=(e)-(s),.cap=HARE_ARRAY_LEN(c)-(s)}
#define HARE_ASSERT(c,m) do{if(!(c))__extension__({__auto_type __msg=(m);__hare_abort((const char*)__msg.data);});}while(0)
#define HARE_ERROR_TAG_BASE 0x80000000U
extern void* __hare_malloc(size_t);
extern void* __hare_realloc(void*, size_t);
extern void* __hare_calloc(size_t, size_t);
extern void __hare_free(void*);
extern void __hare_abort(const char*) __attribute__((noreturn));
#define hare_alloc(i) __extension__({__auto_type __v=(i);__typeof__(__v)*__p=__hare_malloc(sizeof(__v));*__p=__v;__p;})
#define hare_alloc_copy(sl) __extension__({__auto_type __sl=(sl);__typeof__(__sl) __r;__r.data=__hare_malloc(__sl.len*sizeof(*__sl.data));__r.len=__sl.len;__r.cap=__sl.len;for(size_t __i=0;__i<__sl.len;++__i)__r.data[__i]=__sl.data[__i];__r;})
#define hare_free(p) __hare_free((void*)(p))
#define hare_append(sp,v) __extension__({__auto_type __sp=(sp);if(__sp->len>=__sp->cap){__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=__hare_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}__sp->data[__sp->len++]=(v);})
#define hare_insert(sp,i,v) __extension__({__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap){__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=__hare_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;})
#define hare_delete(sp,s,e) __extension__({__auto_type __sp=(sp);size_t __s=(s),__e=(e),__n=__e-__s;for(size_t __i=__s;__i+__n<__sp->len;++__i)__sp->data[__i]=__sp->data[__i+__n];__sp->len-=__n;})
#define hare_static_append(sp,v) __extension__({__auto_type __sp=(sp);if(__sp->len>=__sp->cap)__hare_abort("overflow");__sp->data[__sp->len++]=(v);})
#define hare_static_insert(sp,i,v) __extension__({__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap)__hare_abort("overflow");for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;})
#define hare_static_delete(sp,s,e) hare_delete(sp,s,e)
#define hare_slice_assign(d,s,e,src) __extension__({__auto_type __d=(d);__auto_type __src=(src);for(size_t __i=0;__i<(e)-(s);++__i)__d.data[(s)+__i]=__src.data[__i];})
'''


def tag_name(t):
    """Get C-safe tag name for a type."""
    k = t[0]
    if k == 'T:prim':
        return t[1]
    if k == 'T:alias':
        return t[1].replace('::', '_')
    if k == 'T:ptr':
        return 'ptr_' + tag_name(t[1])
    if k == 'T:err':
        return 'err_' + tag_name(t[1])
    if k == 'T:slice':
        return 'slice_' + tag_name(t[1])
    return 'anon'


def g_slice_type(elem_ty):
    """
    Generate slice type for a given element type.
    Pattern: []T where T is primitive → hare_slice_T
    Pattern: [][N]T → hare_slice_arrN_T (defined in prelude section)
    """
    # For array elements, generate a typedef name
    if elem_ty[0] == 'T:arr':
        inner_ty = elem_ty[1]
        arr_size = elem_ty[2]
        inner_name = g(inner_ty).replace(' ', '_').replace('*', 'ptr')
        if arr_size:
            # Register that we need this slice-of-array typedef
            typedef_name = f'hare_slice_arr{arr_size}_{inner_name}'
            CTX.needed_slice_typedefs[typedef_name] = (inner_ty, arr_size)
            return typedef_name
        else:
            return f'hare_slice_{inner_name}'

    # For primitive types, use predefined slice types
    elem_str = g(elem_ty).replace(' ', '_').replace('*', 'ptr')
    return f'hare_slice_{elem_str}'


def g(n):
    """Main code generator - pattern matching on AST nodes."""
    if n is None:
        return ''
    if isinstance(n, str):
        return n
    k = n[0]

    # === TYPE PATTERNS ===
    if k == 'T:prim':
        return TYPE_MAP.get(n[1], n[1])
    if k == 'T:ptr':
        return f'{g(n[1])}*'
    if k == 'T:slice':
        return g_slice_type(n[1])
    if k == 'T:arr':
        return g(n[1])
    if k == 'T:uarr':
        return f'{g(n[1])}*'
    if k == 'T:struct':
        return f'struct {{ {" ".join(g_decl(t, nm) + ";" for nm,t in n[1])} }}'
    if k == 'T:tuple':
        return f'struct {{ {" ".join(f"{g(t)} _{i};" for i,t in enumerate(n[1]))} }}'
    if k == 'T:tagged':
        return g_tagged_inline(n)
    if k == 'T:err':
        return 'struct{char __m;}' if g(n[1]) == 'void' else g(n[1])
    if k == 'T:alias':
        return n[1].replace('::', '_')
    if k == 'T:fn':
        return f'{g(n[2])} (*)({"void" if not n[1] else ", ".join(g(t) for _,t in n[1])})'

    # === LITERAL PATTERNS ===
    if k == 'lit':
        return g_lit(n)

    # === IDENTIFIER PATTERN - check if it's a type name in return context ===
    if k == 'id':
        name = n[1].replace('::', '_')
        # Don't transform here - let return handle it
        return name

    # === EXPRESSION PATTERNS ===
    if k == 'bin':
        if n[1] == '^^':
            return f'(({g(n[2])}) ? !({g(n[3])}) : ({g(n[3])}))'
        return f'({g(n[2])} {n[1]} {g(n[3])})'
    if k == 'un':
        return f'({n[1]}{g(n[2])})'
    if k == 'call':
        return g_call(n)
    if k == 'spread':
        return g(n[1])
    if k == 'idx':
        return g_idx(n)
    if k == 'slice':
        return g_slice_expr(n)
    if k == 'fld':
        return g_fld(n)
    if k == 'cast':
        return f'(({g(n[2])})({g(n[1])}))'
    if k == 'is':
        return f'(({g(n[1])}).tag==0U)'
    if k == 'if':
        return g_if(n)
    if k == 'block':
        return g_block(n)
    if k == 'arr_lit':
        return g_arr_lit(n)
    if k == 'struct_lit':
        return f'({n[1].replace("::","_") if n[1] else ""}){{ {", ".join(f".{fn}={g(fv)}" for fn,fv in n[2])} }}'
    if k == 'match':
        return g_match(n)
    if k == 'switch':
        return g_switch(n)
    if k == 'len':
        return g_len(n)
    if k == 'size':
        return f'sizeof({g(n[1][1])}[{n[1][2] or ""}])' if n[1][0] == 'T:arr' else f'sizeof({g(n[1])})'
    if k == 'alloc':
        return g_alloc(n)
    if k == 'alloc_cp':
        return f'hare_alloc_copy({g(n[1])})'
    if k == 'alloc_sl':
        return g_alloc_sl(n)
    if k == 'free':
        return g_free(n)
    if k == 'append':
        return f'{"hare_static_append" if n[4] else "hare_append"}(&{g(n[1])},{g(n[2])})'
    if k == 'insert':
        return f'{"hare_static_insert" if n[4] else "hare_insert"}(&{g(n[1][1])},{g(n[1][2])},{g(n[2])})' if n[1][0] == 'idx' else '/*insert err*/'
    if k == 'delete':
        return g_delete(n)
    if k == 'assert_b':
        if n[2]:
            msg = g(n[2])
        else:
            msg = '(hare_str){.data=(uint8_t*)"assertion failed",.len=16}'
        return f'HARE_ASSERT(({g(n[1])}),({msg}))'
    if k == 'abort':
        return '__hare_abort({})'.format({g(n[1]) or '"abort"'})
    if k == 'prop':
        return f'HARE_ERROR_PROPAGATE({g(n[1])})'
    if k == 'unwrap':
        return f'HARE_ERROR_ASSERT({g(n[1])})'
    if k == 'asgn_e':
        return f'({g(n[1])} {n[2]} {g(n[3])})'
    if k == 'yield':
        return f'__r = {g(n[1])};'

    # === STATEMENT PATTERNS ===
    if k == 'let':
        return g_let(n)
    if k == 'slet':
        return g_slet(n)
    if k == 'mlet':
        return '\n'.join(g(('let', nm, ty, ini, n[2])) for nm, ty, ini in n[1])
    if k == 'asgn':
        return g_asgn(n)
    if k == 'ret':
        return g_ret(n)  # Special handling for returns
    if k == 'break':
        return f'goto {n[1]}_break;' if n[1] else 'break;'
    if k == 'cont':
        return f'goto {n[1]}_continue;' if n[1] else 'continue;'
    if k == 'defer':
        return f'/* defer: {g(n[1])} */'
    if k == 'expr':
        return f'{g(n[1])};'
    if k == 'for':
        return f'for ({g(n[1]).rstrip(";") if n[1] else ""}; {g(n[2]) if n[2] else ""}; {g(n[3]).rstrip(";") if n[3] else ""}) {g(n[4])}'

    # === DECLARATION PATTERNS ===
    if k == 'fn':
        return g_fn(n)
    if k == 'typedef':
        return g_typedef(n)
    if k == 'global':
        return f'{"" if n[4] else "static "}{"" if n[5] else "const "}{g_decl(n[2],n[1])}{f" = {g(n[3])}" if n[3] else ""};'
    if k == 'def':
        return f'#define {n[1]} {f"(({g(n[2])})" if n[2] else ""}{g(n[3])}{")" if n[2] else ""}'

    return f'/* unknown: {k} */'

# === HELPER GENERATORS ===


def g_lit(n):
    v, h = n[1], n[2]
    if h == 'str':
        esc = v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
        return f'(hare_str){{.data=(uint8_t*)"{esc}",.len={len(v)}}}'
    if h == 'bool':
        return '1' if v else '0'
    if h == 'null':
        return 'NULL'
    if h == 'void':
        return '(void)0'
    if h == 'rune':
        return f'(uint32_t){v}'
    if isinstance(v, float):
        return f'{v}f' if h == 'f32' else str(v)
    return f'{v}{INT_SUF.get(h, "")}'


def g_decl(ty, name):
    """
    Generate C declaration for a type and name.
    Pattern matching for complex types:
    - Array: T name[N]
    - Function pointer: ret (*name)(args)
    - Pointer to function: ret (**name)(args)
    """
    if ty[0] == 'T:arr':
        dims = []
        while ty[0] == 'T:arr':
            dims.append(str(ty[2]) if ty[2] else '')
            ty = ty[1]
        return f'{g(ty)} {name}' + ''.join(f'[{d}]' for d in dims)

    # Pattern: pointer to function type → ret (*name)(args)
    if ty[0] == 'T:ptr' and ty[1][0] == 'T:fn':
        fn_ty = ty[1]
        ret_type = g(fn_ty[2])
        params = ', '.join(g(t) for _, t in fn_ty[1]) or 'void'
        return f'{ret_type} (*{name})({params})'

    # Pattern: function type (not pointer) → ret (*name)(args)
    if ty[0] == 'T:fn':
        ret_type = g(ty[2])
        params = ', '.join(g(t) for _, t in ty[1]) or 'void'
        return f'{ret_type} (*{name})({params})'

    return f'{g(ty)} {name}'


def g_tagged_inline(n):
    """Generate inline tagged union type."""
    types = n[1]
    fields = []
    for t in types:
        tag = tag_name(t)
        if is_void_type(t):
            fields.append(f'char _{tag}_m; /* void */')
        else:
            fields.append(f'{g(t)} _{tag};')
    return f'struct {{ uint32_t tag; union {{ {" ".join(fields)} }} value; }}'


def g_idx(n):
    """
    Generate indexing expression.
    Pattern: slice[i] → slice.data[i]
    Pattern: array[i] → array[i]
    Pattern: slice_of_arrays[i] → (*slice.data)[i] if needed
    """
    target, idx = n[1], n[2]

    # Check if target is a known slice variable
    if target[0] == 'id' and target[1] in CTX.vars:
        ty = CTX.vars[target[1]]
        if ty and ty[0] == 'T:slice':
            # For slices, access through .data
            return f'({g(target)}).data[{g(idx)}]'

    # Check if target is itself an index expression (nested indexing)
    # e.g., mat[i][j] where mat[i] gave us an array from a slice-of-arrays

    return f'({g(target)})[{g(idx)}]'


def g_fld(n):
    """
    Generate field access.
    Pattern: ptr.field → ptr->field
    Pattern: struct.field → struct.field
    """
    target, field = n[1], n[2]
    if target[0] == 'id' and target[1] in CTX.vars:
        ty = CTX.vars[target[1]]
        if ty and ty[0] == 'T:ptr':
            return f'{g(target)}->{field}'
    # Also check if target is a dereference or other pointer expression
    return f'{g(target)}.{field}'


def g_len(n):
    target = n[1]
    if target[0] == 'id' and target[1] in CTX.vars:
        ty = CTX.vars[target[1]]
        if ty:
            # Slices and strings have .len field
            if ty[0] == 'T:slice':
                return f'({g(target)}).len'
            if ty[0] == 'T:prim' and ty[1] == 'str':
                return f'({g(target)}).len'
    return f'HARE_ARRAY_LEN({g(target)})'


def g_slice_expr(n):
    """
    Generate slice expression.
    Pattern: array[s..e] → HARE_SLICE(array, s, e)
    Pattern: slice[s..e] → subslice with .data pointer arithmetic
    """
    target, start, end = n[1], n[2], n[3]
    start_str = g(start) if start else '0'

    # Check if target is a slice variable
    if target[0] == 'id' and target[1] in CTX.vars:
        ty = CTX.vars[target[1]]
        if ty and ty[0] == 'T:slice':
            # Slicing a slice
            end_str = g(end) if end else f'({g(target)}).len'
            inner_type = g(ty[1])
            slice_type = f'hare_slice_{inner_type.replace(" ","_").replace("*","ptr")}'
            return f'({slice_type}){{.data=({g(target)}).data+{start_str},.len={end_str}-{start_str},.cap=({g(target)}).cap-{start_str}}}'

    # Slicing an array
    end_str = g(end) if end else f'HARE_ARRAY_LEN({g(target)})'
    return f'HARE_SLICE({g(target)},{start_str},{end_str})'


def g_free(n):
    """
    Generate free expression.
    Pattern: free(slice) → hare_free(slice.data)
    Pattern: free(ptr) → hare_free(ptr)
    """
    target = n[1]
    if target[0] == 'id' and target[1] in CTX.vars:
        ty = CTX.vars[target[1]]
        if ty and ty[0] == 'T:slice':
            return f'hare_free(({g(target)}).data)'
    return f'hare_free({g(target)})'


def g_alloc(n):
    """
    Generate alloc expression.
    Pattern: alloc([0...]) → calloc-style for filled arrays
    Pattern: alloc(expr) → hare_alloc(expr)
    """
    val = n[1]
    # Array literal with fill pattern - need special handling
    if val[0] == 'arr_lit' and val[2]:  # has fill
        fill = g(val[2])
        # Generate calloc-style allocation
        return f'__hare_calloc(sizeof(intptr_t), 10)'  # simplified
    return f'hare_alloc({g(val)})'


def g_alloc_sl(n):
    """
    Generate alloc with slice.
    Pattern: alloc([arr_lit], count) → compound literal slice
    """
    val, count = n[1], n[2]
    if val[0] == 'arr_lit':
        elements = val[1]
        if elements:
            init = ', '.join(g(e) for e in elements)
            return f'((hare_slice_intptr_t){{.data = (intptr_t[]){{{init}}}, .len = {len(elements)}, .cap = {g(count)}}})'
    return f'hare_alloc_slice({g(val)},{g(count)})'


def g_call(n):
    """
    Generate function call.
    Pattern: variadic_fn(a, b, c, ...) → fn(a, (slice){...})
    Pattern: variadic_fn(a, slice...) → fn(a, slice)
    Pattern: fn_with_defaults(a) → fn(a, default1, default2)
    """
    func, args = n[1], n[2]

    # Get function name if it's a simple identifier
    fn_name = func[1] if func[0] == 'id' else None

    # Check if this is a registered function
    if fn_name:
        fn_info = CTX.get_fn_info(fn_name)
        if fn_info:
            params = fn_info['params']
            is_variadic = fn_info['variadic']

            # Handle variadic functions
            if is_variadic:
                n_fixed = len(params) - 1  # Last param is the variadic slice

                if len(args) >= n_fixed:
                    # Split into fixed and variadic args
                    fixed_args = list(args[:n_fixed])
                    var_args = list(args[n_fixed:])

                    # Fill in defaults for fixed args
                    for i in range(len(fixed_args), n_fixed):
                        pname, ptype, pdefault = params[i]
                        if pdefault:
                            fixed_args.append(pdefault)

                    fixed_str = ', '.join(g(a) for a in fixed_args)

                    # Check if we have a single spread argument
                    if len(var_args) == 1 and var_args[0][0] == 'spread':
                        slice_str = g(var_args[0][1])
                    elif var_args:
                        var_init = ', '.join(g(a) for a in var_args)
                        var_count = len(var_args)
                        slice_str = f'((hare_slice_intptr_t){{.data = (intptr_t[]){{{var_init}}}, .len = {var_count}, .cap = {var_count}}})'
                    else:
                        slice_str = '((hare_slice_intptr_t){.data = NULL, .len = 0, .cap = 0})'

                    if fixed_str:
                        return f'{g(func)}({fixed_str}, {slice_str})'
                    return f'{g(func)}({slice_str})'

            # Handle functions with default parameters
            else:
                n_params = len(params)
                n_args = len(args)

                if n_args < n_params:
                    # Fill in defaults
                    full_args = list(args)
                    for i in range(n_args, n_params):
                        pname, ptype, pdefault = params[i]
                        if pdefault:
                            full_args.append(pdefault)
                    return f'{g(func)}({", ".join(g(a) for a in full_args)})'

    # Default: regular function call
    return f'{g(func)}({", ".join(g(a) for a in args)})'


def g_arr_lit(n):
    es, fill = n[1], n[2]
    if es:
        inner = ', '.join(g(e) for e in es)
        if fill:
            return f'{{ {inner} /* fill: {g(fill)} */ }}'
        return f'{{ {inner} }}'
    if fill:
        return f'{{ {g(fill)} }}'
    return '{}'


def g_let(n):
    """
    Generate let statement.
    Pattern: let x: TaggedUnion = TypeName → x = TaggedUnion_from_TypeName()
    Pattern: let x: []T = [arr_lit] → backing array + slice struct
    """
    name, ty, init, mut = n[1], n[2], n[3], n[4]
    if ty:
        CTX.vars[name] = ty

    # Pattern: slice initialized with array literal → create backing array
    if ty and ty[0] == 'T:slice' and init and init[0] == 'arr_lit':
        elem_type = g(ty[1])
        elements = init[1]
        fill = init[2]
        count = len(elements)

        if elements:
            arr_init = ', '.join(g(e) for e in elements)
            if fill:
                arr_init += f' /* fill: {g(fill)} */'
        elif fill:
            arr_init = g(fill)
        else:
            arr_init = '0'

        const = '' if mut else 'const '
        slice_type = g(ty)
        lines = [
            f'{elem_type} __{name}_data[] = {{ {arr_init} }};',
            f'{const}{slice_type} {name} = {{.data = __{name}_data, .len = {count}, .cap = {count}}};'
        ]
        return '\n    '.join(lines)

    # Check if assigning a type name to a tagged union variable
    if init and init[0] == 'id' and ty:
        type_name = ty[1] if ty[0] == 'T:alias' else None
        init_name = init[1]
        if type_name and type_name in CTX.tagged and CTX.is_type_name(init_name):
            # This is a tagged union variant assignment
            variants = CTX.tagged[type_name]
            for v in variants:
                vname = v[1] if v[0] == 'T:alias' else (
                    v[1] if v[0] == 'T:prim' else None)
                if vname == init_name:
                    const = '' if mut else 'const '
                    # Check if it's a void-like type (includes !void)
                    if is_void_type(v):
                        return f'{const}{g(ty)} {name} = {type_name}_from_{init_name}();'
                    else:
                        # Non-void type - pass default value (0)
                        return f'{const}{g(ty)} {name} = {type_name}_from_{init_name}(0);'

    # Pattern: tagged union init with value → wrap with constructor
    if ty and ty[0] == 'T:alias' and ty[1] in CTX.tagged and init:
        type_name = ty[1]
        variants = CTX.tagged[type_name]

        # Find appropriate variant for this value
        for v in variants:
            v_tag = tag_name(v)
            if v[0] == 'T:prim':
                if v[1] in ('int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64'):
                    if init[0] == 'lit' and isinstance(init[1], int):
                        const = '' if mut else 'const '
                        return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'
                if v[1] == 'str' and init[0] == 'lit' and init[2] == 'str':
                    const = '' if mut else 'const '
                    return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'
                if v[1] == 'bool' and init[0] == 'lit' and init[2] == 'bool':
                    const = '' if mut else 'const '
                    return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'

    # Set expected type for match expressions
    old_expected = CTX.expected_type
    if ty:
        CTX.expected_type = ty

    const = '' if mut else 'const '
    decl = g_decl(ty, name) if ty else f'__auto_type {name}'
    init_str = f' = {g(init)}' if init else ''

    CTX.expected_type = old_expected
    return f'{const}{decl}{init_str};'


def g_slet(n):
    name, ty, init, mut = n[1], n[2], n[3], n[4]
    if ty:
        CTX.vars[name] = ty
    decl = g_decl(ty, name) if ty else f'__auto_type {name}'
    init_str = f' = {g(init)}' if init else ''
    return f'static {decl}{init_str};'


def g_asgn(n):
    """
    Generate assignment.
    Pattern: slice[s..e] = array_lit → element-wise assignment
    Pattern: target = value → target = value
    """
    tgt, op, val = n[1], n[2], n[3]
    if tgt[0] == 'slice' and op == '=':
        target_expr = tgt[1]
        s = g(tgt[2]) if tgt[2] else '0'

        # Determine if target is a slice variable
        is_slice = False
        if target_expr[0] == 'id' and target_expr[1] in CTX.vars:
            ty = CTX.vars[target_expr[1]]
            is_slice = ty and ty[0] == 'T:slice'

        # If val is an array literal, expand inline
        if val[0] == 'arr_lit':
            elems = val[1]
            lines = []
            for i, elem in enumerate(elems):
                if is_slice:
                    lines.append(
                        f'({g(target_expr)}).data[{s}+{i}] = {g(elem)};')
                else:
                    lines.append(f'({g(target_expr)})[{s}+{i}] = {g(elem)};')
            return ' '.join(lines)

        t = g(target_expr)
        e = g(tgt[3]) if tgt[3] else (
            f'({t}).len' if is_slice else f'HARE_ARRAY_LEN({t})')
        return f'hare_slice_assign({t},{s},{e},{g(val)});'
    return f'{g(tgt)} {op} {g(val)};'


def g_delete(n):
    t, st = n[1], n[2]
    fn = 'hare_static_delete' if st else 'hare_delete'
    if t[0] == 'idx':
        return f'{fn}(&{g(t[1])},{g(t[2])},{g(t[2])}+1)'
    if t[0] == 'slice':
        return f'{fn}(&{g(t[1])},{g(t[2]) or "0"},{g(t[3]) or f"HARE_ARRAY_LEN({g(t[1])})"})'
    return '/*delete err*/'


def g_if(n):
    cond, then, els = n[1], n[2], n[3]

    # Pattern: if with block → generate if statement
    if then[0] == 'block':
        stmts = then[1]
        if stmts:
            # Check if it's a return or assignment block
            first_kind = stmts[0][0] if stmts else None
            if first_kind in ('ret', 'asgn', 'expr', 'let'):
                # Generate if statement
                body = g(then)
                if els:
                    els_body = g(
                        els) if els[0] == 'block' else f'{{ {g(els)}; }}'
                    return f'if ({g(cond)}) {body} else {els_body}'
                return f'if ({g(cond)}) {body}'

    # Pattern: simple expression → ternary
    return f'(({g(cond)}) ? ({g(then)}) : ({g(els) or "0"}))'


def g_block(n):
    ss, r = n[1], n[2]
    body = '\n'.join(f'    {g(s)}' for s in ss)
    if r:
        body += f'\n    __r = {g(r)};'
    return '{\n' + body + '\n}'


def g_ret(n):
    """
    Pattern matching for return statements:
    - return; → return;
    - return TYPE_NAME (in tagged) → return Union_from_TYPE()
    - return void (in tagged) → return Union_from_void()
    - return EXPR (in tagged) → return Union_from_T(EXPR)
    - return match(...) → set expected_type for proper wrapping
    """
    val = n[1]
    if val is None:
        return 'return;'

    # Pattern: return void literal in tagged union → constructor
    if val[0] == 'lit' and val[2] == 'void' and CTX.is_tagged_return():
        ret_name = CTX.ret_name
        return f'return {ret_name}_from_void();'

    # Pattern: return TYPE_NAME → return Union_from_TYPE_NAME()
    # This includes error type aliases like `invalid = !void`
    if val[0] == 'id' and CTX.is_type_name(val[1]) and CTX.is_tagged_return():
        type_name = val[1]
        ret_name = CTX.ret_name
        # Check if this type is void-like (needs no argument)
        underlying = CTX.types.get(type_name)
        if underlying and is_void_type(underlying):
            return f'return {ret_name}_from_{type_name}();'
        else:
            # Non-void error type - pass a default value (0)
            # This handles cases like `return io_error;` where io_error = !int
            return f'return {ret_name}_from_{type_name}(0);'

    # Pattern: return match(...) in tagged union → set expected_type
    if val[0] == 'match' and CTX.is_tagged_return():
        old_expected = CTX.expected_type
        CTX.expected_type = CTX.ret_type
        result = f'return {g(val)};'
        CTX.expected_type = old_expected
        return result

    # Pattern: return EXPR in tagged union → wrap with constructor
    if CTX.is_tagged_return():
        ret_name = CTX.ret_name
        variants = CTX.get_variant_types(ret_name)

        # Find appropriate variant for this expression
        for v in variants:
            if v[0] == 'T:prim' and v[1] in ('int', 'i8', 'i16', 'i32', 'i64',
                                             'u8', 'u16', 'u32', 'u64', 'size', 'uint'):
                return f'return {ret_name}_from_{tag_name(v)}({g(val)});'
            if v[0] == 'T:alias':
                # Check if it's a non-void alias
                underlying = CTX.types.get(v[1])
                if underlying and not is_void_type(underlying):
                    return f'return {ret_name}_from_{tag_name(v)}({g(val)});'

        # Check for str, pointer, or other types
        for v in variants:
            if v[0] == 'T:prim' and v[1] == 'str':
                return f'return {ret_name}_from_{tag_name(v)}({g(val)});'
            if v[0] == 'T:ptr':
                return f'return {ret_name}_from_{tag_name(v)}({g(val)});'

    return f'return {g(val)};'


def g_match(n):
    val, cases = g(n[1]), n[2]

    # Pattern: nullable pointer match
    has_null = any(c[1][0] == 'T:prim' and c[1][1] == 'null' for c in cases)
    has_ptr = any(c[1][0] == 'T:ptr' for c in cases)
    if has_null and has_ptr:
        return g_nullable_match(n)

    # Determine result type - prefer expected_type over ret_type
    if CTX.expected_type:
        ret_type_str = g(CTX.expected_type)
    elif CTX.ret_type:
        ret_type_str = g(CTX.ret_type)
    else:
        ret_type_str = 'intptr_t'

    if ret_type_str == 'void':
        ret_type_str = 'int'  # Use int for void match results

    # Check if we need to wrap yields in tagged union constructors
    wrap_yields = CTX.expected_type and CTX.expected_type[
        0] == 'T:alias' and CTX.expected_type[1] in CTX.tagged
    tagged_name = CTX.expected_type[1] if wrap_yields else None

    # Pattern: tagged union match
    lines = ['__extension__ ({']
    lines.append(f'    __auto_type __m = ({val});')
    lines.append(f'    {ret_type_str} __r = {{0}};')
    lines.append('    switch (__m.tag) {')

    for i, c in enumerate(cases):
        ty, bind, body = c[1], c[2], c[3]
        tag = tag_name(ty)
        lines.append(f'    case {i}U: /* {tag} */ {{')
        if bind and not is_void_type(ty):
            # Register the binding in context for proper field access
            CTX.vars[bind] = ty
            lines.append(f'        {g(ty)} {bind} = __m.value._{tag};')
        lines.append(f'        {g_match_body(body, tagged_name)}')
        lines.append('    } break;')

    lines.append('    }')
    lines.append('    __r;')
    lines.append('})')
    return '\n'.join(lines)


def g_nullable_match(n):
    val, cases = g(n[1]), n[2]
    null_c = next(
        (c for c in cases if c[1][0] == 'T:prim' and c[1][1] == 'null'), None)
    ptr_c = next((c for c in cases if c[1][0] == 'T:ptr'), None)

    # Determine result type
    ret_type_str = g(CTX.ret_type) if CTX.ret_type else 'intptr_t'
    if ret_type_str == 'void':
        ret_type_str = 'int'

    lines = ['__extension__ ({']
    lines.append(f'    __auto_type __m = ({val});')
    lines.append(f'    {ret_type_str} __r = {{0}};')

    if null_c:
        lines.append(f'    if (__m == NULL) {{ {g_match_body(null_c[3])} }}')
    if ptr_c:
        lines.append('    else {')
        if ptr_c[2]:
            # Register the binding
            CTX.vars[ptr_c[2]] = ptr_c[1]
            lines.append(f'        {g(ptr_c[1])} {ptr_c[2]} = __m;')
        lines.append(f'        {g_match_body(ptr_c[3])}')
        lines.append('    }')

    lines.append('    __r;')
    lines.append('})')
    return '\n'.join(lines)


def g_match_body(body, tagged_name=None):
    """
    Generate match case body, handling yield specially.
    Pattern: yield expr → __r = expr (or wrapped for tagged unions)
    Pattern: return → return
    Pattern: block with stmts → just the statements
    Pattern: expr → __r = expr
    """
    if body[0] == 'yield':
        val = body[1]
        expr_code = g(val)

        # If we're yielding to a tagged union, wrap the value
        if tagged_name and tagged_name in CTX.tagged:
            variants = CTX.tagged[tagged_name]

            # Try to determine which variant this yield corresponds to
            # by checking the yielded expression type
            if val[0] == 'id' and val[1] in CTX.vars:
                val_ty = CTX.vars[val[1]]
                for v in variants:
                    v_tag = tag_name(v)
                    if val_ty == v or (val_ty and v[0] == 'T:alias' and val_ty[0] == 'T:alias' and val_ty[1] == v[1]):
                        if is_void_type(v):
                            return f'__r = {tagged_name}_from_{v_tag}();'
                        return f'__r = {tagged_name}_from_{v_tag}({expr_code});'

            # For literal values, try to match the first compatible variant
            if val[0] == 'lit':
                for v in variants:
                    v_tag = tag_name(v)
                    if v[0] == 'T:prim' and v[1] in ('int', 'i32', 'i64'):
                        return f'__r = {tagged_name}_from_{v_tag}({expr_code});'

        return f'__r = {expr_code};'

    if body[0] == 'ret':
        return g(body)
    if body[0] == 'block':
        ss, r = body[1], body[2]
        parts = [g(s) for s in ss]
        if r:
            # Apply same wrapping logic to block result
            if tagged_name:
                parts.append(g_match_body(('yield', r), tagged_name))
            else:
                parts.append(f'__r = {g(r)};')
        return ' '.join(parts)
    # Statement types - generate as-is without yield
    if body[0] in ('let', 'slet', 'asgn', 'expr', 'for', 'if'):
        return g(body)
    # Expression - assign to __r
    return f'__r = {g(body)};'


def g_switch(n):
    val, cases = g(n[1]), n[2]

    # Determine result type
    ret_type_str = g(CTX.ret_type) if CTX.ret_type else 'intptr_t'
    if ret_type_str == 'void':
        ret_type_str = 'int'

    lines = ['__extension__ ({']
    lines.append(f'    {ret_type_str} __r = {{0}};')
    lines.append(f'    switch ({val}) {{')

    for c in cases:
        if c[0] == 'default':
            lines.append('    default:')
            lines.append('    {')
            lines.append(f'        {g_match_body(c[2])}')
            lines.append('    } break;')
        else:
            for v in c[1]:
                lines.append(f'    case {g(v)}:')
            lines.append('    {')
            lines.append(f'        {g_match_body(c[2])}')
            lines.append('    } break;')

    lines.append('    }')
    lines.append('    __r;')
    lines.append('})')
    return '\n'.join(lines)


def g_fn(n):
    name, ps, ret, body, exp, va = n[1], n[2], n[3], n[4], n[5], n[6]
    attrs = n[7] if len(n) > 7 else []

    # Skip @test functions in normal compilation
    if 'test' in attrs:
        return f'#ifdef HARE_TEST\n{g_fn_impl(n)}\n#endif'

    return g_fn_impl(n)


def g_fn_impl(n):
    """Generate function implementation."""
    name, ps, ret, body, exp, va = n[1], n[2], n[3], n[4], n[5], n[6]
    attrs = n[7] if len(n) > 7 else []

    # Register function info (especially for variadic functions)
    CTX.register_fn(name, ps, va)

    # Set up context for this function
    CTX.vars.clear()
    CTX.ret_type = ret

    # Check if return type is a tagged union alias
    if ret[0] == 'T:alias' and ret[1] in CTX.tagged:
        CTX.ret_name = ret[1]
    else:
        CTX.ret_name = None

    # Register parameters
    for pn, pt, _ in ps:
        CTX.vars[pn] = pt

    static = '' if exp else 'static '
    params = ', '.join(g_decl(t, nm) for nm, t, _ in ps) or 'void'

    # Handle function attributes
    attr_str = ''
    if 'init' in attrs:
        attr_str = '__attribute__((constructor)) '
    elif 'fini' in attrs:
        attr_str = '__attribute__((destructor)) '

    defs = [(nm, g(d)) for nm, _, d in ps if d]
    comment = f'/* Defaults: {", ".join(f"{nm}={v}" for nm,v in defs)} */\n' if defs else ''
    comment += '/* variadic */\n' if va else ''
    if 'init' in attrs:
        comment += '/* @init */\n'
    if 'fini' in attrs:
        comment += '/* @fini */\n'
    if 'test' in attrs:
        comment += '/* @test */\n'

    if body[0] == 'block':
        b = g(body)
    else:
        # Simple expression body - may need return wrapping
        b = '{\n    ' + g(('ret', body)) + '\n}'

    return f'{comment}{attr_str}{static}{g(ret)} {name}({params}) {b}'


def g_typedef(n):
    name, ty, exp = n[1], n[2], n[3]

    # Register the type
    CTX.register_type(name, ty)

    if ty[0] == 'T:tagged':
        return g_tagged_typedef(name, ty)

    return f'typedef {g(ty)} {name};'


def is_void_type(t):
    """Check if type is void-like (void or error wrapping void)."""
    if t[0] == 'T:prim' and t[1] == 'void':
        return True
    if t[0] == 'T:err':
        return is_void_type(t[1])
    if t[0] == 'T:alias':
        # Look up the underlying type
        underlying = CTX.types.get(t[1])
        if underlying:
            return is_void_type(underlying)
    return False


def g_tagged_typedef(name, ty):
    """Generate tagged union typedef with constructors."""
    types, spreads = ty[1], ty[2]

    lines = ['typedef struct {', '    uint32_t tag;', '    union {']
    for i, t in enumerate(types):
        tag = tag_name(t)
        ct = g(t)
        sp = ' /* spread */' if spreads[i] else ''
        if is_void_type(t):
            lines.append(f'        char _{tag}_m; /* void */')
        else:
            lines.append(f'        {ct} _{tag};{sp}')
    lines.append('    } value;')
    lines.append(f'}} {name};')

    # Tag constants
    for i, t in enumerate(types):
        tag = tag_name(t)
        base = 'HARE_ERROR_TAG_BASE + ' if t[0] == 'T:err' else ''
        lines.append(f'#define {name}_TAG_{tag} ({base}{i}U)')

    # Constructors
    # Pattern: void types and error-wrapping-void types get void constructors
    for i, t in enumerate(types):
        tag = tag_name(t)
        ct = g(t)
        base = 'HARE_ERROR_TAG_BASE + ' if t[0] == 'T:err' else ''

        # Check if base should be added for alias to error type
        if t[0] == 'T:alias':
            underlying = CTX.types.get(t[1])
            if underlying and underlying[0] == 'T:err':
                base = 'HARE_ERROR_TAG_BASE + '

        # Only generate void constructor for void-like types
        if is_void_type(t):
            lines.append(
                f'static inline {name} {name}_from_{tag}(void) {{ {name} __r; __r.tag = {base}{i}U; return __r; }}')
        else:
            lines.append(
                f'static inline {name} {name}_from_{tag}({ct} __v) {{ {name} __r; __r.tag = {base}{i}U; __r.value._{tag} = __v; return __r; }}')

    return '\n'.join(lines)

# =============================================================================
# MAIN
# =============================================================================


def transpile(src):
    global CTX
    CTX = Ctx()  # Fresh context

    ast = p_unit(P(tokenize(src)))

    # First pass: collect type definitions and function signatures
    for d in ast:
        if d[0] == 'typedef':
            CTX.register_type(d[1], d[2])
        elif d[0] == 'fn':
            # Register function for variadic call handling
            name, ps, va = d[1], d[2], d[6]
            CTX.register_fn(name, ps, va)

    # Second pass: synthesize typedefs for inline tagged unions in function returns
    synth_types = []
    synth_counter = [0]

    def synth_tagged(ty):
        """If ty is an inline tagged, create a synthetic typedef and return its name."""
        if ty[0] == 'T:tagged':
            name = f'__hare_tagged_{synth_counter[0]}'
            synth_counter[0] += 1
            CTX.register_type(name, ty)
            synth_types.append(('typedef', name, ty, False))
            return ('T:alias', name)
        return ty

    # Transform AST to use synthetic types
    new_ast = []
    for d in ast:
        if d[0] == 'fn':
            name, ps, ret, body, exp, va = d[1], d[2], d[3], d[4], d[5], d[6]
            attrs = d[7] if len(d) > 7 else []
            new_ret = synth_tagged(ret)
            new_ast.append(('fn', name, ps, new_ret, body, exp, va, attrs))
        else:
            new_ast.append(d)

    # Third pass: generate code
    types, globs, funcs, fwd_decls = [], [], [], []

    for d in new_ast:
        if d[0] == 'fn':
            fwd = g_fn_decl(d)
            if fwd:
                fwd_decls.append(fwd)
        code = g(d)
        if d[0] == 'fn':
            funcs.append(code)
        elif d[0] in ('typedef', 'def'):
            types.append(code)
        else:
            globs.append(code)

    # Generate synthetic types AFTER user types
    for d in synth_types:
        types.append(g(d))

    # Generate needed slice-of-array typedefs
    slice_typedefs = []
    for name, (inner_ty, arr_size) in CTX.needed_slice_typedefs.items():
        inner_c = g(inner_ty)
        slice_typedefs.append(
            f'typedef struct {{ {inner_c} (*data)[{arr_size}]; size_t len; size_t cap; }} {name};')

    parts = [PRELUDE]
    if slice_typedefs:
        parts.append('\n/* Slice-of-array types */\n' +
                     '\n'.join(slice_typedefs))
    if types:
        parts.append('\n/* Types */\n' + '\n'.join(types))
    if fwd_decls:
        parts.append('\n/* Forward declarations */\n' + '\n'.join(fwd_decls))
    if globs:
        parts.append('\n/* Globals */\n' + '\n'.join(globs))
    if funcs:
        parts.append('\n/* Functions */\n' + '\n\n'.join(funcs))

    return '\n'.join(parts)


def g_fn_decl(n):
    """Generate forward declaration for a function."""
    name, ps, ret, body, exp, va = n[1], n[2], n[3], n[4], n[5], n[6]
    attrs = n[7] if len(n) > 7 else []

    # Skip test functions in forward decls (handled by ifdef in body)
    if 'test' in attrs:
        return f'#ifdef HARE_TEST\nstatic {g(ret)} {name}({", ".join(g_decl(t, nm) for nm, t, _ in ps) or "void"});\n#endif'

    static = '' if exp else 'static '
    params = ', '.join(g_decl(t, nm) for nm, t, _ in ps) or 'void'
    return f'{static}{g(ret)} {name}({params});'


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: hare2c.py <input.ha> [output.c]")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        src = f.read()
    out = transpile(src)
    if len(sys.argv) > 2:
        with open(sys.argv[2], 'w') as f:
            f.write(out)
        print(f"Transpiled {sys.argv[1]} -> {sys.argv[2]}")
    else:
        print(out)
