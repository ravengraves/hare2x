"""
Hare-to-C11 Transpiler - metacompiler-style
Pattern-matching transformations:
1. AST -> Typed AST (add type info)
2. Typed AST -> C code (using rewrite rules)
Key patterns:
- return TYPE_NAME in tagged union -> return Union_from_TYPE_NAME()
- return EXPR in tagged union -> return Union_from_type(EXPR)
- match case TYPE => body -> case TAG: { ... }
"""

import re
import sys
from collections import deque
from contextlib import contextmanager
from functools import lru_cache

# ============================================================================
# TOKENIZER - Lexical Analysis
# ============================================================================

TOKENS = [
    ('COMMENT', r'//[^\n]*'),
    ('FLOAT', r'(?:\d(?:_*\d)*\.\d(?:_*\d)*(?:[eE][+\-]?\d(?:_*\d)*)?(?:f(?:32|64))?|\d(?:_*\d)*(?:[eE][+\-]?\d(?:_*\d)*)(?:f(?:32|64))?|\d(?:_*\d)*f(?:32|64))'),
    ('INT', r'(?:0x[0-9a-fA-F](?:_*[0-9a-fA-F])*|0o[0-7](?:_*[0-7])*|0b[01](?:_*[01])*|\d(?:_*\d)*)(?:z|i(?:8|16|32|64)?|u(?:8|16|32|64)?)?'),
    ('STR', r'"(?:[^"\\]|\\.)*"'), ('RAWSTR', r'`[^`]*`'),
    ('RUNE', r"'(?:[^'\\]|\\(?:x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|.))'"),
    ('OP3', r'\&\.\.|\.\.\.|\>\>=|\<\<='),
    ('OP2', r'\.\.|=\>|==|!=|<=|>=|<<|>>|&&|\|\||\^\^|\+=|-=|\*=|/=|%=|&=|\|=|\^='),
    ('OP', r'[+\-*/%&|^~!<>=@?:;,.\[\](){}#]'),
    ('ID', r'[a-zA-Z_]\w*'), ('WS', r'\s+'),
]
KEYWORDS = {'fn', 'let', 'const', 'type', 'struct', 'union', 'enum', 'return', 'if', 'else',
            'for', 'break', 'continue', 'match', 'switch', 'case', 'yield', 'defer',
            'export', 'use', 'true', 'false', 'null', 'void', 'bool', 'str', 'rune',
            'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'int', 'uint',
            'f32', 'f64', 'size', 'uintptr', 'nullable', 'static', 'alloc', 'free',
            'append', 'insert', 'delete', 'len', 'assert', 'abort', 'as', 'is',
            'nomem', 'done', 'never', 'opaque', 'offset'}
KW_AS_IDENT = {'size'}
TOKEN_RE = re.compile(
    '|'.join(f'(?P<T{i}>{p})' for i, (_, p) in enumerate(TOKENS)))
TOKEN_NAMES = {f'T{i}': n for i, (n, _) in enumerate(TOKENS)}
ESCAPE = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', "'": "'", '"': '"',
          '0': '\0', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v'}


def process_string_escapes(s):
    def replace_escape(m):
        esc = m.group(1)
        if esc in ESCAPE:
            return ESCAPE[esc]
        if esc[0] == 'x' and len(esc) == 3:
            return chr(int(esc[1:], 16))
        if esc[0] in 'oO':
            CTX.error(f"octal escape sequences not supported: '\\{esc}'")
        if esc[0] == '0' and len(esc) > 1:
            CTX.error(f"C-style octal escape sequences not supported: '\\{esc}' (use \\x{int(esc, 8):02x} for hex)")
        if esc[0] == 'u' and len(esc) == 5:
            return chr(int(esc[1:], 16))
        if esc[0] == 'U' and len(esc) == 9:
            return chr(int(esc[1:], 16))
        return esc
    return re.sub(r'\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|U[0-9a-fA-F]{8}|0[0-7]+|.)', replace_escape, s)

C_ESCAPE = str.maketrans({'\\': '\\\\', '"': '\\"', '\t': '\\t', '\r': '\\r', '\0': '\\0', '\n': '\\n'})
escape_c_string = lambda s: s.translate(C_ESCAPE)

def tokenize(src):
    toks, ln = [], 1
    for m in TOKEN_RE.finditer(src):
        k, v = TOKEN_NAMES[m.lastgroup], m.group()
        if k == 'WS':
            ln += v.count('\n')
            continue
        if k == 'COMMENT':
            ln += 1
            continue
        if k in ('OP2', 'OP3'):
            k = v  # Use actual operator as token type
        elif k == 'ID' and v in KEYWORDS:
            k = 'KW'
        toks.append((k, v, ln))
    return toks + [('EOF', '', ln)]


# ============================================================================
# PARSER - Recursive Descent Parser
# ============================================================================

class P:
    def __init__(s, t): s.t, s.i = t, 0
    def pk(s, n=0): return s.t[min(s.i+n, len(s.t)-1)]
    def at(s, *k): t = s.pk(); return t[0] in k or t[1] in k

    def eat(s, *k): return (s.t[s.i], setattr(s,
                                              'i', s.i+1))[0] if s.at(*k) else None
    def need(s, k): t = s.eat(
        k); assert t, f"Expected {k}, got {s.pk()}"; return t
    def val(s, k): return s.need(k)[1]

PREC = {'||': 1, '^^': 2, '&&': 3, '==': 4, '!=': 4, '<': 5, '>': 5, '<=': 5, '>=': 5,
        '|': 6, '^': 7, '&': 8, '<<': 9, '>>': 9, '+': 10, '-': 10, '*': 11, '/': 11, '%': 11}
COMPOUND_OPS = {'+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '>>=', '<<='}


# --- Type Parsing ---

def p_ident(p):
    if p.at('ID'):
        return p.val('ID')
    if p.at('KW') and p.pk()[1] in KW_AS_IDENT:
        return p.eat('KW')[1]
    return p.val('ID')
def p_type(p):
    if p.eat('const'):
        return ('T:const', p_type(p))
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
        if sz[0] == 'lit':
            arr_size = sz[1]
        elif sz[0] == 'id':
            arr_size = sz[1]  # Will be resolved via CTX.defs at code gen time
        else:
            arr_size = sz  # Keep full AST for complex expressions
        return ('T:arr', p_type(p), arr_size, False)
    if p.eat('struct'):
        return p_struct_type(p)
    if p.eat('union'):
        if CTX.is_pika():
            raise SyntaxError("Pika does not allow union types; use tagged unions (T | U) with match, or use pointer casts for reinterpretation")
        return p_union_type(p)
    if p.eat('enum'):
        return p_enum_type(p)
    if p.eat('fn'):
        return p_fn_type(p)
    if p.eat('('):
        return p_tuple_or_tagged(p)
    if p.at('KW'):
        kw = p.eat('KW')[1]
        if kw == 'nomem':
            return ('T:nomem',)
        return ('T:prim', kw)
    if p.at('ID'):
        return p_type_path(p)
    raise SyntaxError(f"Expected type at {p.pk()}")
def p_struct_type(p):
    p.need('{')
    fs = []
    while not p.eat('}'):
        if p.eat('union'):
            union_ty = p_union_type(p)
            fs.append((None, union_ty))  # None name = anonymous
        else:
            # Check for reserved keyword used as field name
            if p.at('KW') and p.pk()[1] not in KW_AS_IDENT:
                raise SyntaxError(f"line {p.pk()[2]}: cannot use reserved keyword '{p.pk()[1]}' as struct field name")
            n = p.val('ID')
            p.need(':')
            fs.append((n, p_type(p)))
        if not p.eat(','):
            p.need('}')
            break
    return ('T:struct', fs)
def p_union_type(p):
    p.need('{')
    fs = []
    while not p.eat('}'):
        # Check for reserved keyword used as field name
        if p.at('KW') and p.pk()[1] not in KW_AS_IDENT:
            raise SyntaxError(f"line {p.pk()[2]}: cannot use reserved keyword '{p.pk()[1]}' as union field name")
        n = p.val('ID')
        p.need(':')
        fs.append((n, p_type(p)))
        if not p.eat(','):
            p.need('}')
            break
    return ('T:union', fs)
def p_enum_type(p):
    base = None
    if not p.at('{'):
        base = p_type(p)
    p.need('{')
    members = []
    val = 0
    while not p.eat('}'):
        name = p.val('ID')
        if p.eat('='):
            v = p_expr(p)
            if v[0] == 'lit':
                val = v[1]
        members.append((name, val))
        val += 1
        if not p.eat(','):
            p.need('}')
            break
    return ('T:enum', members, base)
def p_fn_type(p):
    p.need('(')
    ps = []
    while not p.eat(')'):
        if ps:
            p.need(',')
        # Check if this is a named parameter (name: type) or just a type
        if p.pk(1)[1] == ':':
            # Named parameter like x: int or _: int
            n = p.val('ID')
            p.need(':')
        else:
            # No name given - error in Hare (must use _: type for unnamed)
            CTX.error("function type parameters must have names (use '_' for unnamed, e.g., fn(_: int) int)")
            n = '_'
        ps.append((n, p_type(p)))
    return ('T:fn', ps, p_type(p))
def p_tuple_or_tagged(p):
    sp = bool(p.eat('...'))
    ts = [(p_type(p), sp)]
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


# --- Expression Parsing ---

def p_expr(p, mp=0):
    l = p_unary(p)
    while True:
        t = p.pk()
        pr = PREC.get(t[1] if t[0] == 'OP' else t[0], -1)
        if pr < mp:
            break
        op = p.eat(t[0], t[1])[1]
        l = ('bin', op, l, p_expr(p, pr + 1))
    op_tok = p.pk()
    if op_tok[1] in COMPOUND_OPS:
        p.eat(op_tok[0], op_tok[1])
        l = ('asgn_e', l, op_tok[1], p_expr(p))
    return l
def p_unary(p):
    if op := p.eat('-', '!', '~', '*', '&'):
        return ('un', op[1], p_unary(p))
    if p.eat('match'):
        return p_match(p)
    if p.eat('switch'):
        return p_switch(p)
    return p_postfix(p)
def p_postfix(p):
    l = p_primary(p)
    while True:
        ln = p.pk()[2]  # Capture line number for potential abort sites
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
                l = ('slice', l, None, e, ln)
            else:
                s = p_expr(p)
                if p.eat('..'):
                    e = None if p.at(']') else p_expr(p)
                    p.need(']')
                    l = ('slice', l, s, e, ln)
                else:
                    p.need(']')
                    l = ('idx', l, s, ln)
        elif p.eat('.'):
            if p.at('INT'):
                l = ('fld', l, p.val('INT'))
            elif p.at('FLOAT'):
                fv = p.val('FLOAT')
                parts = fv.split('.')
                l = ('fld', l, parts[0])
                for part in parts[1:]:
                    l = ('fld', l, part)
            else:
                l = ('fld', l, p.val('ID'))
        elif p.eat('?'):
            l = ('prop', l, ln)
        elif p.eat('!'):
            l = ('unwrap', l, ln)
        elif p.eat(':'):
            l = ('cast', l, p_type(p), ln)
        elif p.eat('as'):
            l = ('cast', l, p_type(p), ln)
        elif p.eat('is'):
            l = ('is', l, p_type(p))
        else:
            break
    return l
# Suffix lookup for fast integer parsing
_INT_SUFFIXES = {1: {'z', 'i', 'u'}, 2: {'i8', 'u8'}, 3: {'i16', 'i32', 'i64', 'u16', 'u32', 'u64'}}

def p_int(s):
    # Check for suffix by length (longest first for efficiency)
    sf = None
    for length in (3, 2, 1):
        if len(s) > length and s[-length:] in _INT_SUFFIXES[length]:
            sf = s[-length:]
            s = s[:-length]
            break

    s = s.replace('_', '')
    # Use dict dispatch for base detection
    if s.startswith('0x'):
        return int(s, 16), sf
    if s.startswith('0o'):
        return int(s, 8), sf
    if s.startswith('0b'):
        return int(s, 2), sf
    # Check for leading zero without 0o prefix
    if len(s) > 1 and s[0] == '0' and s != '0':
        if all(c in '01234567' for c in s):
            CTX.error(f"leading zeros not allowed in decimal literals: '{s}' (hint: use '0o{s[1:]}' for octal)")
        else:
            CTX.error(f"leading zeros not allowed in decimal literals: '{s}'")
        return int(s, 10), sf  # Return as decimal to avoid cascading errors
    return int(s, 10), sf
def p_primary(p):
    if t := p.eat('INT'):
        v, sf = p_int(t[1])
        return ('lit', v, sf)
    if t := p.eat('FLOAT'):
        v = t[1].replace('_', '')
        if v.endswith('f32'):
            return ('lit', float(v[:-3]), 'f32')
        if v.endswith('f64'):
            return ('lit', float(v[:-3]), 'f64')
        return ('lit', float(v), 'f64')
    if p.at('STR', 'RAWSTR'):
        parts = []
        while p.at('STR', 'RAWSTR'):
            if t := p.eat('STR'):
                parts.append(process_string_escapes(t[1][1:-1]))
            elif t := p.eat('RAWSTR'):
                parts.append(t[1][1:-1])  # Raw string: no escape processing
        return ('lit', ''.join(parts), 'str')
    if t := p.eat('RUNE'):
        inner = t[1][1:-1]
        ch = process_string_escapes(inner)[0] if inner.startswith('\\') else inner[0]
        return ('lit', ord(ch), 'rune')
    if p.eat('true'):
        return ('lit', True, 'bool')
    if p.eat('false'):
        return ('lit', False, 'bool')
    if p.eat('null'):
        return ('lit', None, 'null')
    if p.eat('void'):
        return ('lit', None, 'void')
    if p.eat('nomem'):
        return ('lit', None, 'nomem')
    if p.eat('done'):
        return ('lit', None, 'done')
    if p.eat('never'):
        return ('lit', None, 'never')
    ln = p.pk()[2]
    BUILTINS = {
        'len': lambda: (p.need('('), (r := ('len', p_expr(p))), p.need(')'))[1],
        'size': lambda: (p.need('('), (r := ('size', p_type(p))), p.need(')'))[1],
        'free': lambda: (p.need('('), (r := ('free', p_expr(p))), p.need(')'))[1],
        'alloc': lambda: (p.need('('), (e := p_expr(p)), (p.need(')'), ('alloc_cp', e, ln))[-1] if p.eat('...') else ((c := p_expr(p)), p.need(')'), ('alloc_sl', e, c, ln))[-1] if p.eat(',') else (p.need(')'), ('alloc', e, ln))[-1])[-1],
        'assert': lambda: (p.need('('), (c := p_expr(p)), (m := p_expr(p) if p.eat(',') else None), p.need(')'), ('assert_b', c, m, ln))[-1],
        'abort': lambda: (p.need('('), (r := ('abort', p_expr(p) if not p.at(')') else None, ln)), p.need(')'))[1],
        'append': lambda: p_append_or_insert(p, False, 'append'),
        'insert': lambda: p_append_or_insert(p, False, 'insert'),
        'delete': lambda: p_delete(p, False),
    }
    for kw, fn in BUILTINS.items():
        if p.at(kw) and p.pk(1)[1] == '(':
            p.eat(kw)
            return fn()
    if p.eat('static'):
        if p.eat('append'):
            return p_append_or_insert(p, True, 'append')
        if p.eat('insert'):
            return p_append_or_insert(p, True, 'insert')
        if p.eat('delete'):
            return p_delete(p, True)
    if p.at('KW') and p.pk()[1] == 'offset' and p.pk(1)[1] == '(':
        p.eat('KW')  # consume 'offset'
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
        if p.eat(','):
            es = [e]
            while True:
                if p.at(')'):
                    break  # Allow trailing comma
                es.append(p_expr(p))
                if not p.eat(','):
                    break
            p.need(')')
            return ('tuple_lit', es)
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
    if p.at('KW') and p.pk()[1] in KW_AS_IDENT:
        return ('id', p.eat('KW')[1])
    raise SyntaxError(f"Unexpected {p.pk()}")
def p_append_or_insert(p, st, op):
    p.need('(')
    t = p_expr(p)
    p.need(',')
    v = p_expr(p)
    va = bool(p.eat('...'))
    p.need(')')
    return (op, t, v, va, st)
def p_delete(p, st):
    p.need('(')
    t = p_expr(p)
    p.need(')')
    return ('delete', t, st)
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
        if p.eat(']'):  # Handle trailing comma - consume ']' and exit
            break
        e = p_expr(p)
        if p.eat('...'):
            p.need(']')  # Must consume closing bracket after fill
            return ('arr_lit', es, e)
        es.append(e)
    return ('arr_lit', es, fill)
def p_struct_lit(p, name):
    p.need('{')
    fs = []
    while not p.eat('}'):
        fn = p.val('ID')
        ty = p_type(p) if p.eat(':') else None
        p.need('=')
        fs.append((fn, p_expr(p), ty))
        if not p.eat(','):
            p.need('}')
            break
    return ('struct_lit', name, fs)
def p_if(p):
    p.need('(')
    c = p_expr(p)
    p.need(')')
    if p.at('return', 'yield', 'break', 'continue'):
        t = p_stmt(p)
    else:
        t = p_expr(p)
    e = None
    if p.eat('else'):
        if p.at('return', 'yield', 'break', 'continue'):
            e = p_stmt(p)
        else:
            e = p_expr(p)
    return ('if', c, t, e)
def p_for(p):
    p.need('(')

    # Check for empty initializer (for (; ...))
    if p.at(';'):
        CTX.error("empty for loop initializer not allowed (hint: use 'for (condition) { body; increment; }' instead of 'for (; condition; increment)')")

    init = None
    if not p.at(';', ')'):
        if p.eat('let'):
            name = p.val('ID')
            if p.eat('&..'):
                arr = p_expr(p)
                p.need(')')
                return ('foreach_ref', name, arr, p_expr(p))
            if p.eat('..'):
                arr = p_expr(p)
                p.need(')')
                return ('foreach', name, arr, p_expr(p))
            if p.eat('=>'):
                iter_expr = p_expr(p)
                p.need(')')
                return ('foreach_iter', name, iter_expr, p_expr(p))
            ty = p_type(p) if p.eat(':') else None
            init_val = p_expr(p) if p.eat('=') else None
            init = ('let', name, ty, init_val, True)
        else:
            init = p_expr(p)
    if p.at(')'):
        p.need(')')
        return ('for', None, init, None, p_expr(p))
    p.need(';')
    cond = p_expr(p) if not p.at(';') else None
    p.need(';')
    after = p_expr(p) if not p.at(')') else None
    p.need(')')
    return ('for', init, cond, after, p_expr(p))


def _parse_hash_annotation(p):
    line = p.pk()[2]
    p.need('#')
    p.need('[')
    annot = p.val('ID') if p.at('ID') else None
    simple = p.at(']')
    depth = 0
    while True:
        if p.at('EOF'):
            raise SyntaxError(f"line {line}: unterminated annotation")
        tok = p.pk()
        if tok[1] == '[':
            depth += 1
            p.i += 1
            continue
        if tok[1] == ']':
            if depth == 0:
                p.i += 1
                break
            depth -= 1
            p.i += 1
            continue
        p.i += 1
    return annot, simple, line


def _skip_hash_annotations(p):
    while p.at('#'):
        _parse_hash_annotation(p)


def _parse_stmt_annotations(p):
    attrs = []
    while p.at('#'):
        annot, simple, line = _parse_hash_annotation(p)
        if simple and annot == 'ivdep':
            if annot in attrs:
                raise SyntaxError(f"line {line}: duplicate #[ivdep] annotation")
            attrs.append(annot)
    return attrs


def _parse_param_annotations(p):
    attrs = []
    while p.at('#') or p.at('@'):
        if p.eat('#'):
            p.i -= 1
            annot, simple, line = _parse_hash_annotation(p)
            if simple and annot == 'restrict':
                if annot in attrs:
                    raise SyntaxError(f"line {line}: duplicate #[restrict] annotation")
                attrs.append(annot)
            continue
        p.need('@')
        attr = p.val('ID')
        if attr == 'restrict':
            raise SyntaxError(f"line {p.pk()[2]}: parameter annotations use #[name], not @name")
        raise SyntaxError(f"line {p.pk()[2]}: unknown parameter attribute")

    return attrs

def _p_case_body(p):
    if p.at('{'):
        body = p_expr(p)
        p.need(';')
        return body
    ss = []
    while not p.at('case', '}'):
        ss.append(p_stmt(p))
    return ('block', ss, None) if len(ss) > 1 else ss[0] if ss else ('lit', None, 'void')
def p_match(p):
    p.need('(')
    v = p_expr(p)
    p.need(')')
    p.need('{')
    cs = []
    while not p.eat('}'):
        if p.eat('case'):
            if p.at('=>'):  # Catch-all case
                p.need('=>')
                cs.append(('case', None, None, _p_case_body(p)))
            else:
                bind = (p.val('ID'), p.need(':'))[0] if p.eat('let') else None
                ty = p_type(p)
                p.need('=>')
                cs.append(('case', ty, bind, _p_case_body(p)))
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
                body = p_stmt(p)
                cs.append(('default', [], body))
            else:
                vs = [p_expr(p)]
                while p.eat(','):
                    vs.append(p_expr(p))
                p.need('=>')
                body = p_stmt(p)
                cs.append(('case', vs, body))
    return ('switch', v, cs)
def p_let(p, mut, need_semi=True):
    ln = p.pk()[2]  # Capture line number
    bs = []
    while True:
        n = p_ident(p)
        ty = p_type(p) if p.eat(':') else None
        init = p_expr(p) if p.eat('=') else None
        bs.append((n, ty, init))
        if not need_semi or not p.eat(','):
            break
    if need_semi:
        p.need(';')
    return ('let', bs[0][0], bs[0][1], bs[0][2], mut, ln) if len(bs) == 1 else ('mlet', bs, mut, ln)


# --- Statement Parsing ---

def p_stmt(p):
    if p.eat('let'):
        return p_let(p, True)
    if p.eat('const'):
        return p_let(p, False)
    if p.eat('static'):
        kw = p.eat('let', 'const')
        if kw:
            ln = p.pk()[2]
            n = p.val('ID')
            ty = p_type(p) if p.eat(':') else None
            init = p_expr(p) if p.eat('=') else None
            p.need(';')
            return ('slet', n, ty, init, kw[1] == 'let', ln)
        for op in ['append', 'insert', 'delete']:
            if p.eat(op):
                e = p_append_or_insert(p, True, op) if op in ('append', 'insert') else p_delete(p, True)
                # Handle optional ! for error unwrapping (e.g., static append(items, 1)!;)
                if p.eat('!'):
                    e = ('unwrap', e, p.pk()[2])
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
    if p.at('#'):
        attrs = _parse_stmt_annotations(p)
        if attrs:
            if not p.eat('for'):
                raise SyntaxError(f"line {p.pk()[2]}: #[ivdep] must be used with a for loop")
            r = p_for(p)
            p.eat(';')
            return ('for', r[1], r[2], r[3], r[4], attrs)
        return p_stmt(p)
    if p.eat('if'):
        r = p_if(p)
        p.eat(';')
        return r
    if p.eat('for'):
        r = p_for(p)
        p.eat(';')
        return r
    ln = p.pk()[2]  # Capture line number before parsing expression
    e = p_expr(p)
    if op := p.eat('=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '>>=', '<<='):
        v = p_expr(p)
        p.need(';')
        return ('asgn', e, op[1], v, ln)
    p.need(';')
    return ('expr', e)


# --- Declaration Parsing ---

def p_fn(p, exp):
    attrs = []
    _skip_hash_annotations(p)
    while p.eat('@'):
        attr_name = p.val('ID')
        if attr_name == 'symbol' and p.eat('('):
            sym = p.val('STR')[1:-1]  # Strip quotes
            p.need(')')
            attrs.append(('symbol', sym))
        else:
            attrs.append(attr_name)
    _skip_hash_annotations(p)
    if p.eat('export'):
        exp = True
    _skip_hash_annotations(p)
    p.need('fn')
    name = p.val('ID')
    p.need('(')
    ps, va = [], False
    while not p.eat(')'):
        if ps:
            p.need(',')
        pattrs = _parse_param_annotations(p)
        pn = p_ident(p)
        p.need(':')
        pt = p_type(p)
        if p.eat('...'):
            va = True
            pt = ('T:slice', pt)
        df = p_expr(p) if p.eat('=') else None
        ps.append((pn, pt, df, pattrs))
    ret = p_type(p)
    p.need('=')
    body = p_expr(p)
    p.need(';')
    return ('fn', name, ps, ret, body, exp, va, attrs)
def p_decl(p):
    _skip_hash_annotations(p)
    exp = bool(p.eat('export'))
    _skip_hash_annotations(p)
    if p.at('@'):
        # Handle @packed type declarations (Pika)
        if p.pk(1)[0] == 'ID' and p.pk(1)[1] == 'packed':
            packed = False
            while p.at('@') and p.pk(1)[0] == 'ID' and p.pk(1)[1] == 'packed':
                p.need('@')
                p.val('ID')
                packed = True
            _skip_hash_annotations(p)
            if p.eat('export'):
                exp = True
            _skip_hash_annotations(p)
            if p.at('@'):
                raise SyntaxError(f"line {p.pk()[2]}: unknown attribute")
            if not p.eat('type'):
                raise SyntaxError(f"line {p.pk()[2]}: @packed is only valid on type declarations")
            name = p_ident(p)
            p.need('=')
            ty = p_type(p)
            if ty[0] != 'T:struct':
                raise SyntaxError(f"line {p.pk()[2]}: @packed is only valid on struct types")
            ty = ('T:struct', ty[1], True)
            p.need(';')
            return ('typedef', name, ty, exp)
        return p_fn(p, exp)
    if p.at('fn'):
        return p_fn(p, exp)
    if p.eat('type'):
        name = p_ident(p)
        p.need('=')
        ty = p_type(p)
        if ty[0] == 'T:struct' and len(ty) > 2 and ty[2]:
            # Struct is already marked packed by @packed handler
            pass
        p.need(';')
        return ('typedef', name, ty, exp)
    if p.eat('let') or p.eat('const'):
        mut = p.t[p.i-1][1] == 'let'
        name = p_ident(p)
        ty = p_type(p) if p.eat(':') else None
        init = p_expr(p) if p.eat('=') else None
        p.need(';')
        return ('global', name, ty, init, exp, mut)
    if p.eat('def'):
        name = p_ident(p)
        ty = p_type(p) if p.eat(':') else None
        p.need('=')
        v = p_expr(p)
        p.need(';')
        return ('def', name, ty, v)
    if p.eat('use'):
        first_id = p.val('ID')
        if p.at('='):  # explicit alias: use t = path;
            p.eat('=')
            path = [p.val('ID')]
            while p.at(':') and p.pk(1)[1] == ':':
                p.eat(':')
                p.eat(':')
                path.append(p.val('ID'))
            p.need(';')
            return ('use', '::'.join(path), first_id)
        else:  # regular: use path; (implicit alias = last component)
            path = [first_id]
            while p.at(':') and p.pk(1)[1] == ':':
                p.eat(':')
                p.eat(':')
                if p.at('{'):
                    break
                path.append(p.val('ID'))
            if p.eat('{'):
                while not p.eat('}'):
                    p.eat('ID')
                    p.eat(',')
            p.need(';')
            return ('use', '::'.join(path), path[-1])  # implicit alias = last component
    raise SyntaxError(f"Expected decl at {p.pk()}")
def p_unit(p):
    ds = []
    while not p.at('EOF'):
        ds.append(p_decl(p))
    return ds


# ============================================================================
# CONTEXT - Global State and Type Registry
# ============================================================================

class Ctx:
    def __init__(self):
        self.types, self.tagged, self.enums, self.vars, self.funcs = {}, {}, {}, {}, {}
        self.global_types = {}  # global var name -> type
        self.defs = {}  # def name -> value (for array size resolution)
        self.imports, self.slice_typedefs, self.needed_slice_types = set(), {}, set()
        self.import_aliases = {}  # alias -> full_module_path (for namespace aliasing)
        self.needed_tuple_types = {}  # tuple_key -> typedef_name
        self.ret_type, self.ret_name, self.expected_type, self.package = None, None, None, None
        self.warnings, self.errors = [], []
        self.current_file, self.current_func = None, None
        self.defer_stack = []  # Stack of defer expression lists, one per scope
        self.loop_defer_depth = []  # Stack of defer stack depths at loop entry
        self.in_static_init = False  # True when generating static/global initializers
        self.source_file = "<stdin>"  # Source filename for error reporting
        self.func_files = {}  # function name -> source file (for multi-file transpilation)
        self.current_line = 0  # Current line number for error reporting
        self.result_used = True  # Whether expression result is used (for match/switch)
        self.global_vars = set()  # Track global variable names for Pika shadowing check
    def push_defer_scope(self):
        self.defer_stack.append([])
    def pop_defer_scope(self):
        return self.defer_stack.pop() if self.defer_stack else []
    def add_defer(self, expr):
        if self.defer_stack:
            self.defer_stack[-1].append(expr)
    def push_loop(self):
        self.loop_defer_depth.append(len(self.defer_stack))
    def pop_loop(self):
        if self.loop_defer_depth:
            self.loop_defer_depth.pop()
    def get_current_defers(self):
        return list(reversed(self.defer_stack[-1])) if self.defer_stack else []
    def get_defers_for_break(self):
        if not self.loop_defer_depth:
            return self.get_current_defers()
        loop_depth = self.loop_defer_depth[-1]
        result = []
        for scope in reversed(self.defer_stack[loop_depth:]):
            result.extend(reversed(scope))
        return result
    def get_all_defers(self):
        result = []
        for scope in reversed(self.defer_stack):
            result.extend(reversed(scope))
        return result
    def warn(self, msg):
        line_part = f":{self.current_line}" if self.current_line else ""
        loc = f"{self.current_file or self.source_file}{line_part}:{self.current_func or '<global>'}"
        self.warnings.append(f"warning: {loc}: {msg}")
    def error(self, msg):
        line_part = f":{self.current_line}" if self.current_line else ""
        loc = f"{self.current_file or self.source_file}{line_part}:{self.current_func or '<global>'}"
        self.errors.append(f"error: {loc}: {msg}")
    def is_pika(self):
        return self.source_file.endswith('.pka')
    def mangle(
        self, name, exp): return name if exp or not self.package else f'{self.package}_{name}'
    def register_type(self, name, ty):
        self.types[name] = ty
        if ty[0] == 'T:tagged':
            self.tagged[name] = ty[1]
        if ty[0] == 'T:enum':
            self.enums[name] = {m: v for m, v in ty[1]}
    def is_tagged_return(self): return self.ret_name in self.tagged

    def find_variant(self, type_name):
        if self.ret_name not in self.tagged:
            return -1
        for i, v in enumerate(self.tagged[self.ret_name]):
            vn = v[1] if v[0] in ('T:alias', 'T:prim') else None
            if vn == type_name:
                return i
        return -1
CTX = Ctx()


# ============================================================================
# TYPE SYSTEM - Type Resolution and Checking
# ============================================================================

def bind_var(name, ty):
    old = CTX.vars.get(name)
    CTX.vars[name] = ty
    return old
def restore_var(name, old):
    if old is not None:
        CTX.vars[name] = old
    elif name in CTX.vars:
        del CTX.vars[name]

@contextmanager
def temp_var(name, ty):
    """Context manager for temporarily binding a variable."""
    old = CTX.vars.get(name)
    CTX.vars[name] = ty
    try:
        yield
    finally:
        restore_var(name, old)

@contextmanager
def temp_ctx_attr(attr_name, value):
    """Context manager for temporarily overriding a CTX attribute."""
    old = getattr(CTX, attr_name, None)
    setattr(CTX, attr_name, value)
    try:
        yield
    finally:
        setattr(CTX, attr_name, old)

def expand_module_alias(name):
    """Expand a qualified name if the first component is a module alias."""
    if '::' in name:
        parts = name.split('::')
        if parts[0] in CTX.import_aliases:
            full_path = CTX.import_aliases[parts[0]]
            return full_path + '::' + '::'.join(parts[1:])
    return name

def is_module_fn(name, module, member):
    if not name:
        return False
    expanded = expand_module_alias(name)
    return expanded == f"{module}::{member}" or expanded == f"{module}_{member}"

def mangle_name(name):
    """Convert Hare module path to C identifier, expanding aliases."""
    return expand_module_alias(name).replace('::', '_')

def get_symbol_attr(attrs):
    """Extract @symbol attribute value from attrs list."""
    for a in attrs:
        if isinstance(a, tuple) and a[0] == 'symbol':
            return a[1]
    return None

def get_fn_c_name(name, exp, attrs, ps, ret):
    """Compute C function name from Hare function metadata."""
    if sym := get_symbol_attr(attrs):
        return sym
    if name == 'main' and exp and not ps and ret == ('T:prim', 'void'):
        return '_main'
    return CTX.mangle(name, exp)

def is_untyped_float_lit(n):
    """Check if node is an untyped float literal (defaults to f64)."""
    return n and n[0] == 'lit' and isinstance(n[1], float) and n[2] in (None, 'f64')

def strip_const(t):
    return t[1] if t and t[0] == 'T:const' else t


def param_name(param):
    return param[0]


def param_type(param):
    return param[1]


def param_default(param):
    return param[2]


def param_attrs(param):
    return param[3] if len(param) > 3 else []


def param_has_attr(param, attr):
    return attr in param_attrs(param)


def param_supports_restrict(ty):
    resolved = resolve_aliases(strip_const(ty)) or strip_const(ty)
    if not resolved:
        return False
    if resolved[0] == 'T:uarr':
        return True
    if resolved[0] != 'T:ptr':
        return False
    inner = resolve_aliases(strip_const(resolved[1])) or strip_const(resolved[1])
    return inner[0] != 'T:fn'

# Memoized cache for common type resolution (no cycles)
_alias_cache = {}

def resolve_aliases(t, seen=None):
    t = strip_const(t)

    # Fast path: use cache when no seen set (common case)
    if seen is None and t and t[0] == 'T:alias':
        cache_key = (id(CTX.types), t[1]) if t else None
        if cache_key and cache_key in _alias_cache:
            return _alias_cache[cache_key]
        result = _resolve_aliases_impl(t, set())
        if cache_key and len(_alias_cache) < 1000:  # Limit cache size
            _alias_cache[cache_key] = result
        return result

    return _resolve_aliases_impl(t, seen or set())

def _resolve_aliases_impl(t, seen):
    while t and t[0] == 'T:alias':
        alias_name = t[1]
        if alias_name not in CTX.types or alias_name in seen:
            break
        seen.add(alias_name)
        t = strip_const(CTX.types[alias_name])
    return t
def resolve_ptr_type(t):
    t = resolve_aliases(t)
    return t if t and t[0] == 'T:ptr' else None
def ptr_chain_has_nullable(t):
    seen = set()
    while True:
        t = resolve_aliases(t, seen)
        if not t or t[0] != 'T:ptr':
            return False
        if len(t) > 2 and t[2]:
            return True
        t = t[1]
def is_nullable_ptr_type(t):
    pt = resolve_ptr_type(t)
    return bool(pt and len(pt) > 2 and pt[2])

is_nonnull_ptr_type = lambda t: bool((pt := resolve_ptr_type(t)) and not (len(pt) > 2 and pt[2]))

def check_nonnull_assignment(target_desc, target_ty, val_node):
    if not is_nonnull_ptr_type(target_ty) or val_node is None:
        return
    if val_node[0] == 'lit' and val_node[2] == 'null':
        CTX.error(f"cannot assign null to non-nullable pointer{target_desc}")
        return
    if is_nullable_ptr_type(infer_expr_type(val_node)):
        CTX.error(f"cannot assign nullable pointer to non-nullable{target_desc}")
def reject_nullable_chain(ty, msg):
    if ptr_chain_has_nullable(ty):
        CTX.error(msg)
def get_type_deps(ty):
    deps = set()
    def collect(t, val_only=False):
        if not t:
            return
        kind = t[0]
        if kind == 'T:alias':
            deps.add(t[1])
        elif val_only and kind in ('T:ptr', 'T:slice'):
            return  # Pointers/slices don't create value dependencies
        elif kind in ('T:struct', 'T:union'):
            for _, field_ty in t[1]:
                collect(field_ty, True)
        elif kind == 'T:tagged':
            for variant_ty in t[1]:
                collect(variant_ty, True)
        elif kind in ('T:arr', 'T:err'):
            collect(t[1], True)
    collect(ty)
    return deps
def topo_sort_typedefs(typedefs):
    name_to_typedef = {td[1]: td for td in typedefs}
    type_names = set(name_to_typedef.keys())
    deps = {}
    for td in typedefs:
        name = td[1]
        ty = td[2]
        type_deps = get_type_deps(ty)
        deps[name] = type_deps & type_names
    # Build in_degree and reverse_deps in single pass
    in_degree = {name: 0 for name in type_names}
    reverse_deps = {name: [] for name in type_names}
    for name, dep_set in deps.items():
        filtered_deps = dep_set & type_names
        in_degree[name] = len(filtered_deps)
        for dep in filtered_deps:
            reverse_deps[dep].append(name)
    # Use deque for O(1) popleft, sort once for determinism
    queue = deque(sorted(name for name in type_names if in_degree[name] == 0))
    result = []
    while queue:
        name = queue.popleft()  # O(1) instead of O(n)
        result.append(name_to_typedef[name])
        # Collect newly freed nodes and add them sorted for determinism
        newly_freed = []
        for dependent in reverse_deps[name]:
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                newly_freed.append(dependent)
        # Add in sorted order to maintain determinism
        queue.extend(sorted(newly_freed))
    remaining = [td for td in typedefs if td[1] not in {r[1] for r in result}]
    result.extend(remaining)
    return result
def infer_expr_type(node):
    if node is None:
        return None
    inferrer = EXPR_TYPE_INFERRERS.get(node[0])
    return inferrer(node) if inferrer else None

def _infer_id(n):
    return CTX.vars.get(n[1]) or CTX.global_types.get(n[1])
def _infer_lit(n):
    hint = n[2]
    if hint in ('i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'str', 'bool', 'f32', 'f64', 'rune'):
        return ('T:prim', hint)
    if hint == 'i':
        return ('T:prim', 'int')
    if hint == 'u':
        return ('T:prim', 'uint')
    if hint == 'null':
        return ('T:prim', 'null')
    if hint == 'z':
        return ('T:prim', 'size')
    if isinstance(n[1], int):
        return ('T:prim', 'int')
    if isinstance(n[1], float):
        return ('T:prim', 'f64')
    return None
def _infer_slice(n):
    base_ty = infer_expr_type(n[1])
    if base_ty and base_ty[0] == 'T:arr':
        return ('T:slice', base_ty[1])
    if base_ty and base_ty[0] == 'T:slice':
        return base_ty
    if base_ty and base_ty[0] == 'T:ptr' and base_ty[1] and base_ty[1][0] == 'T:uarr':
        return ('T:slice', base_ty[1][1])
    return None
def _infer_un(n):
    op, inner = n[1], infer_expr_type(n[2])
    if op == '&' and inner:
        return ('T:ptr', inner, False)
    if op == '*' and inner and inner[0] == 'T:ptr':
        return inner[1]
    return None
def _infer_idx(n):
    base_ty = infer_expr_type(n[1])
    if not base_ty:
        return None

    # Note: Array pointer indexing check disabled due to type inference issues with casts
    # TODO: Fix type inference for cast expressions in variable bindings

    if base_ty[0] == 'T:uarr':
        return base_ty[1]
    if base_ty[0] == 'T:ptr' and base_ty[1] and base_ty[1][0] == 'T:uarr':
        return base_ty[1][1]
    if base_ty[0] in ('T:arr', 'T:slice'):
        return base_ty[1]
    # Allow pointer indexing (C-style pointer arithmetic)
    if base_ty[0] == 'T:ptr':
        return base_ty[1]
    return None
def _infer_fld(n):
    base_ty = infer_expr_type(n[1])
    if not base_ty:
        return None
    base_ty = resolve_aliases(strip_const(base_ty))
    while base_ty and base_ty[0] == 'T:ptr':
        base_ty = resolve_aliases(strip_const(base_ty[1]))
    if base_ty and base_ty[0] in ('T:struct', 'T:union'):
        for fname, ftype in base_ty[1]:
            if fname == n[2]:
                return ftype
    return None
def _infer_case_body(body, case_ty=None, bind=None):
    """Extract type from yield or block yield."""
    if body[0] == 'yield':
        # Match with bound variable
        if bind and body[1][0] == 'id' and body[1][1] == bind and case_ty:
            return case_ty
        return infer_expr_type(body[1])
    if body[0] == 'block' and body[2] is not None:
        return infer_expr_type(body[2])
    return None

def _infer_match(n):
    inferred = None
    for _, case_ty, bind, body in n[2]:
        ty = _infer_case_body(body, case_ty, bind)
        if ty is None or (inferred and not types_match(inferred, ty, resolve_aliases=True)):
            return None
        inferred = inferred or ty
    return inferred

def _infer_switch(n):
    inferred = None
    for _, _, body in n[2]:
        ty = _infer_case_body(body)
        if ty is None or (inferred and not types_match(inferred, ty, resolve_aliases=True)):
            return None
        inferred = inferred or ty
    return inferred
def _infer_bin(n):
    op, l, r = n[1], n[2], n[3]
    if op in ('==', '!=', '<', '<=', '>', '>=', '&&', '||', '^^'):
        return ('T:prim', 'bool')
    lt = infer_expr_type(l)
    rt = infer_expr_type(r)
    if lt and rt and types_match(lt, rt, resolve_aliases=True):
        return lt
    for t in (lt, rt):
        if t and t[0] == 'T:prim' and t[1] in ('f32', 'f64'):
            return t
    return lt or rt
def _infer_call(n):
    if n[1][0] == 'id':
        fn_name = n[1][1]
        if fn_name in CTX.funcs:
            return CTX.funcs[fn_name].get('ret_type')
        if is_module_fn(fn_name, 'strings', 'toutf8'):
            return ('T:slice', ('T:prim', 'u8'))
        if is_module_fn(fn_name, 'strings', 'fromutf8_unsafe'):
            return ('T:prim', 'str')
        if is_module_fn(fn_name, 'strings', 'dup'):
            return ('T:alias', get_strings_dup_result_type_name())
    return None

def _infer_arr_lit(n):
    if not n[1]:
        return None
    elem_ty = infer_expr_type(n[1][0])
    if not elem_ty:
        return None
    return ('T:arr', elem_ty, len(n[1]), True)
EXPR_TYPE_INFERRERS = {
    'lit': _infer_lit,
    'id': _infer_id,
    'arr_lit': _infer_arr_lit,
    'struct_lit': lambda n: ('T:alias', n[1]) if n[1] else None,
    'tuple_lit': lambda n: ('T:tuple', [infer_expr_type(e) or ('T:prim', 'int') for e in n[1]]),
    'slice': _infer_slice,
    'call': _infer_call,
    'un': _infer_un,
    'idx': _infer_idx,
    'fld': _infer_fld,
    'cast': lambda n: n[2],
    'match': _infer_match,
    'switch': _infer_switch,
    'bin': _infer_bin,
}
# prop and unwrap have identical type inference
EXPR_TYPE_INFERRERS['prop'] = EXPR_TYPE_INFERRERS['unwrap'] = lambda n: get_error_result_type(infer_expr_type(n[1])) or infer_expr_type(n[1])
def resolve_type_alias(t):
    if t is None:
        return None
    if t[0] == 'T:const':
        inner = resolve_type_alias(t[1])
        return ('T:const', inner) if inner else t
    if t[0] == 'T:alias' and t[1] in CTX.types:
        return CTX.types[t[1]]
    return t
def is_tagged_union_type(t):
    resolved = resolve_type_alias(t)
    return bool(resolved and resolved[0] == 'T:tagged')
def is_strings_dup_call(n):
    return bool(n and n[0] == 'call' and n[1][0] == 'id' and is_module_fn(n[1][1], 'strings', 'dup'))
def _match_enum(t1, t2, ra):
    if len(t1[1]) != len(t2[1]):
        return False
    if not all(n1 == n2 and v1 == v2 for (n1, v1), (n2, v2) in zip(t1[1], t2[1])):
        return False
    base1, base2 = (t1[2] if len(t1) > 2 else None), (t2[2] if len(t2) > 2 else None)
    return base1 is None and base2 is None or types_match(base1, base2, ra)
def _match_fn(t1, t2, ra):
    if len(t1[1]) != len(t2[1]):
        return False
    if not all(types_match(ty1, ty2, ra) for (_, ty1), (_, ty2) in zip(t1[1], t2[1])):
        return False
    return types_match(t1[2], t2[2], ra)
# Helpers for TYPE_MATCHERS - avoid lambda repetition
_match_inner = lambda t1, t2, ra: types_match(t1[1], t2[1], ra)
_match_seq = lambda t1, t2, ra: len(t1[1]) == len(t2[1]) and all(types_match(e1, e2, ra) for e1, e2 in zip(t1[1], t2[1]))
def _match_struct(t1, t2, ra):
    if (len(t1) > 2) != (len(t2) > 2):
        return False
    return len(t1[1]) == len(t2[1]) and all(n1 == n2 and types_match(ty1, ty2, ra) for (n1, ty1), (n2, ty2) in zip(t1[1], t2[1]))
TYPE_MATCHERS = {
    'T:prim': lambda t1, t2, ra: t1[1] == t2[1],
    'T:alias': lambda t1, t2, ra: t1[1] == t2[1],
    'T:ptr': _match_inner, 'T:slice': _match_inner, 'T:uarr': _match_inner, 'T:const': _match_inner,
    'T:arr': lambda t1, t2, ra: t1[2] == t2[2] and types_match(t1[1], t2[1], ra),
    'T:err': lambda t1, t2, ra: (types_match(t1[1], t2[1], ra) if len(t1) > 1 and len(t2) > 1 else len(t1) == len(t2)),
    'T:nomem': lambda t1, t2, ra: True,
    'T:struct': _match_struct,
    'T:enum': _match_enum,
    'T:tuple': _match_seq, 'T:tagged': _match_seq,
    'T:fn': _match_fn,
}
def types_match(t1, t2, resolve_aliases=True):
    if t1 == t2:
        return True
    if t1 is None or t2 is None:
        return False
    t1, t2 = strip_const(t1), strip_const(t2)
    if resolve_aliases:
        t1_r, t2_r = resolve_type_alias(t1), resolve_type_alias(t2)
        if t1_r != t1 or t2_r != t2:
            return types_match(t1_r, t2_r, resolve_aliases=False)
    if t1[0] != t2[0]:
        return False
    matcher = TYPE_MATCHERS.get(t1[0])
    return matcher(t1, t2, resolve_aliases) if matcher else t1 == t2
def is_void_error_type(t):
    t_res = resolve_aliases(t)
    if not t_res or t_res[0] != 'T:err':
        return False
    inner = resolve_aliases(t_res[1])
    return bool(inner and inner[0] == 'T:prim' and inner[1] == 'void')
def tagged_case_matches(variant, case_type):
    if is_void_error_type(variant) and is_void_error_type(case_type):
        # Only widen matching when one side is direct !void
        if variant[0] == 'T:err' or case_type[0] == 'T:err':
            return True
    return types_match(variant, case_type, resolve_aliases=False)
def find_tag_index(tagged_name, case_type):
    if tagged_name not in CTX.tagged:
        return -1
    variants = CTX.tagged[tagged_name]
    for idx, v in enumerate(variants):
        if tagged_case_matches(v, case_type):
            return idx
    return -1
def find_tagged_variant(tagged_name, case_type):
    if tagged_name not in CTX.tagged:
        return -1, None
    variants = CTX.tagged[tagged_name]
    for idx, v in enumerate(variants):
        if tagged_case_matches(v, case_type):
            return idx, v
    return -1, None
def get_alloc_result_type_name(inner_type):
    if not hasattr(CTX, 'alloc_result_types'):
        CTX.alloc_result_types = {}
    key = str(inner_type)
    if key not in CTX.alloc_result_types:
        name = f'__hare_alloc_{len(CTX.alloc_result_types)}'
        ty = ('T:tagged', [inner_type, ('T:nomem',)], [False, False])
        CTX.register_type(name, ty)
        CTX.alloc_result_types[key] = name
    return CTX.alloc_result_types[key]
def get_strings_dup_result_type_name():
    if not hasattr(CTX, 'strings_dup_result_type'):
        name = STRINGS_DUP_RESULT_NAME
        ty = ('T:tagged', [('T:prim', 'str'), ('T:err', ('T:prim', 'void'))], [False, False])
        CTX.register_type(name, ty)
        CTX.strings_dup_result_type = name
    return CTX.strings_dup_result_type


# ============================================================================
# CODE GENERATION - C11 Code Emission
# ============================================================================

TYPE_MAP = {
    'int': 'intptr_t', 'uint': 'uintptr_t', 'i8': 'int8_t', 'i16': 'int16_t',
    'i32': 'int32_t', 'i64': 'int64_t', 'u8': 'uint8_t', 'u16': 'uint16_t',
    'u32': 'uint32_t', 'u64': 'uint64_t', 'f32': 'float', 'f64': 'double',
    'bool': '_Bool', 'void': 'void', 'size': 'size_t', 'uintptr': 'uintptr_t',
    'str': 'hare_str', 'rune': 'uint32_t', 'never': 'void', 'null': 'void*',
    'done': 'int', 'nomem': 'int', 'opaque': 'void',
}
INT_SUF = {'i64': 'LL', 'u8': 'U', 'u16': 'U',
           'u32': 'U', 'u64': 'ULL', 'z': 'UL'}
INT_PRIMS = {
    'int', 'i8', 'i16', 'i32', 'i64',
    'u8', 'u16', 'u32', 'u64',
    'size', 'uint', 'uintptr',
    'rune', 'char',
}
FLOAT_PRIMS = {'f32', 'f64'}


# --- C Header and Runtime Declarations ---

def make_prelude(filename):
    escaped = filename.replace('\\', '\\\\').replace('"', '\\"')
    return f'''/* Generated by hare2c - requires GCC or Clang */
#ifndef HARE_H
#define HARE_H
#include <stdint.h>
#include <stddef.h>
typedef struct {{ uint8_t* data; size_t len; }} hare_str;
typedef struct {{ char __m; }} hare_nomem_t;
static hare_str __hare_file = {{.data=(uint8_t*)"{escaped}",.len={len(filename)}}};
#define HARE_DEFINE_SLICE(T, name) typedef struct {{ T* data; size_t len; size_t cap; }} name
#define HARE_ARRAY_LEN(x) (sizeof(x)/sizeof((x)[0]))
extern void rt_abort(hare_str*,uint64_t,uint64_t,hare_str) __attribute__((noreturn));
extern void rt_abort_fixed(hare_str*,uint64_t,uint64_t,uint64_t) __attribute__((noreturn));
extern int rt_strcmp(hare_str a, hare_str b);
#define HARE_SLICE(c,s,e) (hare_slice_intptr_t){{.data=(intptr_t*)(c)+(s),.len=(e)-(s),.cap=HARE_ARRAY_LEN(c)-(s)}}
#define HARE_ERROR_TAG_BASE 0x80000000U
#define HARE_IS_ERROR(x) (((x).tag & HARE_ERROR_TAG_BASE) != 0)
extern void* rt_malloc(size_t);
extern void* rt_realloc(void*, size_t);
extern void* rt_calloc(size_t, size_t);
extern void rt_free(void*);
#define rt_alloc(i) __extension__ ({{__auto_type __v=(i);__typeof__(__v)*__p=rt_malloc(sizeof(__v));*__p=__v;__p;}})
#define rt_alloc_copy(sl) ({{__auto_type __sl=(sl);__typeof__(__sl) __r;__r.data=rt_malloc(__sl.len*sizeof(*__sl.data));__r.len=__sl.len;__r.cap=__sl.len;for(size_t __i=0;__i<__sl.len;++__i)__r.data[__i]=__sl.data[__i];__r;}})
#define rt_append(sp,v) ({{__auto_type __sp=(sp);if(__sp->len>=__sp->cap){{__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=rt_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}}__sp->data[__sp->len++]=(v);}})
#define rt_insert(sp,i,v) ({{__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap){{__sp->cap=__sp->cap?__sp->cap*2:8;__sp->data=rt_realloc(__sp->data,__sp->cap*sizeof(*__sp->data));}}for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;}})
#define rt_delete(sp,s,e) ({{__auto_type __sp=(sp);size_t __s=(s),__e=(e),__n=__e-__s;for(size_t __i=__s;__i+__n<__sp->len;++__i)__sp->data[__i]=__sp->data[__i+__n];__sp->len-=__n;}})
#define rt_static_append(sp,v,ln) ({{__auto_type __sp=(sp);if(__sp->len>=__sp->cap)rt_abort_fixed(&__hare_file,(ln),0,3);__sp->data[__sp->len++]=(v);}})
#define rt_static_insert(sp,i,v,ln) __extension__ ({{__auto_type __sp=(sp);size_t __i=(i);if(__sp->len>=__sp->cap)rt_abort_fixed(&__hare_file,(ln),0,3);for(size_t __j=__sp->len;__j>__i;--__j)__sp->data[__j]=__sp->data[__j-1];__sp->data[__i]=(v);__sp->len++;}})
#define rt_static_delete(sp,s,e) __extension__ ({{__auto_type __sp=(sp);size_t __s=(s),__e=(e),__n=__e-__s;for(size_t __i=__s;__i+__n<__sp->len;++__i)__sp->data[__i]=__sp->data[__i+__n];__sp->len-=__n;}})
#define rt_slice_assign(d,s,e,src) ({{__auto_type __d=(d);__auto_type __src=(src);for(size_t __i=0;__i<(e)-(s);++__i)__d.data[(s)+__i]=__src.data[__i];}})
HARE_DEFINE_SLICE(uint8_t, hare_slice_uint8_t);
#endif
'''
RT_DECLS = '''
#ifndef HARE_RT_MODULE
#define HARE_RT_MODULE
/* rt:: module declarations - matches Hare freestanding rt interface */
extern void rt_memcpy(void* dest, const void* src, size_t n);
extern void rt_memmove(void* dest, const void* src, size_t n);
extern void rt_memset(void* dest, uint8_t val, size_t n);
extern int rt_strcmp(hare_str a, hare_str b);
extern void rt_abort(hare_str* path, uint64_t line, uint64_t col, hare_str msg) __attribute__((noreturn));
extern void rt_abort_fixed(hare_str* path, uint64_t line, uint64_t col, uint64_t i) __attribute__((noreturn));
extern void* rt_malloc(size_t n);
extern void rt_free(void* p);
extern void* rt_realloc(void* p, size_t n);
extern void* rt_calloc(size_t nmemb, size_t size);
extern void rt_init(void);
extern void rt_fini(void);
extern int64_t rt_write(int fd, const void* buf, size_t count);
extern int64_t rt_read(int fd, void* buf, size_t count);
extern void rt_exit(int status) __attribute__((noreturn));
/* Slice type for ensure/unensure operations */
typedef struct { void* data; size_t length; size_t capacity; } rt_slice;
extern void rt_ensure(rt_slice* s, size_t membsz);
extern void rt_unensure(rt_slice* s, size_t membsz);
#endif
'''
STRINGS_DUP_RESULT_NAME = '__hare_strings_dup_result'
STRINGS_DECLS = f'''
#ifndef HARE_STRINGS_MODULE
#define HARE_STRINGS_MODULE
/* strings:: module - function prototypes (implementations in lib/hare/rt.c) */
typedef struct {STRINGS_DUP_RESULT_NAME} {STRINGS_DUP_RESULT_NAME};
extern hare_slice_uint8_t strings_toutf8(hare_str s);
extern hare_str strings_fromutf8_unsafe(hare_slice_uint8_t in);
extern {STRINGS_DUP_RESULT_NAME} strings_dup(hare_str s);
#endif
'''
def tag_name(t):
    return {
        'T:prim': lambda: t[1],
        'T:alias': lambda: t[1][4:] if t[1].startswith('_c::') else mangle_name(t[1]),
        'T:const': lambda: tag_name(t[1]),
        'T:ptr': lambda: 'ptr_' + tag_name(t[1]),
        'T:err': lambda: 'err_' + tag_name(t[1]),
        'T:slice': lambda: 'slice_' + tag_name(t[1]),
        'T:nomem': lambda: 'nomem',
    }.get(t[0], lambda: 'anon')()
def is_void(t):
    if t[0] == 'T:const':
        return is_void(t[1])
    if t[0] == 'T:prim' and t[1] == 'void':
        return True
    if t[0] == 'T:nomem':
        return True  # nomem carries no data
    if t[0] == 'T:alias':
        return is_void(CTX.types.get(t[1], t))
    return False
def get_tuple_type_name(tuple_type):
    types = tuple_type[1]
    key = '_'.join(g_type_simple(t) for t in types)
    if key not in CTX.needed_tuple_types:
        name = f'__hare_tuple_{len(CTX.needed_tuple_types)}'
        CTX.needed_tuple_types[key] = (name, types)
    return CTX.needed_tuple_types[key][0]
def g_type_simple(t):
    if t[0] == 'T:const':
        return g_type_simple(t[1])
    if t[0] == 'T:prim':
        return TYPE_MAP.get(t[1], t[1])
    if t[0] == 'T:ptr':
        return 'ptr_' + g_type_simple(t[1])
    if t[0] == 'T:slice':
        return 'slice_' + g_type_simple(t[1])
    if t[0] == 'T:arr':
        return f'arr{t[2]}_{g_type_simple(t[1])}'
    if t[0] == 'T:alias':
        return mangle_name(t[1])
    if t[0] == 'T:tuple':
        return 'tup_' + '_'.join(g_type_simple(et) for et in t[1])
    return 'unknown'
def err_type_name(t):
    if not t:
        return 'unknown'
    if t[0] == 'T:const':
        return err_type_name(t[1])
    if t[0] in ('T:prim', 'T:alias'):
        return t[1]
    if t[0] in ('T:ptr', 'T:arr', 'T:uarr', 'T:slice'):
        return err_type_name(t[1])
    return 'unknown'
def resolve_array_size(size):
    if size is None:
        return ''
    # Treat '_' the same as None (size inference)
    if isinstance(size, str) and size == '_':
        return ''
    if isinstance(size, int):
        return str(size)
    if isinstance(size, str):
        if size in CTX.defs:
            val = CTX.defs[size]
            if val[0] == 'lit' and isinstance(val[1], int):
                return size
        return size  # Use the identifier directly
    if isinstance(size, tuple):
        return g(size)
    return str(size)

def validate_array_size_inference(ty, init, var_name):
    """Validate that array size inference [_] is used correctly"""
    if ty and ty[0] == 'T:arr':
        # Check if this is size inference (None or '_')
        size = ty[2]
        is_inferred = size is None or (isinstance(size, str) and size == '_')

        if is_inferred and init:
            # Check if initializer is arr_lit with fill-only (no elements)
            if init[0] == 'arr_lit' and init[2] is not None and len(init[1]) == 0:
                CTX.error(
                    f"cannot infer array size for '{var_name}': "
                    f"fill-only initializer [value...] requires explicit array size. "
                    f"Use [N]T = [value...] instead of [_]T = [value...]"
                )
            # For valid cases (has elements), we can infer the size
            # Calculate and update the type with actual size
            if init[0] == 'arr_lit' and len(init[1]) > 0:
                count = len(init[1])
                # Update the type with the inferred size
                ty = ('T:arr', ty[1], count, True)
    return ty

def g_decl(ty, name, const=False, restrict=False):
    type_const = False
    if ty[0] == 'T:const':
        type_const = True
        ty = ty[1]
    use_restrict = restrict and param_supports_restrict(ty)
    if restrict and not use_restrict:
        CTX.error("#[restrict] requires a pointer parameter")
    const_kw = 'const ' if const else ''
    if ty[0] == 'T:arr':
        dims = []
        while ty[0] == 'T:arr':
            dims.append(resolve_array_size(ty[2]))
            ty = ty[1]
        dims_str = ''.join(f'[{d}]' for d in dims)
        elem_t = ty
        elem_str = g(('T:const', elem_t)) if type_const else g(elem_t)
        if elem_t[0] == 'T:ptr' and elem_t[1][0] == 'T:fn':
            fn_type = elem_t[1]
            fn_ret = g(fn_type[2])
            fn_params = ', '.join(g(t) for _, t in fn_type[1]) or 'void'
            return f'{fn_ret} (*{const_kw}{name}{dims_str})({fn_params})'
        return f'{const_kw}{elem_str} {name}{dims_str}'
    if ty[0] == 'T:ptr':
        inner = ty[1]
        ptr_depth = 1
        while inner[0] == 'T:ptr':
            ptr_depth += 1
            inner = inner[1]
        if inner[0] == 'T:arr':
            dims = []
            while inner[0] == 'T:arr':
                dims.append(resolve_array_size(inner[2]))
                inner = inner[1]
            elem_str = g(('T:const', inner)) if type_const else g(inner)
            stars = '*' * ptr_depth
            qual = 'restrict ' if use_restrict else ''
            return f'{elem_str} ({stars}{const_kw}{qual}{name})' + ''.join(f'[{d}]' for d in dims)
        if ptr_depth == 1 and inner[0] == 'T:fn':
            return f'{g(inner[2])} (*{const_kw}{name})({", ".join(g(t) for _, t in inner[1]) or "void"})'
        ptr_str = g(ty)
        if type_const:
            ptr_str = f'const {ptr_str}'
        qual = 'restrict ' if use_restrict else ''
        return f'{ptr_str} {const_kw}{qual}{name}'
    if ty[0] == 'T:fn':
        return f'{g(ty[2])} (*{const_kw}{name})({", ".join(g(t) for _, t in ty[1]) or "void"})'
    if type_const and const:
        const_kw = ''
    qual = 'restrict ' if use_restrict else ''
    return f'{const_kw}{g(ty)} {qual}{name}'


def g_param_decl(param):
    return g_decl(param_type(param), param_name(param), restrict=param_has_attr(param, 'restrict'))

def is_packed_struct(ty):
    return ty and ty[0] == 'T:struct' and len(ty) > 2 and bool(ty[2])

def struct_field_decls(fields):
    parts = []
    for fn, ft in fields:
        if fn is None:
            parts.append(f'{g(ft)};')
            continue
        parts.append(f'{g_decl(ft, fn)};')
    return parts
def _g_type_ptr(n):
    inner = n[1]
    if inner[0] == 'T:uarr':
        return f'{g(inner[1])}*'
    if inner[0] == 'T:arr':
        elem = inner
        while elem[0] == 'T:arr':
            elem = elem[1]
        return f'{g(elem)}*'
    if inner[0] == 'T:fn':
        params = ", ".join(g(t) for _, t in inner[1]) or "void"
        return f'{g(inner[2])} (*)({params})'
    return f'{g(inner)}*'
def _g_type_slice(n):
    elem = n[1]
    if elem[0] == 'T:arr':
        inner, sz = g(elem[1]).replace(' ', '_').replace('*', 'ptr'), elem[2]
        name = f'hare_slice_arr{sz}_{inner}'
        CTX.slice_typedefs[name] = (elem[1], sz)
        return name
    elem_c = g(elem).replace(" ", "_").replace("*", "ptr")
    if elem_c != 'uint8_t':
        CTX.needed_slice_types.add((elem_c, g(elem)))
    return f'hare_slice_{elem_c}'
TYPE_GENERATORS = {
    'T:prim': lambda n: TYPE_MAP.get(n[1], n[1]),
    'T:const': lambda n: f'const {g(n[1])}',
    'T:ptr': _g_type_ptr,
    'T:slice': _g_type_slice,
    'T:arr': lambda n: g(n[1]),
    'T:uarr': lambda n: f'{g(n[1])}*',
    'T:struct': lambda n: f'struct{" __attribute__((packed))" if is_packed_struct(n) else ""} {{ {" ".join(struct_field_decls(n[1]))} }}',
    'T:union': lambda n: f'union {{ {" ".join(g_decl(t, nm) + ";" for nm, t in n[1])} }}',
    'T:tuple': get_tuple_type_name,
    'T:tagged': lambda n: f'struct {{ uint32_t tag; union {{ {" ".join(f"char _{tag_name(t)}_m;" if is_void(t) else f"{g(t)} _{tag_name(t)};" for t in n[1])} }} value; }}',
    'T:err': lambda n: 'intptr_t' if (resolve_aliases(n[1]) and resolve_aliases(n[1])[0] == 'T:prim' and resolve_aliases(n[1])[1] == 'void') else g(n[1]),
    'T:nomem': lambda n: 'hare_nomem_t',
    'T:alias': lambda n: n[1][4:] if n[1].startswith('_c::') else mangle_name(n[1]),
    'T:fn': lambda n: f'{g(n[2])} (*)({"void" if not n[1] else ", ".join(g(t) for _, t in n[1])})',
    'T:enum': lambda n: g(n[2] if n[2] else ('T:prim', 'int')),
}
def g_type(n):
    return TYPE_GENERATORS.get(n[0], lambda x: str(x))(n)


# --- Expression Generators ---

def mk_bounds_check(idx_expr, len_expr, ln=0):
    return f'((void)((size_t)({idx_expr})>=(size_t)({len_expr})?(rt_abort_fixed(&__hare_file,{ln},0,0),(void)0):(void)0))'


def g_id(n):
    name = n[1]
    if name.startswith('_c::'):
        return name[4:]
    if '::' in name:
        parts = name.split('::')
        if len(parts) == 2:
            enum_name, member = parts
            if enum_name in CTX.enums:
                val = CTX.enums[enum_name].get(member)
                if val is not None:
                    return str(val)
    if name not in CTX.vars and name not in CTX.global_types and name not in CTX.funcs:
        resolved = resolve_aliases(('T:alias', name))
        if resolved and resolved[0] == 'T:err':
            inner = resolve_aliases(resolved[1])
            if inner and inner[0] == 'T:prim' and inner[1] == 'void':
                return f'(({mangle_name(name)})0)'
    return mangle_name(name)
def g_lit(n):
    v, h = n[1], n[2]
    if h == 'str':
        byte_len = len(v.encode('utf-8'))
        cast = '' if CTX.in_static_init else '(hare_str)'
        if '\n' in v:
            lines = v.split('\n')
            c_str = ' '.join(f'"{escape_c_string(line)}\\n"' if i < len(lines) - 1 else f'"{escape_c_string(line)}"'
                           for i, line in enumerate(lines))
        else:
            c_str = f'"{escape_c_string(v)}"'
        return f'{cast}{{.data=(uint8_t*){c_str},.len={byte_len}}}'
    if h == 'bool':
        return '1' if v else '0'
    if h in ('null', 'void'):
        return 'NULL' if h == 'null' else '(void)0'
    if h == 'never':
        return '(rt_abort_fixed(&__hare_file,0,0,4), 0)'
    if h == 'done':
        return '0'
    if h == 'rune':
        return f'(uint32_t){v}'
    if h == 'i':
        return f'(intptr_t){v}'
    if h == 'u':
        return f'(uintptr_t){v}'
    if isinstance(v, float):
        return f'{v}f' if h == 'f32' else str(v)
    suffix = INT_SUF.get(h, '')
    if not suffix and isinstance(v, int) and v > 9223372036854775807:
        suffix = 'ULL'
    return f'{v}{suffix}'
def is_str_expr(n):
    if n[0] == 'lit':
        return n[2] == 'str'
    if n[0] == 'id':
        ty = CTX.vars.get(n[1])  # Single lookup with get()
        return ty and ty[0] == 'T:prim' and ty[1] == 'str'
    if n[0] == 'call' and n[1][0] == 'id':
        func_info = CTX.funcs.get(n[1][1])  # Single lookup with get()
        if func_info:
            ret_ty = func_info.get('ret_type')
            return ret_ty and ret_ty[0] == 'T:prim' and ret_ty[1] == 'str'
    return False
def g_bin(n):
    op, left, right = n[1], n[2], n[3]
    if op == '^^':
        return f'(({g(left)}) ? !({g(right)}) : ({g(right)}))'
    if op in ('==', '!=') and (is_str_expr(left) or is_str_expr(right)):
        cmp = f'rt_strcmp({g(left)}, {g(right)})'
        return cmp if op == '==' else f'(!{cmp})'
    return f'({g(left)} {op} {g(right)})'
def coerce_array_to_slice(expr, target_ty):
    target_resolved = resolve_aliases(strip_const(target_ty))
    if not target_resolved or target_resolved[0] != 'T:slice':
        return None
    target_c = g(strip_const(target_ty))
    elem_ty = target_resolved[1]
    elem_c = g(elem_ty)
    if expr[0] == 'arr_lit' and expr[2] is None:
        elems = expr[1]
        count = len(elems)
        if count == 0:
            return f'(({target_c}){{.data = NULL, .len = 0, .cap = 0}})'
        init = ', '.join(g(e) for e in elems)
        return f'(({target_c}){{.data = ({elem_c}[]){{{init}}}, .len = {count}, .cap = {count}}})'
    expr_ty = infer_expr_type(expr)
    expr_ty = resolve_aliases(strip_const(expr_ty)) if expr_ty else None
    if not expr_ty or expr_ty[0] != 'T:arr':
        return None
    if not types_match(expr_ty[1], elem_ty, resolve_aliases=True):
        return None
    expr_s = g(expr)
    return f'(({target_c}){{.data = ({elem_c}*)({expr_s}), .len = HARE_ARRAY_LEN({expr_s}), .cap = HARE_ARRAY_LEN({expr_s})}})'

def g_call(n):
    func, args = n[1], n[2]
    fn_name = func[1] if func[0] == 'id' else None
    if fn_name and fn_name.startswith('_c::'):
        c_name = fn_name[4:]  # Strip '_c::' prefix
        return f'{c_name}({", ".join(g(a) for a in args)})'
    if fn_name and '::' in fn_name:
        expanded = expand_module_alias(fn_name)
        if '::' in expanded:
            prefix = '::'.join(expanded.split('::')[:-1])
            if prefix not in CTX.imports:
                raise ValueError(
                    f"unknown namespace '{prefix}' in '{fn_name}' - add 'use {prefix};'")
    c_name = CTX.funcs.get(fn_name, {}).get(
        'c_name', mangle_name(fn_name) if fn_name else g(func))
    info = CTX.funcs.get(fn_name)
    def coerce_arg(arg, param_ty):
        slice_coerced = coerce_array_to_slice(arg, param_ty)
        if slice_coerced is not None:
            return slice_coerced
        pt = resolve_aliases(strip_const(param_ty))
        if pt and pt[0] == 'T:prim' and pt[1] == 'f32':
            if is_untyped_float_lit(arg):
                return f'{arg[1]}f'
            if arg[0] == 'un' and arg[1] == '-' and is_untyped_float_lit(arg[2]):
                return f'(-{arg[2][1]}f)'
        if param_ty and param_ty[0] == 'T:alias' and param_ty[1] in CTX.tagged:
            tagged_name = param_ty[1]
            arg_ty = infer_expr_type(arg)
            if arg_ty and not (arg_ty[0] == 'T:alias' and arg_ty[1] == tagged_name):
                variant = select_tagged_variant(tagged_name, arg)
                if variant:
                    tag = tag_name(variant)
                    arg_expr = '' if is_void(variant) else g(arg)
                    return f'{tagged_name}_from_{tag}({arg_expr})'
        return g(arg)
    if info:
        params, is_va = info['params'], info['variadic']
        if is_va:
            n_fixed = len(params) - 1
            fixed = [coerce_arg(a, params[i][1]) for i, a in enumerate(args[:n_fixed])]
            for i in range(len(args), n_fixed):
                if params[i][2]:
                    fixed.append(g(params[i][2]))
            var_args = args[n_fixed:]
            if len(var_args) == 1 and var_args[0][0] == 'spread':
                slice_s = g(var_args[0][1])
            elif var_args:
                init = ', '.join(g(a) for a in var_args)
                slice_s = f'((hare_slice_intptr_t){{.data = (intptr_t[]){{{init}}}, .len = {len(var_args)}, .cap = {len(var_args)}}})'
            else:
                slice_s = '((hare_slice_intptr_t){.data = NULL, .len = 0, .cap = 0})'
            return f'{c_name}({", ".join(fixed + [slice_s])})'
        elif len(args) < len(params):
            full = list(args) + [p[2] for p in params[len(args):] if p[2]]
            return f'{c_name}({", ".join(coerce_arg(a, params[i][1]) for i, a in enumerate(full))})'
    if info:
        return f'{c_name}({", ".join(coerce_arg(a, params[i][1]) for i, a in enumerate(args))})'
    return f'{c_name}({", ".join(g(a) for a in args)})'
def select_tagged_variant(tagged_name, val_node):
    variants = CTX.tagged.get(tagged_name, [])
    if val_node[0] == 'lit' and val_node[2] == 'void':
        return next((v for v in variants if is_void(v)), None)
    if val_node[0] == 'lit' and val_node[2] == 'done':
        return next((v for v in variants if v == ('T:prim', 'done') or v == ('T:alias', 'done')), None)

    val_ty = infer_expr_type(val_node)
    is_id_type = val_node[0] == 'id' and val_node[1] in CTX.types
    id_type_name = val_node[1] if is_id_type else None

    # Check type compatibility flags once
    is_int_ty = val_ty and val_ty[0] == 'T:prim' and val_ty[1] == 'int'
    is_f64_ty = val_ty and val_ty[0] == 'T:prim' and val_ty[1] == 'f64'

    # Single pass with priority matching
    int_fallback = None
    float_fallback = None
    id_match = None

    for vt in variants:
        # Priority 1: Exact type match
        if val_ty and types_match(vt, val_ty, resolve_aliases=True):
            return vt
        # Priority 2: ID type name match
        if id_type_name and vt[0] in ('T:alias', 'T:prim') and vt[1] == id_type_name:
            id_match = vt
        # Priority 3: Int fallback
        if is_int_ty and not int_fallback and vt[0] == 'T:prim' and vt[1] in ('int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'size', 'uint'):
            int_fallback = vt
        # Priority 4: Float fallback
        if is_f64_ty and not float_fallback and vt[0] == 'T:prim' and vt[1] in ('f64', 'f32'):
            float_fallback = vt

    return id_match or int_fallback or float_fallback
def g_cast(n):
    val, ty = n[1], n[2]
    ln = n[3] if len(n) > 3 else 0
    old_line = CTX.current_line
    if ln:
        CTX.current_line = ln
    val_ty = infer_expr_type(val)
    is_null_lit = val and val[0] == 'lit' and val[2] == 'null'
    is_void_lit = val and val[0] == 'lit' and val[2] == 'void'
    if is_void(ty) and not is_void_lit:
        CTX.error("cannot cast to void")
    is_int_lit = (val[0] == 'lit' and isinstance(val[1], int) and val[2] not in ('null', 'void', 'nomem', 'str', 'bool', 'f32', 'f64'))
    if ty[0] == 'T:ptr' and is_int_lit:
        CTX.error("invalid cast from integer literal to pointer")
    if is_nonnull_ptr_type(ty) and (is_null_lit or is_nullable_ptr_type(val_ty)):
        CTX.error("cannot cast nullable pointer to non-nullable (use match instead)")
    CTX.current_line = old_line
    if val_ty and ty and types_match(val_ty, ty, resolve_aliases=True):
        return g(val)
    if val_ty and val_ty[0] == 'T:alias' and val_ty[1] in CTX.tagged:
        tagged_name = val_ty[1]
        for vt in CTX.tagged.get(tagged_name, []):
            if types_match(vt, ty, resolve_aliases=True):
                return f'(({g(val)}).value._{tag_name(vt)})'
    if ty[0] == 'T:alias' and ty[1] in CTX.tagged:
        tagged_name = ty[1]
        variant = select_tagged_variant(tagged_name, val)
        if variant:
            tag = tag_name(variant)
            arg = '' if is_void(variant) else g(val)
            return f'{tagged_name}_from_{tag}({arg})'
    slice_coerced = coerce_array_to_slice(val, ty)
    if slice_coerced is not None:
        return slice_coerced
    if ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr' and ty[1][1] == ('T:prim', 'u8'):
        if val[0] == 'lit' and val[2] == 'str':
            CTX.error("cannot cast str literal to *[*]u8; use strings::toutf8(\"...\") instead")
        if val_ty and val_ty[0] == 'T:prim' and val_ty[1] == 'str':
            CTX.error("cannot cast str to *[*]u8; use strings::toutf8(s) instead")
    if ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr':
        is_slice_src = val_ty and val_ty[0] == 'T:slice'
        is_str_to_bytes_call = (val[0] == 'call' and val[1][0] == 'id' and
                         is_module_fn(val[1][1], 'strings', 'toutf8'))
        if is_slice_src or is_str_to_bytes_call:
            target_c = g(ty)
            return f'({{ __auto_type __s = {g(val)}; ({target_c})(__s.data); }})'
    if ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr':
        if val_ty and val_ty[0] == 'T:arr':
            return f'({g(val)})'
    if val[0] == 'un' and val[1] == '&' and ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr':
        inner = val[2]
        if inner[0] == 'id' and inner[1] in CTX.vars:
            inner_ty = CTX.vars[inner[1]]
            if inner_ty and inner_ty[0] == 'T:arr':
                return f'({g(inner)})'
            # Handle &slice: *[*]T by extracting .data from slice
            if inner_ty and inner_ty[0] == 'T:slice':
                target_c = g(ty)
                return f'(({target_c})({g(inner)}.data))'
        # Handle &(id: T): S pattern where id is a slice - extract .data
        # This handles parser behavior where &x: T parses as &(x: T)
        if inner[0] == 'cast' and inner[1][0] == 'id':
            inner_id = inner[1][1]
            if inner_id in CTX.vars:
                inner_ty = CTX.vars[inner_id]
                if inner_ty and inner_ty[0] == 'T:slice':
                    target_c = g(ty)
                    return f'(({target_c})({g(inner[1])}.data))'
                if inner_ty and inner_ty[0] == 'T:arr':
                    return f'({g(inner[1])})'
    return f'(({g(ty)})({g(val)}))'
def g_is(n):
    val, ty = n[1], n[2]
    val_ty = None
    if val[0] == 'id' and val[1] in CTX.vars:
        val_ty = CTX.vars[val[1]]
    if ty[0] == 'T:prim' and ty[1] == 'null':
        return f'(({g(val)}) == NULL)'
    if val_ty and val_ty[0] == 'T:alias' and val_ty[1] in CTX.tagged:
        variants = CTX.tagged[val_ty[1]]
        for i, v in enumerate(variants):
            if tagged_case_matches(v, ty):
                is_err = v[0] in ('T:err', 'T:nomem') or (
                    v[0] == 'T:alias' and CTX.types.get(v[1], (None,))[0] in ('T:err', 'T:nomem'))
                tag_val = f'(HARE_ERROR_TAG_BASE + {i}U)' if is_err else f'{i}U'
                return f'(({g(val)}).tag == {tag_val})'
    return f'(({g(val)}).tag == 0U)'
def g_idx(n):
    t, idx = n[1], n[2]
    ln = n[3] if len(n) > 3 else 0
    idx_str, ty = g(idx), None
    if t[0] == 'id' and t[1] in CTX.vars:
        ty = CTX.vars[t[1]]
    else:
        ty = infer_expr_type(t)
    ty = strip_const(ty)
    if ty:
        reject_nullable_chain(ty, "cannot index through nullable pointer (use match to narrow type)")
        if ty[0] == 'T:slice':
            return f'({mk_bounds_check(idx_str, f"({g(t)}).len", ln)}, ({g(t)}).data[{idx_str}])'
        if ty[0] == 'T:arr':
            size = resolve_array_size(ty[2]) or f'HARE_ARRAY_LEN({g(t)})'
            return f'({mk_bounds_check(idx_str, size, ln)}, ({g(t)})[{idx_str}])'
        if ty[0] == 'T:uarr':
            return f'({g(t)})[{idx_str}]'
        if ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr':
            return f'({g(t)})[{idx_str}]'
        if ty[0] == 'T:ptr':
            inner, ptr_depth = ty[1], 1
            while inner[0] == 'T:ptr':
                ptr_depth += 1
                inner = inner[1]
            if inner[0] == 'T:arr':
                derefs = '*' * ptr_depth
                size = resolve_array_size(inner[2]) or f'HARE_ARRAY_LEN({derefs}({g(t)}))'
                return f'({mk_bounds_check(idx_str, size, ln)}, ({derefs}({g(t)}))[{idx_str}])'
            if inner[0] != 'T:uarr':
                CTX.error(f"Can only index into array or slice object, but got {err_type_name(inner)}")
    return f'({g(t)})[{idx_str}]'
def g_idx_lvalue(n):
    t, idx = n[1], n[2]
    ln = n[3] if len(n) > 3 else 0
    idx_str, inner_checks, inner_expr = g(idx), *g_lvalue_with_checks(t)
    ty = CTX.vars[t[1]] if t[0] == 'id' and t[1] in CTX.vars else infer_expr_type(t)
    ty = strip_const(ty)
    checks = inner_checks[:]
    if ty:
        reject_nullable_chain(ty, "cannot index through nullable pointer (use match to narrow type)")
        if ty[0] == 'T:slice':
            checks.append(mk_bounds_check(idx_str, f'({inner_expr}).len', ln))
            return (checks, f'({inner_expr}).data[{idx_str}]')
        if ty[0] == 'T:arr':
            size = resolve_array_size(ty[2]) or f'HARE_ARRAY_LEN({inner_expr})'
            checks.append(mk_bounds_check(idx_str, size, ln))
            return (checks, f'({inner_expr})[{idx_str}]')
        if ty[0] == 'T:uarr':
            return (checks, f'({inner_expr})[{idx_str}]')
        if ty[0] == 'T:ptr' and ty[1][0] == 'T:uarr':
            return (checks, f'({inner_expr})[{idx_str}]')
        if ty[0] == 'T:ptr':
            inner, ptr_depth = ty[1], 1
            while inner[0] == 'T:ptr':
                ptr_depth += 1
                inner = inner[1]
            if inner[0] == 'T:arr':
                derefs = '*' * ptr_depth
                size = resolve_array_size(inner[2]) or f'HARE_ARRAY_LEN({derefs}({inner_expr}))'
                checks.append(mk_bounds_check(idx_str, size, ln))
                return (checks, f'({derefs}({inner_expr}))[{idx_str}]')
            if inner[0] != 'T:uarr':
                CTX.error(f"Can only index into array or slice object, but got {err_type_name(inner)}")
    return (checks, f'({inner_expr})[{idx_str}]')
def g_fld_lvalue(n):
    t, f = n[1], n[2]
    field_name = f'_{f}' if f.isdigit() else f
    checks, inner_expr = g_lvalue_with_checks(t)
    ty = infer_expr_type(t)
    ptr_depth = 0
    inner_ty = resolve_aliases(strip_const(ty)) if ty else None
    while inner_ty and inner_ty[0] == 'T:ptr':
        ptr_depth += 1
        inner_ty = resolve_aliases(strip_const(inner_ty[1]))
    if ptr_depth > 0:
        reject_nullable_chain(ty, "cannot access field through nullable pointer (use match to narrow type)")
        deref = '*' * ptr_depth
        return (checks, f'({deref}{inner_expr}).{field_name}')
    return (checks, f'{inner_expr}.{field_name}')
def g_lvalue_with_checks(expr):
    if expr[0] == 'idx':
        return g_idx_lvalue(expr)
    elif expr[0] == 'fld':
        return g_fld_lvalue(expr)
    elif expr[0] == 'un' and expr[1] == '*':
        checks, inner = g_lvalue_with_checks(expr[2])
        return (checks, f'(*{inner})')
    else:
        return ([], g(expr))
def contains_idx(expr):
    if not isinstance(expr, tuple):
        return False
    if expr[0] == 'idx':
        return True
    return any(contains_idx(e) for e in expr[1:] if isinstance(e, tuple))
def g_slice(n):
    t, s, e = n[1], n[2], n[3]
    s_str = g(s) if s else '0'
    ty = None
    if t[0] == 'id' and t[1] in CTX.vars:
        ty = CTX.vars[t[1]]
    else:
        ty = infer_expr_type(t)
    if ty and ty[0] == 'T:slice':
        e_str = g(e) if e else f'({g(t)}).len'
        elem_c = g(ty[1])
        inner = elem_c.replace(" ", "_").replace("*", "ptr")
        CTX.needed_slice_types.add((inner, elem_c))
        return f'(hare_slice_{inner}){{.data=({g(t)}).data+{s_str},.len={e_str}-{s_str},.cap=({g(t)}).cap-{s_str}}}'
    if ty and ty[0] == 'T:arr':
        elem_ty = ty[1]
        e_str = g(e) if e else f'HARE_ARRAY_LEN({g(t)})'
        elem_c = g(elem_ty)
        inner = elem_c.replace(" ", "_").replace("*", "ptr")
        CTX.needed_slice_types.add((inner, elem_c))
        return f'(hare_slice_{inner}){{.data=({elem_c}*)({g(t)})+{s_str},.len={e_str}-{s_str},.cap=HARE_ARRAY_LEN({g(t)})-{s_str}}}'
    if ty and ty[0] == 'T:ptr' and ty[1] and ty[1][0] == 'T:uarr':
        elem_ty = ty[1][1]
        e_str = g(e) if e else '0'  # Must have explicit end for unbounded
        elem_c = g(elem_ty)
        inner = elem_c.replace(" ", "_").replace("*", "ptr")
        CTX.needed_slice_types.add((inner, elem_c))
        return f'(hare_slice_{inner}){{.data=({elem_c}*)({g(t)})+{s_str},.len={e_str}-{s_str},.cap={e_str}-{s_str}}}'
    e_str = g(e) if e else f'HARE_ARRAY_LEN({g(t)})'
    return f'HARE_SLICE({g(t)},{s_str},{e_str})'
def g_fld(n):
    t, f = n[1], n[2]
    field_name = f'_{f}' if f.isdigit() else f
    ty = infer_expr_type(t)
    ptr_depth = 0
    inner_ty = resolve_aliases(strip_const(ty)) if ty else None
    while inner_ty and inner_ty[0] == 'T:ptr':
        ptr_depth += 1
        inner_ty = resolve_aliases(strip_const(inner_ty[1]))  # Get inner type
    if ptr_depth > 0:
        reject_nullable_chain(ty, "cannot access field through nullable pointer (use match to narrow type)")
        deref = '*' * ptr_depth
        return f'({deref}{g(t)}).{field_name}'
    return f'{g(t)}.{field_name}'
def g_un(n):
    op, expr = n[1], n[2]
    if op == '*':
        expr_ty = infer_expr_type(expr)
        if is_nullable_ptr_type(expr_ty):
            name = f" '{expr[1]}'" if expr[0] == 'id' else ''
            CTX.error(f"cannot dereference nullable pointer{name} (use match to narrow type)")
    if op == '&' and expr[0] == 'idx':
        t, idx, ln = expr[1], expr[2], expr[3] if len(expr) > 3 else 0
        idx_str = g(idx)
        if t[0] == 'id' and t[1] in CTX.vars:
            ty = CTX.vars[t[1]]
            if ty and ty[0] == 'T:slice':
                return f'({mk_bounds_check(idx_str, f"({g(t)}).len", ln)}, &({g(t)}).data[{idx_str}])'
            if ty and ty[0] == 'T:arr':
                return f'({mk_bounds_check(idx_str, ty[2], ln)}, &({g(t)})[{idx_str}])'
        return f'(&({g(t)})[{idx_str}])'
    if op == '&' and expr[0] == 'cast' and expr[2][0] == 'T:ptr':
        # For &(slice: *[*]T), extract slice.data instead of &slice
        inner_val = expr[1]
        target_ty = expr[2]
        if target_ty[1][0] == 'T:uarr' and inner_val[0] == 'id' and inner_val[1] in CTX.vars:
            inner_ty = CTX.vars[inner_val[1]]
            if inner_ty and inner_ty[0] == 'T:slice':
                return f'(({g(target_ty)})({g(inner_val)}.data))'
            if inner_ty and inner_ty[0] == 'T:arr':
                return f'({g(inner_val)})'
        return f'(({g(expr[2])})(&({g(expr[1])})))'
    return f'({op}{g(expr)})'
def g_if(n):
    c, t, e = n[1], n[2], n[3]
    stmt_kinds = ('ret', 'asgn', 'expr', 'let', 'slet', 'break', 'cont', 'yield', 'for', 'if', 'call')
    def is_stmt_form(x):
        if x is None:
            return False
        if x[0] in ('ret', 'yield', 'break', 'continue', 'cont'):
            return True
        if x[0] == 'block':
            return not x[1] or x[1][0][0] in stmt_kinds
        return False
    def fmt_body(x):
        if x[0] in ('ret', 'yield', 'break', 'continue', 'cont'):
            return '{ ' + g(x) + ' }'
        if x[0] == 'block':
            return g(x)
        return '{ ' + g(x) + '; }'
    is_stmt = is_stmt_form(t) or is_stmt_form(e)
    if is_stmt:
        body = fmt_body(t)
        if e:
            return f'if ({g(c)}) {body} else {fmt_body(e)}'
        return f'if ({g(c)}) {body}'
    return f'(({g(c)}) ? ({g(t)}) : ({g(e) or "0"}))'
def g_block(n):
    ss, yield_expr = n[1], n[2]
    CTX.push_defer_scope()
    saved_vars = dict(CTX.vars)
    body_parts = []
    last_stmt = None
    for stmt in ss:
        if stmt[0] == 'defer':
            CTX.add_defer(stmt[1])
        else:
            code = g(stmt)
            if code:
                body_parts.append(f'    {code}')
            last_stmt = stmt[0]
    if yield_expr:
        defers = CTX.get_current_defers()
        if defers:
            body_parts.append(f'    __auto_type __yield_tmp = {g(yield_expr)};')
            for d in defers:
                body_parts.append(f'    {g(d)};')
            body_parts.append('    __r = __yield_tmp;')
        else:
            body_parts.append(f'    __r = {g(yield_expr)};')
    elif last_stmt not in ('ret', 'break', 'cont'):
        for d in CTX.get_current_defers():
            body_parts.append(f'    {g(d)};')
    CTX.pop_defer_scope()
    CTX.vars.clear()
    CTX.vars.update(saved_vars)
    return '{\n' + '\n'.join(body_parts) + '\n}'
def g_len(n):
    t = n[1]
    ty = infer_expr_type(t)
    if ty and ty[0] == 'T:prim' and ty[1] == 'str':
        return f'({g(t)}).len'
    if ty and ty[0] == 'T:slice':
        return f'({g(t)}).len'
    return f'HARE_ARRAY_LEN({g(t)})'
def g_sizeof_type(ty):
    if ty[0] == 'T:arr':
        dims = []
        inner = ty
        while inner[0] == 'T:arr':
            dims.append(inner[2] if inner[2] else '')
            inner = inner[1]
        dims_str = ''.join(f'[{d}]' for d in dims)
        return f'sizeof({g(inner)}{dims_str})'
    return f'sizeof({g(ty)})'
def g_free(n):
    t = n[1]
    if t[0] == 'id' and t[1] in CTX.vars:
        ty = strip_const(CTX.vars[t[1]])
        if ty and ty[0] == 'T:slice':
            return f'rt_free(({g(t)}).data)'
    return f'rt_free({g(t)})'
def g_struct_lit(n):
    name, fields = n[1], n[2]
    init_parts = []
    for fn, fv, ty in fields:
        prev_target = getattr(CTX, 'arr_lit_target_size', None)
        if ty and ty[0] == 'T:arr' and isinstance(ty[2], int):
            CTX.arr_lit_target_size = ty[2]
        else:
            CTX.arr_lit_target_size = None
        init_parts.append(f'.{fn}={g(fv)}')
        CTX.arr_lit_target_size = prev_target
    init = ', '.join(init_parts)
    if name:
        return f'{{ {init} }}' if CTX.in_static_init else f'({name.replace("::","_")}){{ {init} }}'
    has_types = all(ty is not None for _, _, ty in fields)
    if has_types:
        parts = []
        for fn, _, ty in fields:
            parts.append(f'{g_decl(ty, fn)};')
        type_def = ' '.join(parts)
        return f'{{ {init} }}' if CTX.in_static_init else f'(struct {{ {type_def} }}){{ {init} }}'
    temps = ' '.join(f'__auto_type __{fn} = {g(fv)};' for fn, fv, _ in fields)
    types = ' '.join(f'__typeof__(__{fn}) {fn};' for fn, _, _ in fields)
    init = ', '.join(f'.{fn} = __{fn}' for fn, _, _ in fields)
    return f'(__extension__ ({{ {temps} struct {{ {types} }} __r = {{ {init} }}; __r; }}))'
def g_tuple_lit(n):
    es = n[1]
    if not es:
        return '(struct { char __empty; }){}'
    elem_types = [infer_expr_type(e) or ('T:prim', 'int') for e in es]
    tuple_type = ('T:tuple', elem_types)
    type_name = get_tuple_type_name(tuple_type)
    init = ', '.join(f'._{i} = {g(e)}' for i, e in enumerate(es))
    return f'({type_name}){{ {init} }}'
def g_alloc_expr(n):
    val = n[1]
    val_type = infer_expr_type(val)
    if val_type:
        ptr_type = ('T:ptr', val_type, False)
        result_name = get_alloc_result_type_name(ptr_type)
        ptr_tag = tag_name(ptr_type)
        c_type = g(val_type)  # Get proper C type
        if val[0] == 'arr_lit' and val[2] is not None and not val[1]:
            fill = g(val[2])
            elem_c = g(val_type[1]) if val_type[0] == 'T:slice' else c_type
            if fill == '0':
                return f'''(__extension__ ({{
    {c_type} *__p = rt_calloc(1, sizeof({c_type}));
    {result_name} __r;
    if (__p) {{ __r = {result_name}_from_{ptr_tag}(__p); }}
    else {{ __r = {result_name}_from_nomem(); }}
    __r;
}}))'''
        return f'''(__extension__ ({{
    {c_type} __v = ({c_type}){g(val)};
    {c_type} *__p = rt_malloc(sizeof({c_type}));
    {result_name} __r;
    if (__p) {{ *__p = __v; __r = {result_name}_from_{ptr_tag}(__p); }}
    else {{ __r = {result_name}_from_nomem(); }}
    __r;
}}))'''
    return f'rt_alloc({g(val)})'
def g_alloc_cp_expr(n):
    slice_expr = n[1]
    slice_type = infer_expr_type(slice_expr)
    if slice_type and slice_type[0] == 'T:slice':
        result_name = get_alloc_result_type_name(slice_type)
        slice_tag = tag_name(slice_type)
        elem_type = slice_type[1]
        elem_c = g(elem_type)
        slice_c = g(slice_type)
        return f'''(__extension__ ({{
    __auto_type __src = {g(slice_expr)};
    {elem_c}* __data = rt_malloc(__src.len * sizeof({elem_c}));
    {result_name} __r;
    if (__data) {{
        for (size_t __i = 0; __i < __src.len; ++__i) __data[__i] = __src.data[__i];
        __r = {result_name}_from_{slice_tag}(({slice_c}){{.data = __data, .len = __src.len, .cap = __src.len}});
    }} else {{
        __r = {result_name}_from_nomem();
    }}
    __r;
}}))'''
    return f'rt_alloc_copy({g(slice_expr)})'
def g_alloc_sl_expr(n):
    val, count = n[1], n[2]
    if val[0] == 'arr_lit' and val[1]:
        elem_type = infer_expr_type(val[1][0])
        if elem_type:
            slice_type = ('T:slice', elem_type)
            result_name = get_alloc_result_type_name(slice_type)
            slice_tag = tag_name(slice_type)
            elem_c = g(elem_type)
            slice_c = g(slice_type)
            init = ', '.join(g(e) for e in val[1])
            return f'''(__extension__ ({{
    {elem_c}* __data = rt_malloc((size_t){g(count)} * sizeof({elem_c}));
    {result_name} __r;
    if (__data) {{
        {elem_c} __init[] = {{{init}}};
        for (size_t __i = 0; __i < {len(val[1])}; ++__i) __data[__i] = __init[__i];
        __r = {result_name}_from_{slice_tag}(({slice_c}){{.data = __data, .len = {len(val[1])}, .cap = (size_t){g(count)}}});
    }} else {{
        __r = {result_name}_from_nomem();
    }}
    __r;
}}))'''
    return f'rt_alloc_slice({g(val)},{g(count)})'
def _unwrap_alloc(init, kind):
    if init and init[0] == kind:
        return init
    if init and init[0] in ('unwrap', 'prop') and init[1][0] == kind:
        return init[1]
    return None
def _strip_addr_for_uarr(val, target_ty):
    if not (val and target_ty and target_ty[0] == 'T:ptr' and target_ty[1][0] == 'T:uarr'):
        return val
    if val[0] == 'un' and val[1] == '&' and val[2][0] == 'id' and val[2][1] in CTX.vars:
        inner_ty = CTX.vars[val[2][1]]
        if inner_ty and inner_ty[0] == 'T:arr':
            return val[2]
    return val
def _infer_let_type(name, ty, init):
    if ty:
        if ty[0] == 'T:arr' and ty[2] is None and init and init[0] == 'arr_lit' and init[2] is None:
            ty = ('T:arr', ty[1], len(init[1]), True)
        CTX.vars[name] = ty
        return ty
    if init and init[0] == 'cast':
        CTX.vars[name] = init[2]  # Cast target type
        return ty
    if init and init[0] == 'call':
        fn_name = init[1][1] if init[1][0] == 'id' else None
        if fn_name and fn_name in CTX.funcs:
            inferred = CTX.funcs[fn_name].get('ret_type')
            if inferred:
                CTX.vars[name] = inferred
        elif fn_name and is_module_fn(fn_name, 'strings', 'toutf8'):
            CTX.vars[name] = ('T:slice', ('T:prim', 'u8'))
        elif fn_name and is_module_fn(fn_name, 'strings', 'fromutf8_unsafe'):
            CTX.vars[name] = ('T:prim', 'str')
        elif fn_name and is_module_fn(fn_name, 'strings', 'dup'):
            CTX.vars[name] = ('T:alias', get_strings_dup_result_type_name())
    elif init and init[0] in ('alloc', 'alloc_cp', 'alloc_sl'):
        inner = infer_expr_type(init[1])
        if inner:
            ptr_type = ('T:ptr', inner, False) if init[0] == 'alloc' else (
                inner if inner[0] == 'T:slice' else ('T:slice', inner))
            CTX.vars[name] = ('T:alias', get_alloc_result_type_name(ptr_type))
    elif init and init[0] == 'slice':
        inferred = infer_expr_type(init)
        if inferred:
            CTX.vars[name] = inferred
    elif init:
        inferred = infer_expr_type(init)
        if inferred:
            CTX.vars[name] = inferred
    return ty

def _gen_slice_from_arr_lit(name, ty, init, const):
    """Generate code for slice initialized from array literal."""
    elem = g(ty[1])
    elems = init[1]
    arr_init = ', '.join(g(e) for e in elems) or '0'
    return f'{elem} __{name}_data[] = {{ {arr_init} }};\n    {const}{g(ty)} {name} = {{.data = __{name}_data, .len = {len(elems)}, .cap = {len(elems)}}};'

def _gen_slice_from_alloc_sl(name, ty, alloc_init, const):
    """Generate code for slice initialized from alloc(arr_lit, cap)."""
    arr_lit, cap = alloc_init[1], alloc_init[2]
    elem_ty = ty[1]
    elem = g(elem_ty)
    if arr_lit[0] == 'arr_lit' and arr_lit[1]:
        elems = arr_lit[1]
        is_f32_elem = elem_ty[1] == 'f32' and elem_ty[0] in ('T:prim', 'T:alias')
        def gen_elem(e):
            if is_f32_elem and e[0] == 'lit' and isinstance(e[1], float) and e[2] in (None, 'f64'):
                return f'{e[1]}f'
            return g(e)
        assigns = ' '.join(f'__{name}_data[{i}] = {gen_elem(e)};' for i, e in enumerate(elems))
        return f'{elem}* __{name}_data = rt_malloc({g(cap)} * sizeof({elem})); {assigns}\n    {const}{g(ty)} {name} = {{.data = __{name}_data, .len = {len(elems)}, .cap = {g(cap)}}};'
    return None

def _gen_tagged_union_init(name, ty, init, const):
    """Generate code for tagged union initialization from literal or type name."""
    type_name = ty[1]
    variants = CTX.tagged[type_name]
    if init[0] == 'id' and init[1] in CTX.types:
        v = next((v for v in variants if (v[0] in ('T:alias', 'T:prim') and v[1] == init[1])), None)
        if v:
            arg = '' if is_void(v) else '0'
            return f'{const}{g(ty)} {name} = {type_name}_from_{init[1]}({arg});'
    # Handle cast expressions: e.g., `let err1: error = 1: invalid;`
    if init[0] == 'cast':
        cast_ty = init[2]
        # Check if cast type is one of the variants
        if cast_ty[0] == 'T:alias':
            v = next((v for v in variants if (v[0] == 'T:alias' and v[1] == cast_ty[1])), None)
            if v:
                return f'{const}{type_name} {name} = {type_name}_from_{cast_ty[1]}({g(init[1])});'
        elif cast_ty[0] == 'T:prim':
            v = next((v for v in variants if (v[0] == 'T:prim' and v[1] == cast_ty[1])), None)
            if v:
                return f'{const}{type_name} {name} = {type_name}_from_{cast_ty[1]}({g(init[1])});'
    # Handle struct literals for tagged unions
    if init[0] == 'struct_lit' and init[1]:
        v = next((v for v in variants if (v[0] == 'T:alias' and v[1] == init[1])), None)
        if v:
            return f'{const}{type_name} {name} = {type_name}_from_{init[1]}({g(init)});'
    # Handle unary expressions wrapping casts: e.g., `let err1: error = -1: invalid;`
    # Parsed as: ('un', '-', ('cast', ('lit', 1), ('T:alias', 'invalid')))
    if init[0] == 'un' and len(init) > 2 and init[2][0] == 'cast':
        inner_cast = init[2]
        cast_ty = inner_cast[2]
        if cast_ty[0] == 'T:alias':
            v = next((v for v in variants if (v[0] == 'T:alias' and v[1] == cast_ty[1])), None)
            if v:
                # Generate the full unary expression: -(1) as the value
                val_expr = f'{init[1]}({g(inner_cast[1])})'
                return f'{const}{type_name} {name} = {type_name}_from_{cast_ty[1]}({val_expr});'
        elif cast_ty[0] == 'T:prim':
            v = next((v for v in variants if (v[0] == 'T:prim' and v[1] == cast_ty[1])), None)
            if v:
                val_expr = f'{init[1]}({g(inner_cast[1])})'
                return f'{const}{type_name} {name} = {type_name}_from_{cast_ty[1]}({val_expr});'
    if init[0] == 'lit':
        hint = init[2]
        for v in variants:
            v_tag = tag_name(v)
            if v[0] == 'T:prim' and v[1] == 'bool' and hint == 'bool':
                return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'
            if v[0] == 'T:prim' and v[1] == 'str' and hint == 'str':
                return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'
            if v[0] == 'T:prim' and v[1] == 'void' and hint == 'void':
                return f'{const}{type_name} {name} = {type_name}_from_{v_tag}();'
        int_types = ('int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64')
        for v in variants:
            v_tag = tag_name(v)
            if v[0] == 'T:prim' and v[1] in int_types:
                if hint in int_types or (hint is None and isinstance(init[1], int) and not isinstance(init[1], bool)):
                    return f'{const}{type_name} {name} = {type_name}_from_{v_tag}({g(init)});'
    return None


# --- Statement Generators ---

def g_let(n):
    name, ty, init, mut = n[1], n[2], n[3], n[4]
    ln = n[5] if len(n) > 5 else 0
    old_line = CTX.current_line
    if ln:
        CTX.current_line = ln
    if CTX.current_func and name in CTX.global_vars:
        CTX.error(f"variable '{name}' shadows global variable")
        check_warnings_errors()
    if init and is_strings_dup_call(init) and ty and not is_tagged_union_type(ty):
        CTX.error("strings::dup() returns error type (str | !void), must unwrap or handle it")
    ty = _infer_let_type(name, ty, init)
    # Validate array size inference
    ty = validate_array_size_inference(ty, init, name)
    check_nonnull_assignment(f" '{name}'", ty, init)
    CTX.current_line = old_line
    const = '' if mut else 'const '

    # Slice from array literal
    if ty and ty[0] == 'T:slice' and init and init[0] == 'arr_lit':
        return _gen_slice_from_arr_lit(name, ty, init, const)

    # Slice from alloc(arr_lit, cap)
    alloc_sl_init = _unwrap_alloc(init, 'alloc_sl')
    if ty and ty[0] == 'T:slice' and alloc_sl_init:
        result = _gen_slice_from_alloc_sl(name, ty, alloc_sl_init, const)
        if result:
            return result

    # Tagged union initialization
    if ty and ty[0] == 'T:alias' and ty[1] in CTX.tagged and init:
        result = _gen_tagged_union_init(name, ty, init, const)
        if result:
            return result
    alloc_init = _unwrap_alloc(init, 'alloc')
    if ty and ty[0] == 'T:ptr' and ty[1][0] == 'T:arr' and alloc_init:
        if alloc_init[1][0] == 'arr_lit':
            arr_lit = alloc_init[1]
            arr_ty = ty[1]  # T:arr
            elem_ty = arr_ty[1]
            arr_size = arr_ty[2]
            if arr_size:
                if arr_lit[2] is not None and not arr_lit[1]:
                    fill = g(arr_lit[2])
                    if fill == '0':
                        return f'{const}{g_decl(ty, name)} = rt_calloc({arr_size}, sizeof({g(elem_ty)}));'
                    else:
                        return f'{const}{g_decl(ty, name)} = rt_malloc({arr_size} * sizeof({g(elem_ty)})); rt_memset({name}, {fill}, {arr_size} * sizeof({g(elem_ty)}));'
                elif arr_lit[1]:
                    elems = ', '.join(g(e) for e in arr_lit[1])
                    return f'{const}{g_decl(ty, name)} = rt_alloc(({g(elem_ty)}[{arr_size}]){{{elems}}});'
    if ty and ty[0] == 'T:arr' and ty[2] and init and init[0] == 'arr_lit' and init[2] is not None:
        arr_size = ty[2]
        elem_ty = ty[1]
        explicit_elems = init[1]
        if _expr_is_zero_like(init[2]):
            is_const = not mut
            if explicit_elems:
                return f'{g_decl(ty, name, const=is_const)} = {{ {", ".join(g(e) for e in explicit_elems)} }};'
            return f'{g_decl(ty, name, const=is_const)} = {{0}};'
        fill_val = g(init[2])
        numeric_size = None
        if isinstance(arr_size, int):
            numeric_size = arr_size
        elif isinstance(arr_size, str) and arr_size in CTX.defs:
            val = CTX.defs[arr_size]
            if val[0] == 'lit' and isinstance(val[1], int):
                numeric_size = val[1]
        if numeric_size is not None:
            elem_parts = [g(e) for e in explicit_elems]
            remaining = numeric_size - len(explicit_elems)
            elem_parts.extend([fill_val] * remaining)
            is_const = not mut
            return f'{g_decl(ty, name, const=is_const)} = {{ {", ".join(elem_parts)} }};'
        is_const = not mut
        return f'{g_decl(ty, name, const=is_const)} = {{ {", ".join(g(e) for e in explicit_elems)} }};'
    old_expected = CTX.expected_type
    inferred_ty = ty or CTX.vars.get(name)
    if inferred_ty and init and init[0] in ('match', 'switch'):
        CTX.expected_type = inferred_ty
    init = _strip_addr_for_uarr(init, ty)
    is_const = not mut
    if ty:
        decl = g_decl(ty, name, const=is_const)
    elif init and init[0] == 'lit' and isinstance(init[1], int) and init[2] is None:
        decl = f'{"const " if is_const else ""}intptr_t {name}'
    else:
        decl = f'{"const " if is_const else ""}__auto_type {name}'
    is_f32 = ty and ty[1] == 'f32' and ty[0] in ('T:prim', 'T:alias')
    if is_f32 and init and is_untyped_float_lit(init):
        init_str = f' = {init[1]}f'
    elif is_f32 and init and init[0] == 'un' and init[1] == '-' and is_untyped_float_lit(init[2]):
        init_str = f' = (-{init[2][1]}f)'
    else:
        # Set target array size for arr_lit expansion
        if ty and ty[0] == 'T:arr' and isinstance(ty[2], int):
            CTX.arr_lit_target_size = ty[2]
        else:
            CTX.arr_lit_target_size = None
        coerced_init = coerce_array_to_slice(init, ty) if init and ty else None
        init_str = f' = {coerced_init if coerced_init is not None else g(init)}' if init else ''
        CTX.arr_lit_target_size = None
    CTX.expected_type = old_expected
    return f'{decl}{init_str};'
def _g_ret_expr(v):
    if v is None:
        return None
    if CTX.is_tagged_return():
        ret_name = CTX.ret_name
        val_ty = infer_expr_type(v)
        if val_ty and CTX.ret_type and types_match(val_ty, CTX.ret_type, resolve_aliases=True):
            return g(v)
        if v[0] == 'cast' and v[2][0] == 'T:alias' and v[2][1] == ret_name:
            return g(v)
        if v[0] == 'lit' and v[2] == 'void':
            return f'{ret_name}_from_void()'
        if v[0] == 'id' and v[1] in CTX.types:
            underlying = CTX.types.get(v[1])
            arg = '' if underlying and is_void(underlying) else '0'
            return f'{ret_name}_from_{v[1]}({arg})'
        if v[0] in ('match', 'switch'):
            old = CTX.expected_type
            CTX.expected_type = CTX.ret_type
            r = g(v)
            CTX.expected_type = old
            return r
        vt = select_tagged_variant(ret_name, v)
        if vt:
            arg = '' if is_void(vt) else g(v)
            return f'{ret_name}_from_{tag_name(vt)}({arg})'
    return g(v)
def _coerce_ret_expr(v, ret_expr):
    if v is None or ret_expr is None:
        return ret_expr
    if CTX.is_tagged_return():
        return ret_expr
    ret_ty = resolve_aliases(strip_const(CTX.ret_type)) if CTX.ret_type else None
    val_ty = infer_expr_type(v)
    val_ty = resolve_aliases(strip_const(val_ty)) if val_ty else None
    if not ret_ty or not val_ty:
        return ret_expr
    slice_coerced = coerce_array_to_slice(v, CTX.ret_type)
    if slice_coerced is not None:
        return slice_coerced
    if types_match(val_ty, ret_ty, resolve_aliases=True):
        return ret_expr
    if ret_ty[0] == 'T:prim' and val_ty[0] == 'T:prim':
        if ret_ty[1] in INT_PRIMS | FLOAT_PRIMS and val_ty[1] in INT_PRIMS | FLOAT_PRIMS:
            return f'(({g(ret_ty)})({ret_expr}))'
    return ret_expr
def check_return_type_mismatch(ret_val, expected_ret_type):
    """Check if return value type matches function return type."""
    # Note: This check is disabled because *T and *[*]T are both represented as T* in C
    # and are compatible in the C backend, even though they're semantically different in Hare
    # TODO: Re-enable with more nuanced checking if strict Hare semantics are desired
    pass
def g_ret(n):
    v = n[1]
    check_return_type_mismatch(v, CTX.ret_type)
    check_nonnull_assignment(" return value", CTX.ret_type, v)
    defers = CTX.get_all_defers()
    if not defers:
        if v is None:
            return 'return;'
        ret_expr = _g_ret_expr(v)
        ret_expr = _coerce_ret_expr(v, ret_expr)
        return f'return {ret_expr};'
    if v is None:
        cleanup = ' '.join(f'{g(d)};' for d in defers)
        return f'{{ {cleanup} return; }}'
    ret_expr = _g_ret_expr(v)
    ret_expr = _coerce_ret_expr(v, ret_expr)
    cleanup = ' '.join(f'{g(d)};' for d in defers)
    return f'{{ __auto_type __ret_tmp = {ret_expr}; {cleanup} return __ret_tmp; }}'
def g_match_body(body, tagged=None, case_type=None):
    if body[0] == 'yield':
        expr = g(body[1])
        v = body[1]
        if tagged and tagged in CTX.tagged:
            if v[0] == 'id' and v[1] in CTX.vars:
                ty = CTX.vars[v[1]]
                for vt in CTX.tagged[tagged]:
                    if ty == vt or (ty and vt[0] == 'T:alias' and ty[0] == 'T:alias' and ty[1] == vt[1]):
                        return f'__r = {tagged}_from_{tag_name(vt)}({"" if is_void(vt) else expr});'
            if v[0] == 'lit':
                for vt in CTX.tagged[tagged]:
                    if vt[0] == 'T:prim' and vt[1] in ('int', 'i32', 'i64'):
                        return f'__r = {tagged}_from_{tag_name(vt)}({expr});'
        return f'__r = {expr};'
    if body[0] == 'ret':
        val = body[1]
        if val and val[0] == 'id' and val[1] in CTX.vars and CTX.is_tagged_return():
            bound_ty = CTX.vars[val[1]]
            ret_name = CTX.ret_name
            for vt in CTX.tagged.get(ret_name, []):
                if bound_ty == vt or (bound_ty and vt[0] == 'T:alias' and bound_ty[0] == 'T:alias' and bound_ty[1] == vt[1]):
                    return f'return {ret_name}_from_{tag_name(vt)}({"" if is_void(vt) else g(val)});'
        return g(body)
    if body[0] == 'block':
        parts = [g(s) for s in body[1]]
        if body[2]:
            parts.append(g_match_body(
                ('yield', body[2]), tagged, case_type) if tagged else f'__r = {g(body[2])};')
        return ' '.join(parts)
    if body[0] in ('let', 'slet', 'asgn', 'for', 'if', 'break', 'cont'):
        return g(body)
    if body[0] == 'expr':
        inner = body[1]
        if inner[0] in ('abort', 'assert_b', 'free'):
            return g(body)
        if inner[0] == 'lit' and len(inner) > 2 and inner[2] == 'void':
            return g(body)
        inner_type = infer_expr_type(inner)
        if inner_type and inner_type[0] == 'T:prim' and inner_type[1] == 'void':
            return g(body)
        if inner[0] in ('match', 'switch') and inner_type is None:
            return g(body)
        return f'__r = {g(inner)};'
    body_type = infer_expr_type(body)
    if body_type and body_type[0] == 'T:prim' and body_type[1] == 'void':
        return f'{g(body)};'
    return f'__r = {g(body)};'
def _result_type_info():
    tagged = None
    if CTX.expected_type:
        if CTX.expected_type[0] == 'T:alias' and CTX.expected_type[1] in CTX.tagged:
            tagged = CTX.expected_type[1]
        ret_t = g(CTX.expected_type)
    elif CTX.ret_type:
        ret_t = g(CTX.ret_type)
    else:
        ret_t = 'intptr_t'
    if ret_t == 'void':
        ret_t = 'int'
    return ret_t, tagged
def _body_uses_nullable(body_node, var_name, nullable_type):
    """Check if body dereferences or uses nullable variable unsafely."""
    def check_node(n):
        if n is None or not isinstance(n, tuple):
            return False

        # Check for dereference: *var_name
        if n[0] == 'un' and n[1] == '*' and n[2][0] == 'id' and n[2][1] == var_name:
            return True

        # Check for field access: var_name.field (auto-deref)
        if n[0] == 'fld' and n[1][0] == 'id' and n[1][1] == var_name:
            return True

        # Check for array index: var_name[i] (auto-deref)
        if n[0] == 'idx' and n[1][0] == 'id' and n[1][1] == var_name:
            return True

        # Recursively check all sub-nodes
        for item in n[1:]:
            if isinstance(item, tuple) and check_node(item):
                return True
            elif isinstance(item, list):
                for sub_item in item:
                    if isinstance(sub_item, tuple) and check_node(sub_item):
                        return True
        return False

    return check_node(body_node)
def g_match(n):
    val_node = n[1]
    val, cases = g(val_node), n[2]
    matched_type_name = None
    if val_node[0] == 'id':
        val_ty = strip_const(CTX.vars.get(val_node[1]) or CTX.global_types.get(val_node[1]))
        if val_ty and val_ty[0] == 'T:alias' and val_ty[1] in CTX.tagged:
            matched_type_name = val_ty[1]
    if matched_type_name is None:
        inferred_ty = strip_const(infer_expr_type(val_node))
        if inferred_ty and inferred_ty[0] == 'T:alias' and inferred_ty[1] in CTX.tagged:
            matched_type_name = inferred_ty[1]
    # Single pass through cases to gather flags
    has_null = has_ptr = has_catchall = False
    non_catchall_cases = []
    for c in cases:
        if c[1] is None:
            has_catchall = True
        else:
            non_catchall_cases.append(c)
            if c[1][0] == 'T:prim' and c[1][1] == 'null':
                has_null = True
            elif c[1][0] == 'T:ptr':
                has_ptr = True

    val_ty = strip_const(infer_expr_type(val_node))
    is_nullable_ptr = bool(val_ty and val_ty[0] == 'T:ptr' and len(val_ty) > 2 and val_ty[2])
    is_enum_match = non_catchall_cases and all(
        c[1][0] == 'T:alias' and '::' in c[1][1]
        for c in non_catchall_cases
    )
    if matched_type_name is None and not (has_null and has_ptr) and not (is_nullable_ptr and has_ptr) and not is_enum_match:
        if val_node[0] == 'id':
            CTX.warn(f"match on '{val_node[1]}': cannot determine tagged union type, using position-based case matching")
        else:
            CTX.warn("match on complex expression: cannot determine tagged union type, using position-based case matching")
    if matched_type_name and not has_catchall and not (has_null and has_ptr):
        variants = CTX.tagged.get(matched_type_name, [])
        case_types = [c[1] for c in cases if c[1] is not None]
        missing = []
        for v in variants:
            found = any(tagged_case_matches(v, ct) for ct in case_types)
            if not found:
                if v[0] == 'T:alias':
                    missing.append(v[1])
                elif v[0] == 'T:prim':
                    missing.append(v[1])
                elif v[0] == 'T:err':
                    missing.append(f"!{v[1][1] if len(v) > 1 else 'void'}")
                elif v[0] == 'T:nomem':
                    missing.append('nomem')
                else:
                    missing.append(str(v))
        if missing:
            CTX.error(f"non-exhaustive match on '{matched_type_name}': missing cases for {', '.join(missing)}")
    if (has_null or has_catchall) and has_ptr and is_nullable_ptr:
        null_c = next(
            (c for c in cases if c[1] and c[1][0] == 'T:prim' and c[1][1] == 'null'), None)
        if null_c is None:
            null_c = next((c for c in cases if c[1] is None), None)
        ptr_c = next((c for c in cases if c[1] and c[1][0] == 'T:ptr'), None)
        matched_id = val_node[1] if val_node[0] == 'id' else None
        ret_t = g(CTX.expected_type) if CTX.expected_type else (
            g(CTX.ret_type) if CTX.ret_type else 'intptr_t')
        if ret_t == 'void':
            ret_t = 'int'
        lines = ['(__extension__ ({', f'    __auto_type __m = ({val});',
                 f'    {ret_t} __attribute__((unused)) __r = {{0}};']
        if null_c:
            lines.append(f'    if (__m == NULL) {{ {g_match_body(null_c[3])} }}')
        if ptr_c:
            lines.append('    else {')
            old_match = bind_var(matched_id, ptr_c[1]) if matched_id else None
            if ptr_c[2]:
                old = bind_var(ptr_c[2], ptr_c[1])
                lines.append(f'        {g(ptr_c[1])} __attribute__((unused)) {ptr_c[2]} = __m;')
                lines.append(f'        {g_match_body(ptr_c[3])}')
                restore_var(ptr_c[2], old)
            else:
                # Check if nullable pointer matched without let binding
                if matched_id:
                    # Check if body uses the matched variable
                    if _body_uses_nullable(ptr_c[3], matched_id, ptr_c[1]):
                        CTX.error(f"cannot use nullable pointer '{matched_id}' without let binding in match case (hint: use 'case let val: {g(ptr_c[1])}' instead of 'case {g(ptr_c[1])}')")

                lines.append(f'        {g_match_body(ptr_c[3])}')
            if matched_id:
                restore_var(matched_id, old_match)
            lines.append('    }')
        lines.extend(['    __r;' if CTX.result_used else '    (void)0;', '}))'])
        return '\n'.join(lines)
    ret_t, tagged = _result_type_info()
    if is_enum_match:
        lines = ['(__extension__ ({', f'    __auto_type __m = ({val});',
                 f'    {ret_t} __attribute__((unused)) __r = {{0}};', '    switch (__m) {']
        for c in cases:
            ty, bind, body = c[1], c[2], c[3]
            if ty is None:
                lines.append('    default: {')
                lines.append(f'        {g_match_body(body, tagged, ty)}')
                lines.append('    } break;')
            else:
                enum_variant = mangle_name(ty[1])
                lines.append(f'    case {enum_variant}: {{')
                lines.append(f'        {g_match_body(body, tagged, ty)}')
                lines.append('    } break;')
        lines.extend(['    }', '    __r;' if CTX.result_used else '    (void)0;', '}))'])
        return '\n'.join(lines)
    lines = ['(__extension__ ({', f'    __auto_type __m = ({val});',
             f'    {ret_t} __attribute__((unused)) __r = {{0}};', '    switch (__m.tag) {']
    for i, c in enumerate(cases):
        ty, bind, body = c[1], c[2], c[3]
        if ty is None:
            lines.append('    default: {')
            lines.append(f'        {g_match_body(body, tagged, ty)}')
            lines.append('    } break;')
        else:
            actual_idx = -1
            matched_variant = None
            if matched_type_name:
                actual_idx, matched_variant = find_tagged_variant(matched_type_name, ty)
            if actual_idx < 0:
                actual_idx = i  # Fallback to position in match if type not found
            variant = matched_variant or ty
            tag = tag_name(variant)
            is_err = variant[0] in ('T:err', 'T:nomem') or (
                variant[0] == 'T:alias' and CTX.types.get(variant[1], (None,))[0] in ('T:err', 'T:nomem'))
            tag_val = f'HARE_ERROR_TAG_BASE + {actual_idx}U' if is_err else f'{actual_idx}U'
            lines.append(f'    case {tag_val}: /* {tag} */ {{')
            if bind and not is_void(variant):
                old = bind_var(bind, ty)
                lines.append(f'        {g(ty)} __attribute__((unused)) {bind} = __m.value._{tag};')
                lines.append(f'        {g_match_body(body, tagged, ty)}')
                restore_var(bind, old)
            else:
                lines.append(f'        {g_match_body(body, tagged, ty)}')
            lines.append('    } break;')
    lines.extend(['    }', '    __r;' if CTX.result_used else '    (void)0;', '}))'])
    return '\n'.join(lines)
def _check_switch_exhaustive(val_node, cases):
    has_default = any(c[0] == 'default' for c in cases)
    val_ty = strip_const(infer_expr_type(val_node))
    possible = None
    enum_name = None
    if val_ty and val_ty[0] == 'T:alias' and val_ty[1] in CTX.enums:
        enum_name = val_ty[1]
        possible = list(CTX.enums[enum_name].keys())
    elif val_ty and val_ty[0] == 'T:prim' and val_ty[1] == 'bool':
        possible = [True, False]
    if possible is None:
        if not has_default:
            if val_ty and val_ty[0] == 'T:prim':
                CTX.error(f"non-exhaustive switch on '{val_ty[1]}': missing default case")
            elif val_ty and val_ty[0] == 'T:alias':
                CTX.error(f"non-exhaustive switch on '{val_ty[1]}': missing default case")
            else:
                CTX.error("non-exhaustive switch: missing default case")
        return
    # Use set comprehensions for O(1) lookups
    seen = {member for c in cases if c[0] == 'case' for v in c[1]
            if enum_name and v[0] == 'id' and '::' in v[1]
            for enum_part, member in [v[1].split('::', 1)] if enum_part == enum_name} | \
           {v[1] for c in cases if c[0] == 'case' for v in c[1]
            if v[0] == 'lit' and v[2] == 'bool'}
    seen_vals = {v[1] for c in cases if c[0] == 'case' for v in c[1]
                 if v[0] == 'lit' and isinstance(v[1], int)}
    if enum_name:
        for member, val in CTX.enums[enum_name].items():
            if val in seen_vals:
                seen.add(member)
    elif val_ty and val_ty[0] == 'T:prim' and val_ty[1] == 'bool':
        for v in seen_vals:
            if v in (0, 1):
                seen.add(bool(v))
    missing = [m for m in possible if m not in seen]
    if missing and not has_default:
        if enum_name:
            CTX.error(f"non-exhaustive switch on '{enum_name}': missing cases for {', '.join(missing)}")
        else:
            CTX.error("non-exhaustive switch on 'bool': missing true/false cases")
def g_switch(n):
    val_node, cases = n[1], n[2]
    val = g(val_node)
    _check_switch_exhaustive(val_node, cases)
    ret_t, tagged = _result_type_info()
    is_str_switch = is_str_expr(val_node)
    if is_str_switch:
        lines = ['(__extension__ ({', f'    {ret_t} __attribute__((unused)) __r = {{0}};',
                 f'    hare_str __sw = {val};']
        first = True
        for c in cases:
            if c[0] == 'default':
                lines.append(f'    {"else " if not first else ""}{{')
                lines.append(f'        {g_match_body(c[2], tagged)}')
                lines.append('    }')
            else:
                conds = ' || '.join(f'rt_strcmp(__sw, {g(v)})' for v in c[1])
                lines.append(
                    f'    {"else " if not first else ""}if ({conds}) {{')
                lines.append(f'        {g_match_body(c[2], tagged)}')
                lines.append('    }')
                first = False
        lines.extend(['    __r;' if CTX.result_used else '    (void)0;', '}))'])
        return '\n'.join(lines)
    lines = ['(__extension__ ({', f'    {ret_t} __attribute__((unused)) __r = {{0}};', f'    switch ({val}) {{']
    for c in cases:
        if c[0] == 'default':
            lines.extend(
                ['    default:', '    {', f'        {g_match_body(c[2], tagged)}', '    } break;'])
        else:
            for v in c[1]:
                lines.append(f'    case {g(v)}:')
            lines.extend(
                ['    {', f'        {g_match_body(c[2], tagged)}', '    } break;'])
    lines.extend(['    }', '    __r;' if CTX.result_used else '    (void)0;', '}))'])
    return '\n'.join(lines)
def g_delete(n):
    t, st = n[1], n[2]
    fn = 'rt_static_delete' if st else 'rt_delete'
    if t[0] == 'idx':
        return f'{fn}(&{g(t[1])},{g(t[2])},{g(t[2])}+1)'
    if t[0] == 'slice':
        return f'{fn}(&{g(t[1])},{g(t[2]) or "0"},{g(t[3]) or f"HARE_ARRAY_LEN({g(t[1])})"})'
    return '/*delete err*/'
def g_asgn(n):
    tgt, op, val = n[1], n[2], n[3]
    ln = n[4] if len(n) > 4 else 0
    old_line = CTX.current_line
    if ln:
        CTX.current_line = ln
    if op == '=':
        target_ty = CTX.vars.get(tgt[1]) if tgt[0] == 'id' else infer_expr_type(tgt)
        target_desc = f" '{tgt[1]}'" if tgt[0] == 'id' else ''
        if is_strings_dup_call(val) and target_ty and not is_tagged_union_type(target_ty):
            CTX.error("strings::dup() returns error type (str | !void), must unwrap or handle it")
        check_nonnull_assignment(target_desc, target_ty, val)
    CTX.current_line = old_line
    if contains_idx(tgt):
        checks, tgt_expr = g_lvalue_with_checks(tgt)
        checks_str = ' '.join(f'{c};' for c in checks)
        if checks_str:
            return f'{checks_str} {tgt_expr} {op} {g(val)};'
        return f'{tgt_expr} {op} {g(val)};'
    if tgt[0] == 'slice' and op == '=':
        t, s = tgt[1], g(tgt[2]) if tgt[2] else '0'
        is_slice = t[0] == 'id' and t[1] in CTX.vars and CTX.vars[t[1]
                                                                  ] and CTX.vars[t[1]][0] == 'T:slice'
        if val[0] == 'arr_lit':
            def access(
                i): return f'({g(t)}).data[{s}+{i}]' if is_slice else f'({g(t)})[{s}+{i}]'
            return ' '.join(f'{access(i)} = {g(e)};' for i, e in enumerate(val[1]))
        e = g(tgt[3]) if tgt[3] else (
            f'({g(t)}).len' if is_slice else f'HARE_ARRAY_LEN({g(t)})')
        return f'rt_slice_assign({g(t)},{s},{e},{g(val)});'
    if op == '=' and tgt[0] == 'id' and tgt[1] in CTX.vars:
        ty = CTX.vars[tgt[1]]
        val = _strip_addr_for_uarr(val, ty)
        coerced_val = coerce_array_to_slice(val, ty)
        if coerced_val is not None:
            return f'{g(tgt)} {op} {coerced_val};'
    return f'{g(tgt)} {op} {g(val)};'
def g_break_or_continue(n, keyword):
    label = n[1]
    defers = CTX.get_defers_for_break()
    if not defers:
        return f'goto {label}_{keyword};' if label else f'{keyword};'
    cleanup = ' '.join(f'{g(d)};' for d in defers)
    return f'{{ {cleanup} {"goto " + label + "_" + keyword if label else keyword}; }}'
def g_expr_stmt(n):
    old_result_used = CTX.result_used
    CTX.result_used = False
    if is_strings_dup_call(n[1]):
        CTX.error("strings::dup() returns error type (str | !void), must unwrap or handle it")
    result = f'{g(n[1])};'
    CTX.result_used = old_result_used
    return result
def g_for(n):
    init, cond, after, body = n[1], n[2], n[3], n[4]
    attrs = n[5] if len(n) > 5 else []
    CTX.push_loop()
    init_s = g(init).rstrip(';') if init else ''
    cond_s = g(cond) if cond else ''
    after_s = g(after).rstrip(';') if after else ''
    body_s = g(body)
    CTX.pop_loop()
    code = f'for ({init_s}; {cond_s}; {after_s}) {body_s}'
    if 'ivdep' in attrs:
        pragma = '\n'.join([
            '#if defined(__clang__)',
            '#  pragma clang loop vectorize(assume_safety)',
            '#elif defined(__GNUC__)',
            '#  pragma GCC ivdep',
            '#endif',
        ])
        return pragma + '\n' + code
    return code
def _get_element_type(arr_expr):
    ty = strip_const(infer_expr_type(arr_expr))
    if ty and ty[0] == 'T:slice':
        return ty[1]
    if ty and ty[0] == 'T:arr':
        return ty[1]
    return ('T:prim', 'int')
def _iter_info(arr_expr):
    arr_code = g(arr_expr)
    ty = strip_const(infer_expr_type(arr_expr))
    if ty and ty[0] == 'T:arr':
        elem_type = ty[1]
        size = resolve_array_size(ty[2]) or f'HARE_ARRAY_LEN({arr_code})'
        return elem_type, size, f'({arr_code})'
    if ty and ty[0] == 'T:slice':
        return ty[1], f'({arr_code}).len', f'({arr_code}).data'
    return _get_element_type(arr_expr), f'({arr_code}).len', f'({arr_code}).data'
def g_foreach(n):
    name, arr_expr, body = n[1], n[2], n[3]
    elem_type, len_expr, base_expr = _iter_info(arr_expr)
    old_var = bind_var(name, elem_type)
    CTX.push_loop()
    body_code = g(body)
    CTX.pop_loop()
    restore_var(name, old_var)
    type_str = g_type(elem_type)
    idx = f'__{name}_i'
    return f'''for (size_t {idx} = 0; {idx} < {len_expr}; {idx}++) {{ {type_str} {name} = {base_expr}[{idx}]; {body_code} }}'''
def g_foreach_ref(n):
    name, arr_expr, body = n[1], n[2], n[3]
    elem_type, len_expr, base_expr = _iter_info(arr_expr)
    ptr_type = ('T:ptr', elem_type, False)
    old_var = bind_var(name, ptr_type)
    CTX.push_loop()
    body_code = g(body)
    CTX.pop_loop()
    restore_var(name, old_var)
    type_str = g_type(elem_type)
    idx = f'__{name}_i'
    return f'''for (size_t {idx} = 0; {idx} < {len_expr}; {idx}++) {{ {type_str}* {name} = &({base_expr})[{idx}]; {body_code} }}'''
def g_foreach_iter(n):
    name, iter_expr, body = n[1], n[2], n[3]
    iter_type = infer_expr_type(iter_expr)
    elem_type = ('T:prim', 'int')  # Default
    elem_tag = 0
    done_tag = 0
    if iter_type and iter_type[0] == 'T:alias' and iter_type[1] in CTX.tagged:
        variants = CTX.tagged[iter_type[1]]
    elif iter_type and iter_type[0] == 'T:tagged':
        variants = iter_type[1]
    else:
        variants = None
    if variants:
        for i, variant in enumerate(variants):
            if variant == ('T:prim', 'done') or variant == ('T:alias', 'done'):
                done_tag = i
            else:
                elem_type = variant
                elem_tag = i
    old_var = bind_var(name, elem_type)
    CTX.push_loop()
    iter_code = g(iter_expr)
    body_code = g(body)
    CTX.pop_loop()
    restore_var(name, old_var)
    type_str = g_type(elem_type)
    iter_type_str = g_type(iter_type) if iter_type else 'int'
    elem_tag_name = tag_name(elem_type)
    return f'''for (;;) {{ {iter_type_str} __iter_result = {iter_code}; if (__iter_result.tag == {done_tag}) break; {type_str} {name} = __iter_result.value._{elem_tag_name}; {body_code} }}'''
def get_error_result_type(expr_type):
    if not expr_type:
        return None
    if expr_type[0] == 'T:alias' and expr_type[1] in CTX.tagged:
        variants = CTX.tagged[expr_type[1]]
        non_error = [v for v in variants if v[0] not in ('T:err', 'T:nomem') and not (
            v[0] == 'T:alias' and CTX.types.get(v[1], (None,))[0] in ('T:err', 'T:nomem'))]
        if len(non_error) == 1:
            return non_error[0]
        elif len(non_error) > 1:
            for v in non_error:
                if not is_void(v):
                    return v
            return non_error[0]
    return None
def _g_error_check(n, propagate):
    expr = n[1]
    ln = n[2] if len(n) > 2 else 0  # Line number for abort
    # Slice operations (append, insert, delete) in our C implementation either
    # succeed or abort - they don't return error unions, so ! is a no-op
    if expr[0] in ('append', 'insert', 'delete'):
        return g(expr)
    expr_code = g(expr)
    abort_action = f'rt_abort_fixed(&__hare_file,{ln},0,7)'
    def make_error_action(type_name=None):
        if not propagate:
            return abort_action
        ret_type = CTX.ret_type
        if ret_type and ret_type[0] == 'T:alias' and ret_type[1] in CTX.tagged:
            return f'return *({ret_type[1]}*)&__e'
        return 'return __e'
    expr_type = None
    if expr[0] == 'call':
        func = expr[1]
        if func[0] == 'id' and func[1] in CTX.funcs:
            expr_type = CTX.funcs[func[1]].get('ret_type')
    if expr[0] == 'id' and expr[1] in CTX.vars:
        expr_type = CTX.vars[expr[1]]
    if expr[0] in ('alloc', 'alloc_cp', 'alloc_sl'):
        inner = infer_expr_type(expr[1])
        if inner:
            ptr_type = ('T:ptr', inner, False) if expr[0] == 'alloc' else (
                ('T:slice', inner) if inner[0] != 'T:slice' else inner)
            type_name = get_alloc_result_type_name(ptr_type)
            result_tag = tag_name(ptr_type)
            action = make_error_action(type_name)
            return f'({{ {type_name} __e = {expr_code}; if (HARE_IS_ERROR(__e)) {action}; __e.value._{result_tag}; }})'
    if expr_type is None:
        expr_type = infer_expr_type(expr)
    if expr_type and expr_type[0] == 'T:alias' and expr_type[1] in CTX.tagged:
        type_name = expr_type[1]
        result_type = get_error_result_type(expr_type)
        if result_type:
            result_tag = tag_name(result_type)
            action = make_error_action(type_name)
            result_expr = '(void)0' if is_void(result_type) else f'__e.value._{result_tag}'
            return f'({{ {type_name} __e = {expr_code}; if (HARE_IS_ERROR(__e)) {action}; {result_expr}; }})'
    action = abort_action if not propagate else 'return __e'
    result = '__e.value' if propagate else '__e'
    return f'({{ __auto_type __e = ({expr_code}); if (HARE_IS_ERROR(__e)) {action}; {result}; }})'
g_prop = lambda n: _g_error_check(n, propagate=True)
g_unwrap = lambda n: _g_error_check(n, propagate=False)
def g_fn(n):
    name, ps, ret, body, exp, va, attrs = n[1], n[2], n[3], n[4], n[5], n[6], n[7] if len(
        n) > 7 else []
    if 'test' in attrs:
        return f'#ifdef HARE_TEST\n{g_fn_impl(n)}\n#endif'
    return g_fn_impl(n)
def g_use(n):
    module_path, alias = n[1], n[2]
    register_use(n)
    return f'/* use {module_path} as {alias} */'

def register_use(n):
    module_path, alias = n[1], n[2]
    CTX.imports.add(module_path)
    CTX.import_aliases[alias] = module_path
    if module_path == 'strings':
        get_strings_dup_result_type_name()


# --- Declaration Generators ---

def g_fn_signature(name, ps, ret, static=''):
    params = ', '.join(g_param_decl(param) for param in ps) or 'void'
    if ret[0] == 'T:ptr' and ret[1][0] == 'T:arr':
        arr = ret[1]
        dims = []
        while arr[0] == 'T:arr':
            dims.append(str(arr[2]) if arr[2] else '')
            arr = arr[1]
        elem_t = g(arr)
        dims_str = ''.join(f'[{d}]' for d in dims)
        return f'{static}{elem_t} (*{name}({params})){dims_str}'
    if ret[0] == 'T:ptr' and ret[1][0] == 'T:fn':
        fn_type = ret[1]
        fn_ret = g(fn_type[2])
        fn_params = ', '.join(g(t) for _, t in fn_type[1]) or 'void'
        return f'{static}{fn_ret} (*{name}({params}))({fn_params})'
    return f'{static}{g(ret)} {name}({params})'
def g_fn_impl(n):
    name, ps, ret, body, exp, va, attrs = n[1], n[2], n[3], n[4], n[5], n[6], n[7] if len(
        n) > 7 else []
    c_name = get_fn_c_name(name, exp, attrs, ps, ret)
    CTX.funcs[name] = {'params': ps, 'variadic': va,
                       'exported': exp, 'c_name': c_name, 'ret_type': ret}
    CTX.vars.clear()
    CTX.ret_type = ret
    CTX.ret_name = ret[1] if ret[0] == 'T:alias' and ret[1] in CTX.tagged else None
    CTX.current_func = name  # Track for warning/error context
    CTX.current_file = CTX.func_files.get(name)  # Track source file for errors
    for param in ps:
        CTX.vars[param_name(param)] = param_type(param)
    is_main = name == 'main' and exp and not ps and ret == ('T:prim', 'void')
    static = '' if (exp or is_main or get_symbol_attr(attrs)) else 'static '
    sig = g_fn_signature(c_name, ps, ret, static)
    comment = ''
    if any(param_default(param) for param in ps):
        comment += f'/* Defaults: {", ".join(f"{param_name(param)}={g(param_default(param))}" for param in ps if param_default(param))} */\n'
    if va:
        comment += '/* variadic */\n'
    for a in attrs:
        if isinstance(a, tuple):
            comment += f'/* @{a[0]}("{a[1]}") */\n'
        else:
            comment += f'/* @{a} */\n'
    if body[0] == 'block':
        b = g(body)
        if CTX.ret_name and ret[0] == 'T:alias' and ret[1] in CTX.tagged:
            variants = CTX.tagged[ret[1]]
            has_void_primitive = any(v[0] == 'T:prim' and v[1] == 'void' for v in variants)
            if has_void_primitive:
                void_return = f'return {CTX.ret_name}_from_void();'
                if b.rstrip().endswith('}'):
                    b = b.rstrip()[:-1] + f'    {void_return}\n}}'
        elif ret and ret != ('T:prim', 'void') and b.rstrip().endswith('}'):
            b = b.rstrip()[:-1] + '    __builtin_unreachable();\n}'
    else:
        b = '{\n    ' + g(('ret', body)) + '\n}'
    result = f'{comment}{sig} {b}'
    simple_attrs = [a for a in attrs if not isinstance(a, tuple)]
    if 'init' in simple_attrs:
        result += f'\n__attribute__((used, section("hare_init"))) static void (*__hare_init_{c_name})(void) = {c_name};'
    elif 'fini' in simple_attrs:
        result += f'\n__attribute__((used, section("hare_fini"))) static void (*__hare_fini_{c_name})(void) = {c_name};'
    elif 'test' in simple_attrs:
        result += f'\n__attribute__((used, section("hare_test"))) static void (*__hare_test_{c_name})(void) = {c_name};'
    return result
def g_typedef_fwd(n):
    name, ty = n[1], n[2]
    if ty[0] == 'T:struct':
        return f'typedef struct {name} {name};'
    if ty[0] == 'T:union':
        return f'typedef union {name} {name};'
    if ty[0] == 'T:tagged':
        return f'typedef struct {name} {name};'  # Tagged unions are structs in C
    return None  # No forward declaration needed for other types
def g_typedef(n):
    name, ty, exp = n[1], n[2], n[3]
    CTX.register_type(name, ty)
    if ty[0] == 'T:enum':
        members, base = ty[1], ty[2]
        base_type = g(base) if base else 'intptr_t'
        lines = [f'typedef {base_type} {name};']
        for member_name, val in members:
            lines.append(f'#define {name}_{member_name} (({name}){val})')
        return '\n'.join(lines)
    if ty[0] == 'T:struct':
        fields = ty[1]
        field_defs = ' '.join(struct_field_decls(fields))
        attr = ' __attribute__((packed))' if is_packed_struct(ty) else ''
        return f'struct{attr} {name} {{ {field_defs} }};'
    if ty[0] == 'T:union':
        fields = ty[1]
        field_defs = ' '.join(f'{g_decl(ft, fn)};' for fn, ft in fields)
        return f'union {name} {{ {field_defs} }};'
    if ty[0] != 'T:tagged':
        return f'typedef {g(ty)} {name};'
    types, spreads = ty[1], ty[2]
    lines = [f'struct {name} {{', '    uint32_t tag;', '    union {']
    for i, t in enumerate(types):
        tag = tag_name(t)
        lines.append(f'        char _{tag}_m;' if is_void(
            t) else f'        {g(t)} _{tag};{" /* spread */" if spreads[i] else ""}')
    lines.extend(['    } value;', '};'])
    for i, t in enumerate(types):
        tag = tag_name(t)
        base = 'HARE_ERROR_TAG_BASE + ' if t[0] in ('T:err', 'T:nomem') or (
            t[0] == 'T:alias' and CTX.types.get(t[1], (None,))[0] in ('T:err', 'T:nomem')) else ''
        lines.append(f'#define {name}_TAG_{tag} ({base}{i}U)')
        if is_void(t):
            lines.append(
                f'static inline {name} {name}_from_{tag}(void) {{ {name} __r; __r.tag = {base}{i}U; return __r; }}')
        else:
            lines.append(
                f'static inline {name} {name}_from_{tag}({g(t)} __v) {{ {name} __r; __r.tag = {base}{i}U; __r.value._{tag} = __v; return __r; }}')
    return '\n'.join(lines)
def g_slet(n):
    name, ty, init, mut = n[1], n[2], n[3], n[4]
    ln = n[5] if len(n) > 5 else 0
    old_line = CTX.current_line
    if ln:
        CTX.current_line = ln
    if ty:
        CTX.vars[name] = ty
    elif init:
        inferred = infer_expr_type(init)
        if inferred:
            CTX.vars[name] = inferred
    check_nonnull_assignment(f" '{name}'", ty, init)
    CTX.current_line = old_line
    # For static variables, we can't use __auto_type with initializer lists
    # Infer the type for common cases
    if ty:
        decl = g_decl(ty, name)
    elif init and init[0] == 'lit' and init[2] == 'str':
        decl = f'hare_str {name}'
    else:
        inferred = infer_expr_type(init) if init else None
        if inferred:
            decl = g_decl(inferred, name)
        else:
            decl = f"__auto_type {name}"
    if init:
        CTX.in_static_init = True
        init_code = g(init)
        CTX.in_static_init = False
        return f'static {"" if mut else "const "}{decl} = {init_code};'
    else:
        return f'static {"" if mut else "const "}{decl};'
def g_global(n):
    name, ty, init, exported, mut = n[1], n[2], n[3], n[4], n[5]
    check_nonnull_assignment(f" '{name}'", ty, init)
    # Validate array size inference before processing
    ty = validate_array_size_inference(ty, init, name)
    if ty:
        CTX.vars[name] = ty
    elif init:
        inferred = infer_expr_type(init)
        if inferred:
            ty = inferred
            CTX.vars[name] = inferred
    prefix = "" if exported else "static "
    const = "" if mut else "const "
    if not ty:
        CTX.error(f"cannot infer type for global '{name}'")
        ty = ('T:prim', 'int')
    decl = g_decl(ty, name)
    if init:
        # Set target array size for arr_lit expansion
        if ty and ty[0] == 'T:arr' and isinstance(ty[2], int):
            CTX.arr_lit_target_size = ty[2]
        else:
            CTX.arr_lit_target_size = None

        CTX.in_static_init = True
        init_code = g(init)
        CTX.in_static_init = False
        CTX.arr_lit_target_size = None
        return f'{prefix}{const}{decl} = {init_code};'
    else:
        return f'{prefix}{const}{decl};'
def g_insert_expr(n):
    if n[1][0] != 'idx':
        return '/*insert err*/'
    if n[4]:  # static insert
        return f'rt_static_insert(&{g(n[1][1])},{g(n[1][2])},{g(n[2])},0)'
    else:
        return f'rt_insert(&{g(n[1][1])},{g(n[1][2])},{g(n[2])})'
def g_assert_builtin(n):
    ln = n[3] if len(n) > 3 else 0
    if n[2]:  # has message
        return f'do {{ if (!({g(n[1])})) rt_abort(&__hare_file,{ln},0,({g(n[2])})); }} while(0)'
    else:
        return f'do {{ if (!({g(n[1])})) rt_abort_fixed(&__hare_file,{ln},0,6); }} while(0)'

def _expr_is_zero_like(n):
    if not n:
        return False
    if n[0] == 'lit':
        v, hint = n[1], n[2]
        if hint == 'null':
            return True
        if isinstance(v, bool):
            return v is False
        if isinstance(v, int):
            return v == 0
        if isinstance(v, float):
            return v == 0.0
        return False
    if n[0] == 'un' and len(n) > 2 and n[1] in ('+', '-'):
        return _expr_is_zero_like(n[2])
    if n[0] == 'cast':
        return _expr_is_zero_like(n[1])
    if n[0] == 'arr_lit':
        elems, fill = n[1], n[2]
        if fill is not None and not _expr_is_zero_like(fill):
            return False
        if not elems:
            return fill is not None and _expr_is_zero_like(fill)
        return all(_expr_is_zero_like(e) for e in elems)
    if n[0] == 'struct_lit':
        for _, fv, _ in n[2]:
            if not _expr_is_zero_like(fv):
                return False
        return True
    if n[0] == 'tuple_lit':
        return all(_expr_is_zero_like(e) for e in n[1])
    return False

def g_arr_lit(n):
    """Generate array literal with fill expansion support"""
    elems, fill = n[1], n[2]

    def _gen_elem(elem):
        prev_target = getattr(CTX, 'arr_lit_target_size', None)
        CTX.arr_lit_target_size = None
        out = g(elem)
        CTX.arr_lit_target_size = prev_target
        return out

    if fill is not None:
        if _expr_is_zero_like(fill):
            if elems:
                return f'{{ {", ".join(_gen_elem(e) for e in elems)} }}'
            return '{0}'
        # Need to expand fill value
        # Try to get target array size from context
        target_size = getattr(CTX, 'arr_lit_target_size', None)

        if target_size is not None:
            # Expand to target size
            expanded = list(elems)
            fill_count = target_size - len(elems)
            if fill_count > 0:
                # Generate fill elements
                expanded.extend([fill] * fill_count)
            return f'{{ {", ".join(_gen_elem(e) for e in expanded)} }}'
        else:
            # No target size available, just output what we have
            # This shouldn't happen if validation is working
            if elems:
                return f'{{ {", ".join(_gen_elem(e) for e in elems)} }}'
            else:
                # Fill-only without size - output single fill value
                # C will use it to initialize the array
                return f'{{{_gen_elem(fill)}}}'
    else:
        # No fill - just output elements
        return f'{{ {", ".join(_gen_elem(e) for e in elems)} }}' if elems else '{0}'


# --- Generator Dispatch Table ---
ABORT_HARE_STR = "(hare_str){.data=(uint8_t*)\"abort\",.len=5}"
GENERATORS = {
    'T:prim': g_type, 'T:ptr': g_type, 'T:slice': g_type, 'T:arr': g_type,
    'T:uarr': g_type, 'T:struct': g_type, 'T:union': g_type, 'T:enum': g_type,
    'T:tuple': g_type, 'T:tagged': g_type, 'T:err': g_type, 'T:alias': g_type,
    'T:fn': g_type, 'T:nomem': g_type, 'T:const': g_type,
    'lit': g_lit,
    'id': g_id,
    'bin': g_bin,
    'un': g_un,
    'call': g_call,
    'spread': lambda n: g(n[1]),
    'idx': g_idx,
    'slice': g_slice,
    'fld': g_fld,
    'cast': g_cast,
    'is': g_is,
    'if': g_if,
    'block': g_block,
    'arr_lit': g_arr_lit,
    'struct_lit': g_struct_lit,
    'tuple_lit': g_tuple_lit,
    'match': g_match,
    'switch': g_switch,
    'len': g_len,
    'size': lambda n: g_sizeof_type(n[1]),
    'alloc': g_alloc_expr,
    'alloc_cp': g_alloc_cp_expr,
    'alloc_sl': g_alloc_sl_expr,
    'free': g_free,
    'append': lambda n: f'rt_static_append(&{g(n[1])},{g(n[2])},0)' if n[4] else f'rt_append(&{g(n[1])},{g(n[2])})',
    'insert': g_insert_expr,
    'delete': g_delete,
    'assert_b': g_assert_builtin,
    'abort': lambda n: f'rt_abort(&__hare_file,{n[2] if len(n) > 2 else 0},0,{g(n[1]) if n[1] else ABORT_HARE_STR})',
    'prop': g_prop,
    'unwrap': g_unwrap,
    'asgn_e': lambda n: f'({g(n[1])} {n[2]} {g(n[3])})',
    'yield': lambda n: f'__r = {g(n[1])};',
    'let': g_let,
    'slet': g_slet,
    'mlet': lambda n: '\n'.join(g(('let', nm, ty, ini, n[2])) for nm, ty, ini in n[1]),
    'asgn': g_asgn,
    'ret': g_ret,
    'break': lambda n: g_break_or_continue(n, 'break'), 'cont': lambda n: g_break_or_continue(n, 'continue'),
    'defer': lambda n: '',
    'expr': g_expr_stmt,
    'for': g_for,
    'foreach': g_foreach,
    'foreach_ref': g_foreach_ref,
    'foreach_iter': g_foreach_iter,
    'fn': g_fn,
    'typedef': g_typedef,
    'global': g_global,
    'def': lambda n: f'#define {n[1]} ' + (f'(({g(n[2])}){g(n[3])})' if n[2] else g(n[3])),
    'use': g_use,
}
def g(n):
    if n is None:
        return ''
    if isinstance(n, str):
        return n
    gen = GENERATORS.get(n[0])
    if gen:
        return gen(n)
    return f'/* unknown: {n[0]} */'
def g_fn_decl(n):
    name, ps, ret, _, exp, va, attrs = n[1], n[2], n[3], n[4], n[5], n[6], n[7] if len(
        n) > 7 else []
    c_name = get_fn_c_name(name, exp, attrs, ps, ret)
    static = '' if (exp or name == 'main' or get_symbol_attr(attrs)) else 'static '
    simple_attrs = [a for a in attrs if not isinstance(a, tuple)]
    if 'test' in simple_attrs:
        sig = g_fn_signature(c_name, ps, ret, 'static ')
        return f'#ifdef HARE_TEST\n{sig};\n#endif'
    return f'{g_fn_signature(c_name, ps, ret, static)};'
def check_warnings_errors():
    import sys
    for w in CTX.warnings:
        print(w, file=sys.stderr)
    for e in CTX.errors:
        print(e, file=sys.stderr)
    if CTX.errors:
        raise RuntimeError(f"Transpilation failed with {len(CTX.errors)} error(s)")
def _generate_output(ast):
    for d in ast:
        if d[0] == 'typedef':
            CTX.register_type(d[1], d[2])
        elif d[0] == 'fn':
            CTX.funcs[d[1]] = {'params': d[2], 'variadic': d[6], 'exported': d[5],
                               'c_name': get_fn_c_name(d[1], d[5], d[7] if len(d) > 7 else [], d[2], d[3]),
                               'ret_type': d[3]}
        elif d[0] == 'def':
            CTX.defs[d[1]] = d[3]
        elif d[0] == 'global':
            CTX.global_vars.add(d[1])
            if d[2]:
                CTX.global_types[d[1]] = d[2]
            elif d[3]:
                inferred = infer_expr_type(d[3])
                if inferred:
                    CTX.global_types[d[1]] = inferred
        elif d[0] == 'use':
            register_use(d)
    synth, counter = [], [0]
    def synth_tagged(ty):
        if ty[0] == 'T:tagged':
            name = f'__hare_tagged_{counter[0]}'
            counter[0] += 1
            CTX.register_type(name, ty)
            synth.append(('typedef', name, ty, False))
            return ('T:alias', name)
        return ty
    new_ast = [(('fn', d[1], d[2], synth_tagged(d[3]), d[4], d[5], d[6],
                d[7] if len(d) > 7 else []) if d[0] == 'fn' else d) for d in ast]
    defs = []              # #define from def declarations
    typedef_simple = []    # Enums, simple type aliases (must come before struct bodies)
    typedef_slice_alias = []  # Aliases to slice types (must come after slice typedefs)
    typedef_fwd = []       # Forward declarations (struct/union/tagged)
    typedef_body = []      # Complete struct/union definitions
    typedef_tagged = []    # Tagged union definitions (with constructors)
    fn_decls = []          # Function forward declarations
    fn_impls = []          # Function implementations
    globs = []             # Global variables
    imports = []           # Use statements
    all_typedefs = [d for d in new_ast if d[0] == 'typedef']
    sorted_typedefs = topo_sort_typedefs(all_typedefs)
    for d in sorted_typedefs:
        fwd = g_typedef_fwd(d)
        if fwd:
            typedef_fwd.append(fwd)
    for d in sorted_typedefs:
        ty = d[2]
        if ty[0] == 'T:enum':
            typedef_simple.append(g_typedef(d))
        elif ty[0] in ('T:struct', 'T:union'):
            typedef_body.append(g_typedef(d))
        elif ty[0] == 'T:tagged':
            typedef_tagged.append(g_typedef(d))
        else:  # Simple alias (e.g., type token_kind = ...)
            if ty[0] == 'T:slice':
                typedef_slice_alias.append(g_typedef(d))
            else:
                typedef_simple.append(g_typedef(d))
    for d in new_ast:
        if d[0] == 'fn':
            fn_decls.append(g_fn_decl(d))
            fn_impls.append(g(d))
        elif d[0] == 'def':
            defs.append(g(d))
        elif d[0] == 'global':
            globs.append(g(d))
        elif d[0] == 'use':
            imports.append(g(d))
    for d in synth:
        fwd = g_typedef_fwd(d)
        if fwd:
            typedef_fwd.append(fwd)
        typedef_tagged.append(g_typedef(d))
    simple_slice_tds = [f'HARE_DEFINE_SLICE({elem_t}, hare_slice_{name});'
                        for name, elem_t in CTX.needed_slice_types if name != 'uint8_t']
    slice_tds = [f'typedef struct {{ {g(inner)} (*data)[{sz}]; size_t len; size_t cap; }} {name};'
                 for name, (inner, sz) in CTX.slice_typedefs.items()]
    tuple_tds = [f'typedef struct {{ {" ".join(f"{g(t)} _{i};" for i, t in enumerate(elem_types))} }} {name};'
                 for _, (name, elem_types) in CTX.needed_tuple_types.items()]
    alloc_fwd_decls = [f'typedef struct {name} {name};'
                       for name in getattr(CTX, 'alloc_result_types', {}).values()]
    alloc_types = [g_typedef(('typedef', name, CTX.types[name], False))
                   for name in getattr(CTX, 'alloc_result_types', {}).values()]
    strings_dup_type = getattr(CTX, 'strings_dup_result_type', None)
    strings_tagged = [g_typedef(('typedef', strings_dup_type, CTX.types[strings_dup_type], False))
                      ] if strings_dup_type else []
    parts = [make_prelude(CTX.source_file)]
    if 'rt' in CTX.imports:
        parts.append(RT_DECLS)
    if 'strings' in CTX.imports:
        parts.append(STRINGS_DECLS)
    if imports:
        parts.append('\n/* Imports */\n' + '\n'.join(imports))
    if defs:
        parts.append('\n/* Constants */\n' + '\n'.join(defs))
    if typedef_simple:
        parts.append('\n/* Type aliases and enums */\n' + '\n'.join(typedef_simple))
    all_fwd_decls = typedef_fwd + alloc_fwd_decls
    if all_fwd_decls:
        parts.append('\n/* Type forward declarations */\n' + '\n'.join(all_fwd_decls))
    if simple_slice_tds:
        parts.append('\n/* Slice types */\n' + '\n'.join(simple_slice_tds))
    if tuple_tds:
        parts.append('\n/* Tuple types */\n' + '\n'.join(tuple_tds))
    if slice_tds:
        parts.append('\n/* Slice-of-array types */\n' + '\n'.join(slice_tds))
    if typedef_slice_alias:
        parts.append('\n/* Slice aliases */\n' + '\n'.join(typedef_slice_alias))
    if typedef_body:
        parts.append('\n/* Struct/union definitions */\n' + '\n'.join(typedef_body))
    all_tagged = typedef_tagged + alloc_types + strings_tagged
    if all_tagged:
        parts.append('\n/* Tagged union definitions */\n' + '\n'.join(all_tagged))
    if fn_decls:
        parts.append('\n/* Forward declarations */\n' + '\n'.join(fn_decls))
    if globs:
        parts.append('\n/* Globals */\n' + '\n'.join(globs))
    if fn_impls:
        parts.append('\n/* Functions */\n' + '\n\n'.join(fn_impls))
    check_warnings_errors()
    return '\n'.join(parts) + '\n'


# ============================================================================
# MAIN ENTRY POINTS - Public API
# ============================================================================

def transpile(src, package=None, filename="<string>"):
    global CTX
    CTX = Ctx()
    CTX.package = package
    CTX.source_file = filename
    return _generate_output(p_unit(P(tokenize(src))))
def transpile_files(files, package=None):
    global CTX
    CTX = Ctx()
    CTX.package = package
    CTX.source_file = files[0] if files else "<stdin>"
    all_ast = []
    for f in files:
        with open(f) as fp:
            file_ast = p_unit(P(tokenize(fp.read())))
            for decl in file_ast:
                if decl[0] == 'fn':
                    CTX.func_files[decl[1]] = f
            all_ast.extend(file_ast)
    return _generate_output(all_ast)
if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Hare to C11 transpiler')
    parser.add_argument('files', nargs='+', help='Input .ha files')
    parser.add_argument('-o', '--output', help='Output .c file')
    parser.add_argument('-N', '-p', '--namespace',
                        help='Package name for symbol prefixing')
    args = parser.parse_args()
    out = transpile_files(args.files, args.namespace)
    if args.output:
        with open(args.output, 'w') as f:
            f.write(out)
        print(f"Transpiled {len(args.files)} file(s) -> {args.output}")
    else:
        print(out)
