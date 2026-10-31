#!/usr/bin/env python3
"""rezc.py -- an independent compiler for Apple's MPW Rez language, extended
to build the resource fork of a Macintosh ROM.

Based on the Rez compiler written for the Photoshop 1.0.1 port
(photoshop/tools/rez/rezc.py); this copy adds what the Mac ROM build needs.

Usage:
    python3 tools/rez/rezc.py [options] file.r...

    --rsrc FILE        write the resources as a resource fork (the standard
                       format of Inside Macintosh I-128)
    --rom-asm FILE     write the ROM resource fork described by the 'rrhd' and
                       'rrsc' resources of the sources (see RomTypes.r) as GNU
                       as source: the resource map, the order and relative
                       handles of the resources, and the data of the resources
                       compiled from Rez (include/romrsrc.inc has the macros)
    --cpp FILE         C++ byte arrays (the output of the Photoshop port)
    --rom-image FILE   add the resources of a Plus/SE ROM image (its resource
                       map and headers), e.g. to --list them or to write them
                       as a resource fork with --rsrc
    --list             print a summary of all resources
    --hexdump 'TYPE'=ID
                       print the data of one resource
    -d NAME[=VALUE]    define a preprocessor macro
    -u NAME            undefine one of the default macros
    -i DIR             directory to search for #include files
    -s DIR             directory to search for read/include files
    --types FILE       template file read first (repeatable; default: Types.r
                       and RomTypes.r next to this script)
    --lenient          skip resource statements whose type has no template
                       (to compile parts of other people's .r files)
    -v                 report the number of resources and warnings

Like MPW's Rez, all input files are processed in one invocation and share a
single set of #define macros and resource type declarations. The templates
in Types.r and RomTypes.r (next to this script) are read first.

Supported language:
  * preprocessor: #define NAME tokens (with backslash line continuation),
    #undef, #if/#elif/#else/#endif, #ifdef/#ifndef, defined(NAME),
    #include "file"; /* */ and // comments. Source files may be UTF-8 or
    Mac Roman with CR, LF or CRLF line ends (MPW files are Mac Roman/CR).
  * resource 'TYPE' (id [, "name"] [, attributes]) { ... };
  * data 'TYPE' (id [, "name"] [, attributes]) { $"..." "..." };
  * read 'TYPE' (id [, "name"] [, attributes]) "file";
  * include "file" [ 'TYPE' [ (id) ] ];   (resources of a resource fork file)
  * type 'TYPE' { ... };  and  type 'TYPE' as 'TYPE2';
    with integer/longint/byte/bitstring[n]/boolean/char, unsigned and radix
    modifiers, string/pstring/wstring/cstring [n] (also hex string), point,
    rect, fill/align, (wide) array [label] [count], switch/case/key,
    symbolic constants and constant fields (= expression with $$CountOf)
  * not supported: label arithmetic and $$Word/$$BitField/... (Apple's
    FONT and PixMap templates use them), change/delete statements.

Errors are reported as "file:line: error: ..." and make the compiler exit
with status 1; unsupported but ignorable constructs produce warnings.
"""

import argparse
import os
import re
import sys

# Macros defined before the sources are read (the Photoshop port defined its
# build switches here).
DEFAULT_DEFINES = []

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
TYPES_FILES = [os.path.join(TOOL_DIR, 'Types.r'), os.path.join(TOOL_DIR, 'RomTypes.r')]

# ---------------------------------------------------------------------------
# Diagnostics


class RezError(Exception):
    def __init__(self, msg, where=None):
        super().__init__(msg)
        self.msg = msg
        self.where = where

    def __str__(self):
        loc = _where(self.where)
        return f'{loc}: error: {self.msg}' if loc else f'error: {self.msg}'


def _where(w):
    if w is None:
        return ''
    if isinstance(w, Tok):
        return f'{w.file}:{w.line}'
    if isinstance(w, tuple):
        return f'{w[0]}:{w[1]}'
    return str(w)


_warning_count = 0


def warn(msg, where=None):
    global _warning_count
    _warning_count += 1
    loc = _where(where)
    print(f'{loc}: warning: {msg}' if loc else f'warning: {msg}', file=sys.stderr)


# ---------------------------------------------------------------------------
# Mac Roman (identical to the table in src/mac/MacTypes.cpp)

MAC_ROMAN_HIGH = [
    0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1, 0x00E0, 0x00E2, 0x00E4, 0x00E3,
    0x00E5, 0x00E7, 0x00E9, 0x00E8, 0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,
    0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC, 0x2020, 0x00B0, 0x00A2, 0x00A3,
    0x00A7, 0x2022, 0x00B6, 0x00DF, 0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
    0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211, 0x220F, 0x03C0, 0x222B, 0x00AA,
    0x00BA, 0x03A9, 0x00E6, 0x00F8, 0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,
    0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153, 0x2013, 0x2014, 0x201C, 0x201D,
    0x2018, 0x2019, 0x00F7, 0x25CA, 0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1, 0x00CB, 0x00C8, 0x00CD, 0x00CE,
    0x00CF, 0x00CC, 0x00D3, 0x00D4, 0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,
    0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7]
assert len(MAC_ROMAN_HIGH) == 128

UNICODE_TO_MAC = {cp: 0x80 + i for i, cp in enumerate(MAC_ROMAN_HIGH)}
UNICODE_TO_MAC[0x00A4] = 0xDB      # currency sign (pre Mac OS 8.5 meaning of 0xDB)
UNICODE_TO_MAC[0x2126] = 0xBD      # ohm sign -> Omega
UNICODE_TO_MAC[0x2206] = 0xC6      # increment


def mac_roman_to_utf8(data):
    return ''.join(chr(b) if b < 0x80 else chr(MAC_ROMAN_HIGH[b - 0x80]) for b in data)


def char_to_mac_roman(ch, where):
    cp = ord(ch)
    if cp < 0x80:
        return cp
    b = UNICODE_TO_MAC.get(cp)
    if b is None:
        raise RezError(f'character {ch!r} (U+{cp:04X}) has no Mac Roman equivalent', where)
    return b


# ---------------------------------------------------------------------------
# Lexer


class Tok:
    __slots__ = ('kind', 'value', 'file', 'line', 'bol')

    # kinds: ident, num (int), str (bytes), hex (bytes), lit (bytes),
    #        func (name after $$), punct (str), hash, nl, eof

    def __init__(self, kind, value, file, line, bol=False):
        self.kind = kind
        self.value = value
        self.file = file
        self.line = line
        self.bol = bol

    def describe(self):
        k = self.kind
        if k == 'eof':
            return 'end of file'
        if k == 'ident':
            return f'"{self.value}"'
        if k == 'punct':
            return f"'{self.value}'"
        if k == 'num':
            return f'number {self.value}'
        if k in ('str', 'hex'):
            return 'string'
        if k == 'lit':
            return f"literal '{mac_roman_to_utf8(self.value)}'"
        if k == 'func':
            return f'$${self.value}'
        return k

    def __repr__(self):
        return f'Tok({self.kind}, {self.value!r}, {self.file}:{self.line})'


_TOKEN_RE = re.compile(r'''
    (?P<cont>\\[ \t\r\f\v]*\n)
  | (?P<ws>[ \t\r\f\v]+)
  | (?P<nl>\n)
  | (?P<bcomment>/\*.*?\*/)
  | (?P<lcomment>//[^\n]*)
  | (?P<hex>\$"[^"]*")
  | (?P<str>"(?:[^"\\\n]|\\.)*")
  | (?P<lit>'(?:[^'\\\n]|\\.)*')
  | (?P<func>\$\$[A-Za-z_][A-Za-z0-9_]*)
  | (?P<num>\$[0-9A-Fa-f]+|0[xX][0-9A-Fa-f]+|0[bB][01]+|[0-9]+)
  | (?P<ident>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct><<|>>|<=|>=|==|!=|&&|\|\||[{}()\[\],;:=+\-*/%&|^~!<>])
  | (?P<hash>\#)
''', re.VERBOSE | re.DOTALL)

# Rez follows the MPW C convention: \n is a Macintosh return (0x0D) and \r a
# line feed (0x0A).
_SIMPLE_ESCAPES = {'t': 0x09, 'b': 0x08, 'r': 0x0A, 'n': 0x0D, 'f': 0x0C, 'v': 0x0B,
                   '?': 0x7F, '\\': 0x5C, "'": 0x27, '"': 0x22}


def decode_string(raw, where):
    """Decodes the text between the quotes of a Rez string or literal
    (escape sequences, Unicode -> Mac Roman) into bytes."""
    out = bytearray()
    i = 0
    n = len(raw)
    while i < n:
        c = raw[i]
        if c != '\\':
            out.append(char_to_mac_roman(c, where))
            i += 1
            continue
        if i + 1 >= n:
            raise RezError('backslash at end of string', where)
        e = raw[i + 1]
        two = raw[i + 1:i + 3].lower()
        if two == '0x':                                  # \0xHH
            digits = raw[i + 3:i + 5]
            if not re.fullmatch(r'[0-9A-Fa-f]{2}', digits):
                raise RezError(f'invalid hex escape "\\{raw[i + 1:i + 5]}"', where)
            out.append(int(digits, 16))
            i += 5
        elif two == '0d' and re.fullmatch(r'[0-9]{3}', raw[i + 3:i + 6] or ''):   # \0dDDD
            v = int(raw[i + 3:i + 6], 10)
            if v > 255:
                raise RezError(f'decimal escape value {v} out of range', where)
            out.append(v)
            i += 6
        elif two == '0b' and re.fullmatch(r'[01]{8}', raw[i + 3:i + 11] or ''):   # \0bBBBBBBBB
            out.append(int(raw[i + 3:i + 11], 2))
            i += 11
        elif e == '$':                                   # \$HH
            digits = raw[i + 2:i + 4]
            if not re.fullmatch(r'[0-9A-Fa-f]{2}', digits):
                raise RezError(f'invalid hex escape "\\{raw[i + 1:i + 4]}"', where)
            out.append(int(digits, 16))
            i += 4
        elif e in '01234567':                            # \ooo
            m = re.match(r'[0-7]{1,3}', raw[i + 1:])
            v = int(m.group(), 8)
            if v > 255:
                raise RezError(f'octal escape value {v} out of range', where)
            out.append(v)
            i += 1 + len(m.group())
        elif e in _SIMPLE_ESCAPES:
            out.append(_SIMPLE_ESCAPES[e])
            i += 2
        else:
            warn(f'unknown escape sequence "\\{e}"', where)
            out.append(char_to_mac_roman(e, where))
            i += 2
    return bytes(out)


def read_source(path):
    """Reads a Rez source file: UTF-8, or Mac Roman (MPW's encoding) when
    the bytes are not valid UTF-8; CR and CRLF line ends become LF."""
    with open(path, 'rb') as fp:
        raw = fp.read()
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError:
        text = mac_roman_to_utf8(raw)
    return text.replace('\r\n', '\n').replace('\r', '\n')


def skip_header_block(text):
    """The original sources start with a Pascal-style comment block
    "{Photoshop version 1.0.1, file: ...}" (not a comment in Rez -- MPW
    strips it when the sources are published).  Blank it out, keeping the
    line structure."""
    m = re.match(r'\s*', text)
    start = m.end()
    if start >= len(text) or text[start] != '{':
        return text
    end = text.find('}', start)
    if end < 0:
        return text
    block = text[start:end + 1]
    return text[:start] + re.sub(r'[^\n]', ' ', block) + text[end + 1:]


def lex(text, filename):
    toks = []
    pos = 0
    line = 1
    n = len(text)
    line_has_tok = False
    while pos < n:
        if text.startswith('/*', pos) and text.find('*/', pos + 2) < 0:
            raise RezError('unterminated comment', (filename, line))
        m = _TOKEN_RE.match(text, pos)
        if not m:
            ch = text[pos]
            if ch in '"\'':
                raise RezError('unterminated string or literal', (filename, line))
            raise RezError(f'unexpected character {ch!r}', (filename, line))
        kind = m.lastgroup
        s = m.group()
        where = (filename, line)
        if kind in ('ws', 'lcomment'):
            pass
        elif kind == 'cont':            # backslash-newline: the line continues
            line += 1
        elif kind == 'bcomment':
            line += s.count('\n')
        elif kind == 'nl':
            toks.append(Tok('nl', None, filename, line))
            line += 1
            line_has_tok = False
        else:
            if kind == 'hash':
                tok = Tok('hash', '#', filename, line, bol=not line_has_tok)
            elif kind == 'hex':
                digits = re.sub(r'\s+', '', s[2:-1])
                if not re.fullmatch(r'[0-9A-Fa-f]*', digits):
                    raise RezError('invalid character in hex string', where)
                if len(digits) % 2:
                    raise RezError('odd number of digits in hex string', where)
                tok = Tok('hex', bytes.fromhex(digits), filename, line)
            elif kind == 'str':
                tok = Tok('str', decode_string(s[1:-1], where), filename, line)
            elif kind == 'lit':
                tok = Tok('lit', decode_string(s[1:-1], where), filename, line)
                if not 1 <= len(tok.value) <= 4:
                    raise RezError(f'literal {s} must have 1 to 4 characters', where)
            elif kind == 'func':
                tok = Tok('func', s[2:], filename, line)
            elif kind == 'num':
                if s.startswith('$'):
                    v = int(s[1:], 16)
                elif s[:2] in ('0x', '0X'):
                    v = int(s[2:], 16)
                elif s[:2] in ('0b', '0B'):
                    v = int(s[2:], 2)
                elif len(s) > 1 and s[0] == '0':
                    if not re.fullmatch(r'[0-7]+', s):
                        raise RezError(f'invalid octal number {s}', where)
                    v = int(s, 8)
                else:
                    v = int(s, 10)
                tok = Tok('num', v, filename, line)
            elif kind == 'ident':
                tok = Tok('ident', s, filename, line)
            else:
                tok = Tok('punct', s, filename, line)
            toks.append(tok)
            line_has_tok = True
            line += s.count('\n')
        pos = m.end()
    toks.append(Tok('eof', None, filename, line))
    return toks


# ---------------------------------------------------------------------------
# Token cursor


class Cursor:
    def __init__(self, toks):
        self.toks = toks
        self.i = 0

    def peek(self, k=0):
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else self.toks[-1]

    def next(self):
        t = self.toks[self.i]
        if t.kind != 'eof':
            self.i += 1
        return t

    def at_eof(self):
        return self.peek().kind == 'eof'

    def at_punct(self, p):
        t = self.peek()
        return t.kind == 'punct' and t.value == p

    def at_keyword(self, kw):
        t = self.peek()
        return t.kind == 'ident' and t.value.lower() == kw

    def accept_punct(self, p):
        if self.at_punct(p):
            self.i += 1
            return True
        return False

    def expect_punct(self, p, context=''):
        t = self.peek()
        if t.kind == 'punct' and t.value == p:
            return self.next()
        ctx = f' {context}' if context else ''
        raise RezError(f"expected '{p}'{ctx} but found {t.describe()}", t)

    def expect(self, kind, what):
        t = self.peek()
        if t.kind != kind:
            raise RezError(f'expected {what} but found {t.describe()}', t)
        return self.next()


# ---------------------------------------------------------------------------
# Expressions (C precedence, like Rez)

_BINOPS = {
    '||': 1, '&&': 2, '|': 3, '^': 4, '&': 5, '==': 6, '!=': 6,
    '<': 7, '>': 7, '<=': 7, '>=': 7, '<<': 8, '>>': 8,
    '+': 9, '-': 9, '*': 10, '/': 10, '%': 10,
}


def literal_value(b):
    return int.from_bytes(b, 'big')


def parse_expr(cur, min_prec=1):
    lhs = parse_unary(cur)
    while True:
        t = cur.peek()
        if t.kind != 'punct' or t.value not in _BINOPS:
            break
        prec = _BINOPS[t.value]
        if prec < min_prec:
            break
        cur.next()
        rhs = parse_expr(cur, prec + 1)
        lhs = ('bin', t.value, lhs, rhs, t)
    return lhs


def parse_unary(cur):
    t = cur.peek()
    if t.kind == 'punct':
        if t.value in ('-', '+', '~', '!'):
            cur.next()
            return ('un', t.value, parse_unary(cur), t)
        if t.value == '(':
            cur.next()
            e = parse_expr(cur)
            cur.expect_punct(')', 'in expression')
            return e
    if t.kind == 'num':
        cur.next()
        return ('num', t.value, t)
    if t.kind == 'lit':
        cur.next()
        return ('num', literal_value(t.value), t)
    if t.kind == 'ident':
        cur.next()
        return ('sym', t.value, t)
    if t.kind == 'func':
        cur.next()
        cur.expect_punct('(', f'after $${t.value}')
        args = []
        if not cur.at_punct(')'):
            while True:
                args.append(parse_expr(cur))
                if not cur.accept_punct(','):
                    break
        cur.expect_punct(')', f'after $${t.value} arguments')
        return ('func', t.value, args, t)
    raise RezError(f'expected an expression but found {t.describe()}', t)


def _c_div(a, b, t):
    if b == 0:
        raise RezError('division by zero', t)
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def eval_expr(node, resolve, scope=None):
    """Evaluates an expression AST.  resolve(name, tok) supplies the values
    of identifiers; scope (a Scope) is needed for $$CountOf(label)."""
    op = node[0]
    if op == 'num':
        return node[1]
    if op == 'sym':
        return resolve(node[1], node[2])
    if op == 'un':
        v = eval_expr(node[2], resolve, scope)
        return {'-': -v, '+': v, '~': ~v, '!': int(not v)}[node[1]]
    if op == 'bin':
        o, t = node[1], node[4]
        a = eval_expr(node[2], resolve, scope)
        if o == '&&':
            return int(bool(a) and bool(eval_expr(node[3], resolve, scope)))
        if o == '||':
            return int(bool(a) or bool(eval_expr(node[3], resolve, scope)))
        b = eval_expr(node[3], resolve, scope)
        if o == '+':
            return a + b
        if o == '-':
            return a - b
        if o == '*':
            return a * b
        if o == '/':
            return _c_div(a, b, t)
        if o == '%':
            return a - b * _c_div(a, b, t)
        if o == '<<':
            return a << b
        if o == '>>':
            return a >> b
        if o == '&':
            return a & b
        if o == '|':
            return a | b
        if o == '^':
            return a ^ b
        return int({'==': a == b, '!=': a != b, '<': a < b, '>': a > b,
                    '<=': a <= b, '>=': a >= b}[o])
    if op == 'func':
        name, args, t = node[1].lower(), node[2], node[3]
        if name == 'countof':
            if len(args) != 1 or args[0][0] != 'sym':
                raise RezError('$$CountOf expects an array label', t)
            if scope is None:
                raise RezError('$$CountOf can only be used in constant fields of a type', t)
            elems = scope.lookup(args[0][1])
            if elems is None:
                raise RezError(f'unknown array label "{args[0][1]}"', t)
            return len(elems)
        raise RezError(f'function $${node[1]} is not supported', t)
    raise AssertionError(op)


def undefined_symbol(name, tok):
    raise RezError(f'undefined identifier "{name}"', tok)


# ---------------------------------------------------------------------------
# Preprocessor


class Preprocessor:
    MAX_INCLUDE_DEPTH = 32

    def __init__(self, macros, include_dirs=()):
        self.macros = macros            # name -> list of Tok (shared by all files)
        self.include_dirs = list(include_dirs)
        self.depth = 0

    def find_include(self, name, from_file, where):
        dirs = [os.path.dirname(os.path.abspath(from_file))] + self.include_dirs + [TOOL_DIR]
        for d in dirs:
            path = os.path.join(d, name)
            if os.path.isfile(path):
                return path
        raise RezError(f'cannot find #include file "{name}"', where)

    def include(self, line, from_file, where):
        """Tokens of an #include "file" / #include <file>, preprocessed."""
        args = line[1:]
        if len(args) == 1 and args[0].kind == 'str':
            name = mac_roman_to_utf8(args[0].value)
        elif (len(args) >= 3 and args[0].kind == 'punct' and args[0].value == '<'
              and args[-1].kind == 'punct' and args[-1].value == '>'):
            name = ''.join(str(a.value) if a.kind != 'str' else mac_roman_to_utf8(a.value)
                           for a in args[1:-1])
        else:
            raise RezError('#include expects "file" or <file>', where)
        if self.depth >= self.MAX_INCLUDE_DEPTH:
            raise RezError('#include nested too deeply', where)
        path = self.find_include(name, from_file, where)
        self.depth += 1
        try:
            toks = self.run(lex(read_source(path), path), path)
        finally:
            self.depth -= 1
        return toks[:-1]                # without the eof token

    def expand_into(self, tok, out, active):
        if tok.kind == 'ident' and tok.value in self.macros and tok.value not in active:
            inner = active | {tok.value}
            for bt in self.macros[tok.value]:
                # report errors at the place where the macro is used
                self.expand_into(Tok(bt.kind, bt.value, tok.file, tok.line), out, inner)
        else:
            out.append(tok)

    def eval_condition(self, args, where):
        toks = []
        k = 0
        while k < len(args):
            a = args[k]
            if a.kind == 'ident' and a.value == 'defined':
                paren = k + 1 < len(args) and args[k + 1].kind == 'punct' and args[k + 1].value == '('
                j = k + 2 if paren else k + 1
                if j >= len(args) or args[j].kind != 'ident':
                    raise RezError('"defined" expects a macro name', a)
                toks.append(Tok('num', int(args[j].value in self.macros), a.file, a.line))
                k = j + 1
                if paren:
                    if k >= len(args) or args[k].kind != 'punct' or args[k].value != ')':
                        raise RezError("expected ')' after defined(NAME", a)
                    k += 1
                continue
            self.expand_into(a, toks, frozenset())
            k += 1
        if not toks:
            raise RezError('missing expression in #if', where)
        toks.append(Tok('eof', None, where.file, where.line))
        cur = Cursor(toks)
        # Undefined identifiers count as 0, like in C.
        value = eval_expr(parse_expr(cur), lambda name, tok: 0)
        if not cur.at_eof():
            raise RezError(f'unexpected {cur.peek().describe()} in #if expression', cur.peek())
        return value != 0

    def run(self, toks, filename):
        out = []
        stack = []
        active = True
        i = 0
        while True:
            t = toks[i]
            if t.kind == 'eof':
                break
            if t.kind == 'nl':
                i += 1
                continue
            if t.kind == 'hash':
                if not t.bol:
                    raise RezError("stray '#'", t)
                j = i + 1
                line = []
                while toks[j].kind not in ('nl', 'eof'):
                    line.append(toks[j])
                    j += 1
                i = j
                if line and line[0].kind == 'ident' and line[0].value == 'include':
                    if active:
                        out.extend(self.include(line, filename, line[0]))
                    continue
                active = self.directive(t, line, stack, active)
                continue
            if active:
                self.expand_into(t, out, frozenset())
            i += 1
        if stack:
            raise RezError('unterminated #if', stack[-1]['tok'])
        out.append(toks[-1])
        return out

    def directive(self, hash_tok, line, stack, active):
        if not line or line[0].kind != 'ident':
            if not active:
                return active
            raise RezError('invalid preprocessor directive', hash_tok)
        d = line[0].value
        args = line[1:]
        if d in ('if', 'ifdef', 'ifndef'):
            cond = False
            if active:
                if d == 'if':
                    cond = self.eval_condition(args, line[0])
                else:
                    if len(args) != 1 or args[0].kind != 'ident':
                        raise RezError(f'#{d} expects a macro name', line[0])
                    cond = (args[0].value in self.macros) == (d == 'ifdef')
            stack.append({'parent': active, 'taken': cond, 'else': False, 'tok': line[0]})
            return active and cond
        if d in ('elif', 'else', 'endif'):
            if not stack:
                raise RezError(f'#{d} without #if', line[0])
            top = stack[-1]
            if d == 'endif':
                stack.pop()
                return top['parent']
            if top['else']:
                raise RezError(f'#{d} after #else', line[0])
            if d == 'else':
                top['else'] = True
                cond = not top['taken']
                top['taken'] = True
                return top['parent'] and cond
            cond = False
            if top['parent'] and not top['taken']:
                cond = self.eval_condition(args, line[0])
                top['taken'] = cond
            return top['parent'] and cond
        if not active:
            return active
        if d == 'define':
            if not args or args[0].kind != 'ident':
                raise RezError('#define expects a macro name', line[0])
            name = args[0].value
            body = args[1:]
            old = self.macros.get(name)
            if old is not None and [(x.kind, x.value) for x in old] != [(x.kind, x.value) for x in body]:
                warn(f'macro "{name}" redefined', line[0])
            self.macros[name] = body
        elif d == 'undef':
            if len(args) != 1 or args[0].kind != 'ident':
                raise RezError('#undef expects a macro name', line[0])
            self.macros.pop(args[0].value, None)
        elif d in ('printf', 'line', 'pragma'):
            warn(f'#{d} is not supported; ignored', line[0])
        else:
            raise RezError(f'unknown preprocessor directive #{d}', line[0])
        return active


# ---------------------------------------------------------------------------
# Resource type templates

_UNIT_BITS = {'bit': 1, 'nibble': 4, 'byte': 8, 'word': 16, 'long': 32}
_NUM_TYPES = {'byte': 8, 'integer': 16, 'longint': 32}
_STRING_TYPES = ('string', 'pstring', 'wstring', 'cstring')


class Field:
    """One field of a resource type template.

    kind: 'num' (bitstring/byte/integer/longint/boolean), 'char', 'str',
          'point', 'rect', 'fill', 'align', 'label', 'array', 'switch'."""

    def __init__(self, kind, tok):
        self.kind = kind
        self.tok = tok
        self.bits = 0               # num: width in bits
        self.unsigned = False
        self.symbols = {}           # lower-case name -> int or bytes
        self.const = None           # constant value (field not given in the data)
        self.is_key = False
        self.strkind = None         # str: string/pstring/wstring/cstring
        self.length = None          # str: fixed length
        self.unit = 0               # fill/align: unit size in bits
        self.count = None           # fill: units; array: fixed element count
        self.label = None           # array/label: label name
        self.fields = None          # array: element fields
        self.cases = None           # switch: list of Case

    def consumes_data(self):
        if self.kind in ('fill', 'align', 'label'):
            return False
        if self.kind in ('array', 'switch'):
            return True
        return self.const is None


class Case:
    def __init__(self, name, fields, tok):
        self.name = name
        self.fields = fields
        self.tok = tok


class Template:
    def __init__(self, restype, fields, tok):
        self.restype = restype
        self.fields = fields
        self.tok = tok


def const_int(cur):
    """Parses an expression that must be a compile-time constant."""
    t = cur.peek()
    return eval_expr(parse_expr(cur), undefined_symbol), t


def parse_string_tokens(cur, what='a string'):
    t = cur.peek()
    if t.kind not in ('str', 'hex'):
        raise RezError(f'expected {what} but found {t.describe()}', t)
    out = bytearray()
    while cur.peek().kind in ('str', 'hex'):
        out += cur.next().value
    return bytes(out)


class TypeParser:
    """Parses the body of a 'type' statement."""

    def __init__(self, cur):
        self.cur = cur

    def field_list(self, in_case=False):
        cur = self.cur
        fields = []
        while True:
            if cur.at_punct('}') or cur.at_eof():
                break
            if in_case and cur.at_keyword('case'):
                break
            fields.append(self.field())
        return fields

    def field(self):
        cur = self.cur
        t = cur.peek()
        if t.kind != 'ident':
            raise RezError(f'expected a field definition but found {t.describe()}', t)
        kw = t.value.lower()
        nxt = cur.peek(1)
        if nxt.kind == 'punct' and nxt.value == ':' and kw != 'case':
            cur.next()
            cur.next()
            f = Field('label', t)
            f.label = t.value
            return f
        if kw == 'fill':
            cur.next()
            f = Field('fill', t)
            f.unit = self.unit()
            f.count = 1
            if cur.accept_punct('['):
                f.count, _ = const_int(cur)
                cur.expect_punct(']')
            cur.expect_punct(';', 'after fill')
            return f
        if kw == 'align':
            cur.next()
            f = Field('align', t)
            f.unit = self.unit()
            cur.expect_punct(';', 'after align')
            return f
        if kw in ('array', 'wide'):
            cur.next()
            if kw == 'wide' and not (cur.peek().kind == 'ident' and cur.next().value.lower() == 'array'):
                raise RezError('expected "array" after "wide"', t)
            f = Field('array', t)
            if cur.peek().kind == 'ident':
                f.label = cur.next().value
            if cur.accept_punct('['):
                f.count, _ = const_int(cur)
                cur.expect_punct(']')
            cur.expect_punct('{', 'to start the array definition')
            f.fields = self.field_list()
            cur.expect_punct('}', 'to end the array definition')
            cur.accept_punct(';')
            if not any(x.consumes_data() for x in f.fields):
                raise RezError('array elements must contain at least one data field', t)
            return f
        if kw == 'switch':
            cur.next()
            f = Field('switch', t)
            f.cases = []
            cur.expect_punct('{', 'after switch')
            while not cur.at_punct('}'):
                ct = cur.expect('ident', '"case"')
                if ct.value.lower() != 'case':
                    raise RezError(f'expected "case" but found {ct.describe()}', ct)
                name = cur.expect('ident', 'a case name')
                cur.expect_punct(':', 'after the case name')
                fields = self.field_list(in_case=True)
                keys = [x for x in fields if x.is_key]
                if len(keys) != 1:
                    raise RezError(f'case "{name.value}" must have exactly one key field', name)
                if any(c.name.lower() == name.value.lower() for c in f.cases):
                    raise RezError(f'duplicate case "{name.value}"', name)
                f.cases.append(Case(name.value, fields, name))
            cur.expect_punct('}', 'to end the switch')
            cur.accept_punct(';')
            if not f.cases:
                raise RezError('empty switch', t)
            return f
        if kw == 'case':
            raise RezError('"case" outside of a switch', t)
        is_key = False
        if kw == 'key':
            cur.next()
            is_key = True
        f = self.data_type()
        f.is_key = is_key
        if cur.accept_punct('='):
            f.const = self.value(f, deferred=True)
        elif cur.peek().kind == 'ident':
            self.symbols(f)
        cur.expect_punct(';', 'after the field definition')
        if is_key and f.const is None:
            raise RezError('key fields need a constant value', t)
        return f

    def unit(self):
        t = self.cur.expect('ident', 'bit, nibble, byte, word or long')
        u = _UNIT_BITS.get(t.value.lower())
        if u is None:
            raise RezError(f'expected bit, nibble, byte, word or long but found {t.describe()}', t)
        return u

    def data_type(self):
        cur = self.cur
        unsigned = False
        while cur.peek().kind == 'ident':
            w = cur.peek().value.lower()
            if w == 'unsigned':
                unsigned = True
            elif w not in ('hex', 'decimal', 'octal', 'binary', 'literal'):
                break
            cur.next()                  # radix modifiers only matter for DeRez
        t = cur.expect('ident', 'a data type')
        w = t.value.lower()
        if w == 'bitstring':
            f = Field('num', t)
            cur.expect_punct('[', 'after bitstring')
            f.bits, bt = const_int(cur)
            cur.expect_punct(']')
            if not 1 <= f.bits <= 32:
                raise RezError(f'bitstring length {f.bits} not supported', bt)
        elif w in _NUM_TYPES:
            f = Field('num', t)
            f.bits = _NUM_TYPES[w]
        elif w == 'boolean':
            f = Field('num', t)
            f.bits = 1
            unsigned = True
        elif w == 'char':
            f = Field('char', t)
        elif w in _STRING_TYPES:
            f = Field('str', t)
            f.strkind = w
            if cur.accept_punct('['):
                f.length, lt = const_int(cur)
                cur.expect_punct(']')
                if f.length < 0 or (w == 'pstring' and f.length > 255):
                    raise RezError(f'invalid {w} length {f.length}', lt)
        elif w in ('point', 'rect'):
            f = Field(w, t)
        else:
            raise RezError(f'unknown data type "{t.value}"', t)
        f.unsigned = unsigned
        return f

    def value(self, f, deferred):
        """Parses a value in a type definition (constant field or symbol)."""
        cur = self.cur
        if f.kind == 'num':
            expr = parse_expr(cur)
            if deferred:
                return expr             # may use $$CountOf: evaluated when emitting

            def resolve(name, tok):
                v = f.symbols.get(name.lower())
                if isinstance(v, int):
                    return v
                return undefined_symbol(name, tok)
            return eval_expr(expr, resolve)
        if f.kind in ('char', 'str'):
            t = cur.peek()
            b = parse_string_tokens(cur)
            if f.kind == 'char' and len(b) != 1:
                raise RezError('char values must be one character long', t)
            return b
        if f.kind in ('point', 'rect'):
            n = 2 if f.kind == 'point' else 4
            cur.expect_punct('{')
            vals = []
            for k in range(n):
                v, _ = const_int(cur)
                vals.append(v)
                if k < n - 1:
                    cur.accept_punct(',')
            cur.expect_punct('}')
            return vals
        raise RezError('a value is not allowed here', f.tok)

    def symbols(self, f):
        cur = self.cur
        next_value = 0
        while True:
            name = cur.expect('ident', 'a symbolic name')
            if cur.accept_punct('='):
                v = self.value(f, deferred=False)
            elif f.kind == 'num':
                v = next_value
            else:
                raise RezError(f'symbolic name "{name.value}" needs a value', name)
            key = name.value.lower()
            if key in f.symbols and f.symbols[key] != v:
                warn(f'symbolic name "{name.value}" redefined in the same field', name)
            f.symbols[key] = v
            if f.kind == 'num':
                next_value = v + 1
            if not cur.accept_punct(','):
                break


# ---------------------------------------------------------------------------
# Binary output


class BitWriter:
    def __init__(self):
        self.buf = bytearray()
        self.bitpos = 0

    def write_bits(self, value, nbits):
        if nbits <= 0:
            return
        if self.bitpos % 8 == 0 and nbits % 8 == 0:
            self.buf += value.to_bytes(nbits // 8, 'big')
            self.bitpos += nbits
            return
        for i in range(nbits - 1, -1, -1):
            byte_index = self.bitpos >> 3
            if byte_index >= len(self.buf):
                self.buf.append(0)
            if (value >> i) & 1:
                self.buf[byte_index] |= 0x80 >> (self.bitpos & 7)
            self.bitpos += 1

    def write_bytes(self, data):
        if self.bitpos % 8 == 0:
            self.buf += data
            self.bitpos += 8 * len(data)
        else:
            for b in data:
                self.write_bits(b, 8)

    def align(self, unit_bits):
        rem = self.bitpos % unit_bits
        if rem:
            self.write_bits(0, unit_bits - rem)

    def data(self):
        return bytes(self.buf)


class Scope:
    """Array labels visible while emitting (for $$CountOf)."""

    def __init__(self, labels, parent):
        self.labels = labels
        self.parent = parent

    def lookup(self, name):
        s = self
        key = name.lower()
        while s is not None:
            if key in s.labels:
                return s.labels[key]
            s = s.parent
        return None


def check_range(value, f, where):
    lo = -(1 << (f.bits - 1)) if f.bits > 1 else 0
    hi = (1 << f.bits) - 1
    if f.unsigned:
        lo = 0
    if not lo <= value <= hi:
        warn(f'value {value} does not fit in a {f.bits}-bit field', where)
    return value & ((1 << f.bits) - 1)


def encode_string(f, b, where):
    k = f.strkind
    n = f.length
    if k == 'string':
        if n is not None:
            if len(b) > n:
                warn(f'string truncated to {n} bytes', where)
            b = b[:n] + bytes(max(0, n - len(b)))
        return b
    if k == 'pstring':
        limit = 255 if n is None else n
        if len(b) > limit:
            warn(f'string truncated to {limit} characters', where)
            b = b[:limit]
        out = bytes([len(b)]) + b
        if n is not None:
            out += bytes(n - len(b))
        return out
    if k == 'wstring':
        limit = 65535 if n is None else n
        if len(b) > limit:
            warn(f'string truncated to {limit} characters', where)
            b = b[:limit]
        out = len(b).to_bytes(2, 'big') + b
        if n is not None:
            out += bytes(n - len(b))
        return out
    if k == 'cstring':
        if n is not None:
            if len(b) > n - 1:
                warn(f'string truncated to {max(0, n - 1)} characters', where)
                b = b[:max(0, n - 1)]
            return b + bytes(n - len(b))
        return b + b'\0'
    raise AssertionError(k)


class Value:
    """A value parsed from resource data, with its source location."""
    __slots__ = ('v', 'tok')

    def __init__(self, v, tok):
        self.v = v
        self.tok = tok


def emit_fields(w, fields, values, scope):
    labels = {}
    for f, v in zip(fields, values):
        if f.kind == 'array' and f.label:
            labels[f.label.lower()] = v.v
    scope = Scope(labels, scope)
    for f, v in zip(fields, values):
        emit_field(w, f, v, scope)


def emit_field(w, f, v, scope):
    k = f.kind
    if k == 'num':
        if v is None:
            value = eval_expr(f.const, undefined_symbol, scope)
            w.write_bits(check_range(value, f, f.tok), f.bits)
        else:
            w.write_bits(check_range(v.v, f, v.tok), f.bits)
    elif k == 'char':
        w.write_bytes(f.const if v is None else v.v)
    elif k == 'str':
        if v is None:
            w.write_bytes(encode_string(f, f.const, f.tok))
        else:
            w.write_bytes(encode_string(f, v.v, v.tok))
    elif k in ('point', 'rect'):
        vals = f.const if v is None else v.v
        where = f.tok if v is None else v.tok
        for x in vals:
            if not -32768 <= x <= 65535:
                warn(f'coordinate {x} does not fit in 16 bits', where)
            w.write_bits(x & 0xFFFF, 16)
    elif k == 'fill':
        w.write_bits(0, f.unit * f.count)
    elif k == 'align':
        w.align(f.unit)
    elif k == 'label':
        pass
    elif k == 'array':
        for elem in v.v:
            emit_fields(w, f.fields, elem, scope)
    elif k == 'switch':
        case, vals = v.v
        emit_fields(w, case.fields, vals, scope)
    else:
        raise AssertionError(k)


# ---------------------------------------------------------------------------
# Resource data parsing (template driven)


def field_resolver(f):
    def resolve(name, tok):
        v = f.symbols.get(name.lower())
        if v is None:
            raise RezError(f'undefined identifier "{name}"', tok)
        if not isinstance(v, int):
            raise RezError(f'"{name}" is not a numeric value', tok)
        return v
    return resolve


def parse_data_fields(cur, fields):
    """Parses the values for a list of template fields.  Rez is lenient
    about separators: commas and semicolons may be used interchangeably and
    are optional (trailing separators are accepted)."""
    values = []
    for f in fields:
        if not f.consumes_data():
            values.append(None)
            continue
        values.append(parse_data_value(cur, f))
        if not cur.accept_punct(','):
            cur.accept_punct(';')
    return values


def parse_data_value(cur, f):
    t = cur.peek()
    k = f.kind
    if k == 'num':
        return Value(eval_expr(parse_expr(cur), field_resolver(f)), t)
    if k in ('char', 'str'):
        if t.kind == 'ident':
            v = f.symbols.get(t.value.lower())
            if not isinstance(v, bytes):
                raise RezError(f'undefined identifier "{t.value}" (expected a string)', t)
            cur.next()
            b = v
        else:
            b = parse_string_tokens(cur)
        if k == 'char' and len(b) != 1:
            warn('char value is not one character long', t)
            b = (b + b'\0')[:1]
        return Value(b, t)
    if k in ('point', 'rect'):
        n = 2 if k == 'point' else 4
        cur.expect_punct('{', f'to start the {k}')
        vals = []
        resolve = field_resolver(f)
        for i in range(n):
            vals.append(eval_expr(parse_expr(cur), resolve))
            if i < n - 1 and not cur.accept_punct(','):
                cur.accept_punct(';')
        cur.expect_punct('}', f'to end the {k}')
        return Value(vals, t)
    if k == 'array':
        cur.expect_punct('{', 'to start the array')
        elems = []
        while not cur.at_punct('}'):
            if cur.at_eof():
                raise RezError('unterminated array', t)
            start = cur.i
            elems.append(parse_data_fields(cur, f.fields))
            if cur.i == start:
                raise RezError(f'unexpected {cur.peek().describe()} in array', cur.peek())
        cur.expect_punct('}', 'to end the array')
        if f.count is not None and len(elems) != f.count:
            raise RezError(f'array needs exactly {f.count} elements but has {len(elems)}', t)
        return Value(elems, t)
    if k == 'switch':
        name = cur.expect('ident', 'a case name')
        for case in f.cases:
            if case.name.lower() == name.value.lower():
                break
        else:
            names = ', '.join(c.name for c in f.cases)
            raise RezError(f'unknown case "{name.value}" (expected one of {names})', name)
        cur.expect_punct('{', f'after "{name.value}"')
        vals = parse_data_fields(cur, case.fields)
        cur.expect_punct('}', f'to end "{name.value}"')
        return Value((case, vals), name)
    raise AssertionError(k)


# ---------------------------------------------------------------------------
# Statements

_ATTR_SET = {'sysheap': 0x40, 'purgeable': 0x20, 'locked': 0x10,
             'protected': 0x08, 'preload': 0x04, 'changed': 0x02}
_ATTR_CLEAR = {'appheap': 0x40, 'nonpurgeable': 0x20, 'unlocked': 0x10,
               'unprotected': 0x08, 'nonpreload': 0x04, 'unchanged': 0x02}


class Resource:
    def __init__(self, restype, resid, name, attrs, data, where):
        self.restype = restype      # 4 bytes
        self.resid = resid
        self.name = name            # Mac Roman bytes or None
        self.attrs = attrs
        self.data = data
        self.where = where


def type_name(restype):
    return mac_roman_to_utf8(restype)


class Compiler:
    def __init__(self, verbose=False, include_dirs=(), search_dirs=(), lenient=False):
        self.macros = {}
        self.pp = Preprocessor(self.macros, include_dirs)
        self.types = {}             # 4 bytes -> Template or ('alias', 4 bytes, tok)
        self.resources = {}         # (type, id) -> Resource
        self.order = []
        self.verbose = verbose
        self.search_dirs = list(search_dirs)
        self.lenient = lenient

    def define(self, name, value):
        toks = lex(value, '<command line>')[:-1]
        self.macros[name] = [t for t in toks if t.kind != 'nl']

    def compile_file(self, path, display_name=None):
        display_name = display_name or path
        text = read_source(path)
        toks = self.pp.run(lex(skip_header_block(text), display_name), display_name)
        cur = Cursor(toks)
        while not cur.at_eof():
            t = cur.next()
            if t.kind == 'punct' and t.value == ';':
                continue
            if t.kind != 'ident':
                raise RezError(f'expected a statement but found {t.describe()}', t)
            kw = t.value.lower()
            if kw == 'type':
                self.type_statement(cur, t)
            elif kw == 'resource':
                self.resource_statement(cur, t)
            elif kw == 'data':
                self.data_statement(cur, t)
            elif kw == 'read':
                self.read_statement(cur, t)
            elif kw == 'include':
                self.include_statement(cur, t)
            elif kw in ('change', 'delete'):
                warn(f'"{t.value}" statements are not supported; ignored', t)
                self.skip_statement(cur, t)
            else:
                raise RezError(f'unknown statement "{t.value}"', t)

    def skip_statement(self, cur, t):
        """Skips to the ';' that ends a statement, over balanced braces."""
        depth = 0
        while True:
            if cur.at_eof():
                raise RezError(f'missing \';\' after "{t.value}" statement', t)
            p = cur.next()
            if p.kind == 'punct':
                if p.value == '{':
                    depth += 1
                elif p.value == '}':
                    depth -= 1
                elif p.value == ';' and depth <= 0:
                    return

    def find_file(self, name, where):
        """A file named by a read or include statement: absolute, or relative
        to the source file or one of the -s directories."""
        if os.path.isabs(name) and os.path.isfile(name):
            return name
        src = where.file if isinstance(where, Tok) else ''
        for d in [os.path.dirname(os.path.abspath(src))] + self.search_dirs + [os.getcwd()]:
            path = os.path.join(d, name)
            if os.path.isfile(path):
                return path
        raise RezError(f'cannot find file "{name}"', where)

    def read_statement(self, cur, t):
        """read 'TYPE' (id, ...) "file";  -- the data are the bytes of the file."""
        restype, resid, name, attrs, tt = self.resource_header(cur)
        ft = cur.peek()
        fname = mac_roman_to_utf8(parse_string_tokens(cur, 'a file name'))
        cur.expect_punct(';', 'after the read statement')
        with open(self.find_file(fname, ft), 'rb') as fp:
            data = fp.read()
        self.add_resource(Resource(restype, resid, name, attrs, data, tt))

    def include_statement(self, cur, t):
        """include "file" [ 'TYPE' [ (id) ] ];  -- resources of a resource fork
        file (the raw fork, as written by --rsrc or extracted from a Mac file)."""
        ft = cur.peek()
        fname = mac_roman_to_utf8(parse_string_tokens(cur, 'a file name'))
        want_type = want_id = None
        if cur.peek().kind == 'lit':
            want_type, _ = self.restype(cur)
            if cur.accept_punct('('):
                want_id = eval_expr(parse_expr(cur), undefined_symbol)
                cur.expect_punct(')', 'after the resource ID')
        cur.expect_punct(';', 'after the include statement')
        path = self.find_file(fname, ft)
        with open(path, 'rb') as fp:
            fork = fp.read()
        try:
            found = read_resource_fork(fork)
        except ValueError as e:
            raise RezError(f'"{fname}" is not a resource fork: {e}', ft)
        n = 0
        for r in found:
            if want_type is not None and r.restype != want_type:
                continue
            if want_id is not None and r.resid != want_id:
                continue
            r.where = ft
            self.add_resource(r)
            n += 1
        if n == 0:
            warn(f'no matching resources in "{fname}"', ft)

    def restype(self, cur):
        t = cur.expect('lit', 'a resource type literal')
        if len(t.value) != 4:
            raise RezError('resource types must have 4 characters', t)
        return t.value, t

    def type_statement(self, cur, t):
        restype, tt = self.restype(cur)
        if cur.accept_punct('('):
            warn('resource ID ranges in type declarations are not supported; '
                 'the template is used for all IDs', tt)
            while not cur.accept_punct(')'):
                if cur.at_eof():
                    raise RezError("missing ')'", tt)
                cur.next()
        if restype in self.types:
            warn(f"type '{type_name(restype)}' redefined", tt)
        if cur.at_keyword('as'):
            cur.next()
            target, target_tok = self.restype(cur)
            if cur.accept_punct('('):
                raise RezError('"as" with a resource ID is not supported', target_tok)
            cur.expect_punct(';', 'after the type statement')
            self.types[restype] = ('alias', target, target_tok)
            return
        cur.expect_punct('{', 'to start the type definition')
        fields = TypeParser(cur).field_list()
        cur.expect_punct('}', 'to end the type definition')
        cur.accept_punct(';')
        self.types[restype] = Template(restype, fields, tt)

    def find_template(self, restype):
        """The template of a type (following 'as' aliases), or None."""
        seen = set()
        t = restype
        while True:
            tmpl = self.types.get(t)
            if tmpl is None or isinstance(tmpl, Template):
                return tmpl
            if t in seen:
                return None
            seen.add(t)
            t = tmpl[1]

    def template(self, restype, where):
        seen = set()
        t = restype
        while True:
            tmpl = self.types.get(t)
            if tmpl is None:
                raise RezError(f"no type declaration for '{type_name(t)}'", where)
            if isinstance(tmpl, Template):
                return tmpl
            if t in seen:
                raise RezError(f"circular type alias for '{type_name(restype)}'", where)
            seen.add(t)
            t = tmpl[1]

    def resource_header(self, cur):
        restype, tt = self.restype(cur)
        cur.expect_punct('(', 'after the resource type')
        idt = cur.peek()
        resid = eval_expr(parse_expr(cur), undefined_symbol)
        if not -32768 <= resid <= 32767:
            raise RezError(f'resource ID {resid} out of range', idt)
        name = None
        attrs = 0
        while cur.accept_punct(','):
            a = cur.peek()
            if a.kind in ('str', 'hex'):
                if name is not None:
                    raise RezError('resource name given twice', a)
                name = parse_string_tokens(cur)
                if len(name) > 255:
                    raise RezError('resource name too long', a)
            elif a.kind == 'ident' and a.value.lower() in _ATTR_SET:
                cur.next()
                attrs |= _ATTR_SET[a.value.lower()]
            elif a.kind == 'ident' and a.value.lower() in _ATTR_CLEAR:
                cur.next()
                attrs &= ~_ATTR_CLEAR[a.value.lower()]
            else:
                attrs = eval_expr(parse_expr(cur), undefined_symbol)
                if not 0 <= attrs <= 255:
                    raise RezError(f'resource attributes {attrs} out of range', a)
        cur.expect_punct(')', 'to end the resource header')
        return restype, resid, name, attrs, tt

    def add_resource(self, res):
        key = (res.restype, res.resid)
        old = self.resources.get(key)
        if old is not None:
            warn(f"duplicate resource '{type_name(res.restype)}' ({res.resid}); this definition "
                 f"replaces the one at {_where(old.where)}", res.where)
        else:
            self.order.append(key)
        self.resources[key] = res

    def resource_statement(self, cur, t):
        restype, resid, name, attrs, tt = self.resource_header(cur)
        if self.lenient and self.find_template(restype) is None:
            warn(f"no type declaration for '{type_name(restype)}'; resource "
                 f"({resid}) skipped", tt)
            self.skip_statement(cur, t)
            return
        tmpl = self.template(restype, tt)
        cur.expect_punct('{', 'to start the resource data')
        values = parse_data_fields(cur, tmpl.fields)
        cur.expect_punct('}', f"at the end of resource '{type_name(restype)}' ({resid})")
        cur.accept_punct(';')
        w = BitWriter()
        emit_fields(w, tmpl.fields, values, None)
        if w.bitpos % 8:
            warn(f'resource data is not a whole number of bytes ({w.bitpos} bits); padded', tt)
            w.align(8)
        self.add_resource(Resource(restype, resid, name, attrs, w.data(), tt))

    def data_statement(self, cur, t):
        restype, resid, name, attrs, tt = self.resource_header(cur)
        cur.expect_punct('{', 'to start the resource data')
        data = bytearray()
        while not cur.at_punct('}'):
            d = cur.peek()
            if d.kind in ('str', 'hex'):
                data += cur.next().value
            elif d.kind == 'punct' and d.value in (',', ';'):
                cur.next()
            else:
                raise RezError(f'expected a string in data statement but found {d.describe()}', d)
        cur.expect_punct('}')
        cur.accept_punct(';')
        self.add_resource(Resource(restype, resid, name, attrs, bytes(data), tt))


# ---------------------------------------------------------------------------
# Resource forks (Inside Macintosh I-128)

_ATTR_NAMES = [(0x40, 'sysHeap'), (0x20, 'purgeable'), (0x10, 'locked'),
               (0x08, 'protected'), (0x04, 'preload'), (0x02, 'changed')]


def map_layout(resources):
    """Groups resources for a resource map: [(type, [Resource])] with the
    types in the order of their first resource and the resources of a type
    in the given order."""
    types = []
    by_type = {}
    for r in resources:
        if r.restype not in by_type:
            by_type[r.restype] = []
            types.append(r.restype)
        by_type[r.restype].append(r)
    return [(t, by_type[t]) for t in types]


def write_resource_fork(resources):
    """The resources as a resource fork: header, data (each with its length
    long), map (type list, reference lists, name list)."""
    data = bytearray()
    offsets = []
    for r in resources:
        offsets.append(len(data))
        data += len(r.data).to_bytes(4, 'big') + r.data
    layout = map_layout(resources)
    names = bytearray()
    name_off = {}
    for r in resources:
        if r.name is not None:
            name_off[id(r)] = len(names)
            names += bytes([len(r.name)]) + r.name
    type_list = bytearray((len(layout) - 1).to_bytes(2, 'big', signed=True))
    refs = bytearray()
    ref_base = 2 + 8 * len(layout)
    index = {id(r): k for k, r in enumerate(resources)}
    for restype, rs in layout:
        type_list += restype + (len(rs) - 1).to_bytes(2, 'big') + (ref_base + len(refs)).to_bytes(2, 'big')
        for r in rs:
            refs += r.resid.to_bytes(2, 'big', signed=True)
            refs += name_off.get(id(r), 0xFFFF).to_bytes(2, 'big')
            refs += bytes([r.attrs]) + offsets[index[id(r)]].to_bytes(3, 'big')
            refs += bytes(4)
    map_len = 28 + len(type_list) + len(refs) + len(names)
    header = (256).to_bytes(4, 'big') + (256 + len(data)).to_bytes(4, 'big') + \
        len(data).to_bytes(4, 'big') + map_len.to_bytes(4, 'big')
    rmap = header + bytes(4 + 2 + 2) + (28).to_bytes(2, 'big') + \
        (28 + len(type_list) + len(refs)).to_bytes(2, 'big') + type_list + refs + names
    return header + bytes(256 - len(header)) + bytes(data) + rmap


def read_resource_fork(fork):
    """The resources of a resource fork, in map order (ValueError if the
    bytes are not a resource fork)."""
    if len(fork) < 16:
        raise ValueError('too short')
    doff, moff, dlen, mlen = (int.from_bytes(fork[k:k + 4], 'big') for k in range(0, 16, 4))
    if doff + dlen > len(fork) or moff + mlen > len(fork) or mlen < 30:
        raise ValueError('bad header')
    m = fork[moff:moff + mlen]
    tl = int.from_bytes(m[24:26], 'big')
    nl = int.from_bytes(m[26:28], 'big')
    ntypes = (int.from_bytes(m[tl:tl + 2], 'big') + 1) & 0xFFFF
    out = []
    for k in range(ntypes):
        e = tl + 2 + 8 * k
        restype = bytes(m[e:e + 4])
        n = int.from_bytes(m[e + 4:e + 6], 'big') + 1
        rl = tl + int.from_bytes(m[e + 6:e + 8], 'big')
        for j in range(n):
            r = rl + 12 * j
            resid = int.from_bytes(m[r:r + 2], 'big', signed=True)
            noff = int.from_bytes(m[r + 2:r + 4], 'big')
            attrs = m[r + 4]
            d = doff + int.from_bytes(m[r + 5:r + 8], 'big')
            size = int.from_bytes(fork[d:d + 4], 'big')
            name = None
            if noff != 0xFFFF:
                ln = m[nl + noff]
                name = bytes(m[nl + noff + 1:nl + noff + 1 + ln])
            out.append(Resource(restype, resid, name, attrs, bytes(fork[d + 4:d + 4 + size]), None))
    return out


def read_rom_resource_fork(rom):
    """The resources of a ROM image (Mac Plus/SE layout: the long at +$1A of
    the ROM header points to the resource count and map size, then the map;
    data offsets are relative to ROM offset 0, and each resource's data
    follow an 8-byte block header). Returns (resources in map order, info);
    each Resource has .rom = (header offset, tag byte, relative handle)."""
    if len(rom) < 0x20:
        raise ValueError('too short for a ROM image')
    area = int.from_bytes(rom[0x1A:0x1E], 'big')
    if area + 4 + 28 > len(rom):
        raise ValueError('no resource map at the offset of the ROM header')
    count = int.from_bytes(rom[area:area + 2], 'big')
    msize = int.from_bytes(rom[area + 2:area + 4], 'big')
    m = area + 4
    mp = bytes(rom[m:m + msize])
    tl = int.from_bytes(mp[24:26], 'big')
    nl = int.from_bytes(mp[26:28], 'big')
    ntypes = (int.from_bytes(mp[tl:tl + 2], 'big') + 1) & 0xFFFF
    out = []
    for k in range(ntypes):
        e = tl + 2 + 8 * k
        restype = bytes(mp[e:e + 4])
        n = int.from_bytes(mp[e + 4:e + 6], 'big') + 1
        rl = tl + int.from_bytes(mp[e + 6:e + 8], 'big')
        for j in range(n):
            r = rl + 12 * j
            resid = int.from_bytes(mp[r:r + 2], 'big', signed=True)
            noff = int.from_bytes(mp[r + 2:r + 4], 'big')
            attrs = mp[r + 4]
            d = int.from_bytes(mp[r + 5:r + 8], 'big')
            tag = int.from_bytes(rom[d - 8:d - 4], 'big')
            size = (tag & 0xFFFFFF) - 8 - ((tag >> 24) & 0x0F)
            name = None
            if noff != 0xFFFF:
                ln = mp[nl + noff]
                name = bytes(mp[nl + noff + 1:nl + noff + 1 + ln])
            res = Resource(restype, resid, name, attrs, bytes(rom[d:d + size]), None)
            res.rom = (d - 8, tag >> 24, int.from_bytes(rom[d - 4:d], 'big'))
            out.append(res)
    info = {'area': area, 'count': count, 'map_size': msize,
            'header': [int.from_bytes(mp[k:k + 4], 'big') for k in range(0, 16, 4)],
            'next_map': int.from_bytes(mp[16:20], 'big'),
            'file_ref': int.from_bytes(mp[20:22], 'big', signed=True),
            'map_attrs': int.from_bytes(mp[22:24], 'big')}
    return out, info


# ---------------------------------------------------------------------------
# ROM resource fork (--rom-asm; layout types of RomTypes.r)

ROM_LAYOUT_TYPES = (b'rrhd', b'rrsc')


class _Reader:
    """Decodes the data of a layout resource (big-endian, as Rez emits it)."""

    def __init__(self, res):
        self.d = res.data
        self.p = 0
        self.res = res

    def need(self, n):
        if self.p + n > len(self.d):
            raise RezError(f"'{type_name(self.res.restype)}' ({self.res.resid}) is too short "
                           f"for its RomTypes.r layout", self.res.where)

    def int(self, n, signed=False):
        self.need(n)
        v = int.from_bytes(self.d[self.p:self.p + n], 'big', signed=signed)
        self.p += n
        return v

    def bytes(self, n):
        self.need(n)
        v = self.d[self.p:self.p + n]
        self.p += n
        return v

    def pstring(self):
        return self.bytes(self.int(1))

    def align_word(self):
        self.p += self.p & 1


class RomEntry:
    def __init__(self, kind, restype, resid, name, attrs, symbol, data, where):
        self.kind = kind            # 'asm' or 'rez'
        self.restype = restype
        self.resid = resid
        self.name = name            # bytes or None
        self.attrs = attrs
        self.symbol = symbol
        self.data = data            # rez: the compiled data
        self.where = where


_SYMBOL_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def rom_layout(compiler):
    """(header parameters, [RomEntry]) from the 'rrhd' and 'rrsc' resources."""
    maps = [r for k, r in compiler.resources.items() if k[0] == b'rrhd']
    if len(maps) != 1:
        raise RezError(f"--rom-asm needs exactly one 'rrhd' resource, found {len(maps)}")
    rd = _Reader(maps[0])
    params = {
        'first_relh': rd.int(4),
        'next_map': rd.int(4),
        'file_ref': rd.int(2, signed=True),
        'map_attrs': rd.int(2),
        'base': mac_roman_to_utf8(rd.pstring()),
        'where': maps[0].where,
    }
    rd.align_word()
    params['name_order'] = [(rd.bytes(4), rd.int(2, signed=True)) for _ in range(rd.int(2))]
    if not _SYMBOL_RE.match(params['base']):
        raise RezError(f'"{params["base"]}" is not an assembler label', maps[0].where)
    entries = []
    for key in sorted((k for k in compiler.resources if k[0] == b'rrsc'), key=lambda k: k[1]):
        res = compiler.resources[key]
        rd = _Reader(res)
        for _ in range(rd.int(2)):
            kind = rd.int(2)
            restype = rd.bytes(4)
            resid = rd.int(2, signed=True)
            if kind == 1:
                attrs = rd.int(1)
                name = rd.pstring() or None
                symbol = mac_roman_to_utf8(rd.pstring())
                rd.align_word()
                entries.append(RomEntry('asm', restype, resid, name, attrs, symbol, None, res.where))
            elif kind == 2:
                symbol = mac_roman_to_utf8(rd.pstring())
                rd.align_word()
                src = compiler.resources.get((restype, resid))
                if src is None:
                    raise RezError(f"'rrsc' ({res.resid}) names '{type_name(restype)}' ({resid}), "
                                   f"which the sources do not define", res.where)
                entries.append(RomEntry('rez', restype, resid, src.name, src.attrs, symbol,
                                        src.data, res.where))
            else:
                raise RezError(f"'rrsc' ({res.resid}): unknown entry kind {kind}", res.where)
    if not entries:
        raise RezError("--rom-asm: no 'rrsc' resources")
    seen, syms = {}, {}
    for e in entries:
        k = (e.restype, e.resid)
        if k in seen:
            raise RezError(f"'{type_name(e.restype)}' ({e.resid}) is in the ROM twice", e.where)
        seen[k] = e
        if not _SYMBOL_RE.match(e.symbol):
            raise RezError(f'"{e.symbol}" is not an assembler symbol', e.where)
        if e.symbol.lower() in syms:
            raise RezError(f'assembler symbol "{e.symbol}" used twice', e.where)
        syms[e.symbol.lower()] = e
    placed = {(e.restype, e.resid) for e in entries if e.kind == 'rez'}
    for k, r in compiler.resources.items():
        if k[0] not in ROM_LAYOUT_TYPES and k not in placed:
            warn(f"'{type_name(k[0])}' ({k[1]}) is compiled but not in any 'rrsc'; "
                 f"it is not part of the ROM", r.where)
    for t_, i_ in params['name_order']:
        e = seen.get((t_, i_))
        if e is None or e.name is None:
            raise RezError(f"'rrhd' name order: '{type_name(t_)}' ({i_}) is not a named "
                           f"ROM resource", params['where'])
    return params, entries


def _asm_string(b):
    """A GNU as string literal for Mac Roman bytes."""
    out = []
    for c in b:
        if c in (0x22, 0x5C):
            out.append('\\' + chr(c))
        elif 0x20 <= c < 0x7F:
            out.append(chr(c))
        else:
            out.append('\\%03o' % c)
    return '"' + ''.join(out) + '"'


def _asm_type(restype):
    """Macro argument for a resource type: a string if it is printable."""
    if all(0x20 <= c < 0x7F and c not in (0x22, 0x5C, 0x2C) for c in restype):
        return '"' + restype.decode('ascii') + '"'
    return None


def _line(code, comment=''):
    if not comment:
        return code
    return (code.ljust(48) if len(code) < 48 else code + ' ') + '| ' + comment


def generate_rom_asm(compiler, inputs, out_name):
    params, entries = rom_layout(compiler)
    n = len(entries)
    layout = map_layout(entries)
    named = [e for e in entries if e.name is not None]
    order = [next(e for e in entries if (e.restype, e.resid) == k) for k in params['name_order']]
    order += [e for e in named if e not in order]
    name_index = {id(e): k for k, e in enumerate(order)}
    srcs = ', '.join(os.path.relpath(p) for p in inputs)
    L = []
    L.append(f'| {out_name} -- GENERATED by tools/rez/rezc.py from {srcs};')
    L.append('| do not edit.')
    L.append('|')
    L.append(f'| The resource fork of the ROM: {n} resources, in ROM order. With the macros')
    L.append('| of include/romrsrc.inc:')
    L.append('|   ROM_RESOURCE_AREA      the two words that InitResources reads')
    L.append('|   ROM_RESOURCE_MAP       the resource map')
    L.append('|   ROM_RESOURCE sym ... ROM_RESOURCE_END sym')
    L.append('|                          the 8-byte header in front of the data of each')
    L.append('|                          resource, and its size (from the data between them)')
    L.append('|   ROM_RESOURCE_REZ sym   the same for the data of a resource compiled by rezc')
    L.append('')
    L.append(_line(f'    .set .LROMRSRC_BASE, {params["base"]}', 'ROM offset 0'))
    L.append(_line(f'    .set .LROMRSRC_COUNT, {n}', 'number of ROM resources'))
    L.append(_line('    .set .LROMRSRC_SEQ, 0', 'counts the ROM_RESOURCE macros'))
    L.append('')
    L.append('| index, relative handle (offset of the master pointer in the ROM zone)')
    for i, e in enumerate(entries):
        desc = f"'{type_name(e.restype)}' ({e.resid}"
        desc += f', "{mac_roman_to_utf8(e.name)}")' if e.name is not None else ')'
        if e.kind == 'rez':
            desc += ', compiled by rezc'
        L.append(_line(f'    .set .LROMRSRC_{e.symbol}_INDEX, {i}', desc))
        L.append(f'    .set .LROMRSRC_{e.symbol}_RELH, 0x{params["first_relh"] + 4 * i:X}')
    L.append('')
    datalen = f'4*{n} + ' + ' + '.join(f'.LROMRSRC_{e.symbol}_SIZE' for e in entries)
    L.append('.macro ROM_RESOURCE_AREA')
    L.append(_line(f'    .short  {n}', 'number of ROM resources: one master pointer each'))
    L.append(_line('    .short  .LRMAP_END - .LRMAP_START', 'size of the resource map'))
    L.append('.endm')
    L.append('')
    attr_names = {0x8000: 'mapReadOnly', 0x4000: 'mapCompact', 0x2000: 'mapChanged'}
    ma = params['map_attrs']
    ma_desc = '+'.join(v for k, v in attr_names.items() if ma & k) or 'none'
    L.append('.macro ROM_RESOURCE_MAP')
    L.append('.LRMAP_START:')
    L.append('| the header of an equivalent resource file')
    L.append(_line('    .long   0x100', 'offset of the resource data'))
    L.append(_line('    .long   0x100 + .LROMRSRC_DATALEN', 'offset of the resource map'))
    L.append(_line('    .long   .LROMRSRC_DATALEN', 'length of the resource data'))
    L.append(_line('    .long   .LRMAP_END - .LRMAP_START', 'length of the resource map'))
    L.append(_line(f'    .long   0x{params["next_map"]:08X}', 'next-map handle'))
    L.append(_line(f'    .short  {params["file_ref"]}', 'file reference number'))
    L.append(_line(f'    .short  0x{ma:04X}', f'map attributes: {ma_desc}'))
    L.append(_line('    .short  .LRMAP_TYPES - .LRMAP_START', 'offset of the type list'))
    L.append(_line('    .short  .LRMAP_NAMES - .LRMAP_START', 'offset of the name list'))
    L.append('.LRMAP_TYPES:')
    L.append(_line(f'    .short  {len(layout)} - 1', 'number of types - 1'))
    for k, (restype, es) in enumerate(layout):
        targ = _asm_type(restype)
        if targ is None:
            raise RezError(f"resource type '{type_name(restype)}' cannot be written as a "
                           f"string", es[0].where)
        L.append(f'    RMAP_TYPE {targ}, {len(es)}, .LRMAP_REFS_{k}')
    for k, (restype, es) in enumerate(layout):
        L.append(f'.LRMAP_REFS_{k}:')
        for e in es:
            if e.name is not None:
                noff = f'.LRMAP_NAME_{name_index[id(e)]} - .LRMAP_NAMES'
                desc = f'"{mac_roman_to_utf8(e.name)}"'
            else:
                noff = '-1'
                desc = ''
            attrs = ', '.join(nm for bit, nm in _ATTR_NAMES if e.attrs & bit) or 'none'
            L.append(_line(f'    RMAP_REF {e.resid}, {noff}, 0x{e.attrs:02X}, {e.symbol}',
                           f"'{type_name(restype)}' ({e.resid}) {desc} {attrs}".replace('  ', ' ')))
    L.append('.LRMAP_NAMES:')
    for k, e in enumerate(order):
        L.append(f'.LRMAP_NAME_{k}:')
        L.append(_line(f'    .byte   {len(e.name)}', f"name of '{type_name(e.restype)}' ({e.resid})"))
        L.append(f'    .ascii  {_asm_string(e.name)}')
    L.append('.LRMAP_END:')
    L.append(_line('    .balign 2, 0', 'the resources start at an even address'))
    L.append('.endm')
    L.append('')
    L.append('| length of the resource data of an equivalent resource file: the data of')
    L.append('| each resource with its length long (the sizes come from ROM_RESOURCE_END)')
    L.append(f'    .set .LROMRSRC_DATALEN, {datalen}')
    for e in entries:
        if e.kind != 'rez':
            continue
        L.append('')
        L.append(f"| '{type_name(e.restype)}' ({e.resid}): {len(e.data)} bytes compiled by rezc")
        L.append(f'.macro ROMREZ_{e.symbol}')
        for k in range(0, len(e.data), 16):
            L.append('    .byte   ' + ','.join(f'0x{b:02X}' for b in e.data[k:k + 16]))
        L.append('.endm')
    return '\n'.join(L) + '\n'


# ---------------------------------------------------------------------------
# C++ output


def _cpp_char(b):
    if 0x20 <= b < 0x7F and b not in (0x22, 0x5C, 0x3F):   # " \ ?
        return chr(b)
    return '\\%03o' % b


def cpp_string(data):
    return ''.join(_cpp_char(b) for b in data)


def _comment_safe(s):
    s = ''.join(c if 0x20 <= ord(c) < 0x7F or ord(c) >= 0xA0 else '?' for c in s)
    return s.replace('*/', '*_/')


def _attr_names(attrs):
    names = [n for n, bit in sorted(_ATTR_SET.items(), key=lambda x: -x[1]) if attrs & bit]
    return ', '.join(names)


def generate_cpp(compiler, inputs):
    res_list = sorted(compiler.resources.values(), key=lambda r: (r.restype, r.resid))
    out = []
    out.append('// ResourceData.cpp -- GENERATED by tools/rez/rezc.py, do not edit.')
    out.append('//')
    out.append('// Compiled from: ' + ' '.join(os.path.basename(p) for p in inputs))
    out.append(f'// {len(res_list)} resources, {sum(len(r.data) for r in res_list)} bytes of data.')
    out.append('')
    out.append('#include "mac/ResourceTable.h"')
    out.append('')
    out.append('namespace mac::generated {')
    out.append('namespace {')
    out.append('')
    for i, r in enumerate(res_list):
        desc = f"'{type_name(r.restype)}' ({r.resid}"
        if r.name is not None:
            desc += f', "{mac_roman_to_utf8(r.name)}"'
        if r.attrs:
            desc += ', ' + _attr_names(r.attrs)
        desc += f') -- {len(r.data)} bytes'
        out.append(f'// {_comment_safe(desc)}')
        out.append(f'const uint8_t kData{i}[{len(r.data) + 1}] =')
        lines = [r.data[k:k + 24] for k in range(0, len(r.data), 24)] or [b'']
        for k, chunk in enumerate(lines):
            out.append(f'    "{cpp_string(chunk)}"' + (';' if k == len(lines) - 1 else ''))
        out.append('')
    out.append('} // namespace')
    out.append('')
    out.append('const ResEntry kResources[] = {')
    for i, r in enumerate(res_list):
        code = int.from_bytes(r.restype, 'big')
        name = 'nullptr'
        if r.name is not None:
            name = '"' + cpp_string(mac_roman_to_utf8(r.name).encode('utf-8')) + '"'
        tcomment = _comment_safe(type_name(r.restype))
        out.append(f"    {{0x{code:08X}u /* '{tcomment}' */, {r.resid}, {name}, 0x{r.attrs:02X}, "
                   f'kData{i}, {len(r.data)}}},')
    if not res_list:
        out.append('    {0, 0, nullptr, 0, nullptr, 0},')
    out.append('};')
    out.append('')
    out.append(f'const size_t kResourceCount = {len(res_list)};')
    out.append('')
    out.append('} // namespace mac::generated')
    out.append('')
    return '\n'.join(out)


def write_if_changed(path, content):
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8', newline='\n') as fp:
        fp.write(content)
    os.replace(tmp, path)


def list_resources(compiler, fp):
    for key in sorted(compiler.resources):
        r = compiler.resources[key]
        name = '' if r.name is None else f' "{mac_roman_to_utf8(r.name)}"'
        attrs = f' [{_attr_names(r.attrs)}]' if r.attrs else ''
        print(f"'{type_name(r.restype)}' {r.resid:6d}{name}{attrs}: {len(r.data)} bytes", file=fp)


def main(argv=None):
    ap = argparse.ArgumentParser(
        description='Compile Rez resource descriptions (MPW Rez language).',
        epilog='See the module docstring of tools/rez/rezc.py for the supported language.')
    ap.add_argument('inputs', nargs='*', help='Rez source files (.r)')
    ap.add_argument('--rsrc', metavar='FILE', help='write a resource fork')
    ap.add_argument('--rom-asm', metavar='FILE',
                    help='write the ROM resource fork as GNU as source (RomTypes.r)')
    ap.add_argument('--cpp', '--output', '-o', dest='cpp', metavar='FILE',
                    help='write C++ byte arrays (the Photoshop port\'s output)')
    ap.add_argument('-d', '--define', action='append', default=[], metavar='NAME[=VALUE]',
                    help='define a preprocessor macro (default value 1)')
    ap.add_argument('-u', '--undef', action='append', default=[], metavar='NAME',
                    help='undefine one of the default macros')
    ap.add_argument('-i', '--include-dir', action='append', default=[], metavar='DIR',
                    help='search DIR for #include files')
    ap.add_argument('-s', '--search-dir', action='append', default=[], metavar='DIR',
                    help='search DIR for the files of read and include statements')
    ap.add_argument('--types', action='append', metavar='FILE',
                    help='template files read first (default: Types.r and RomTypes.r '
                         'next to rezc.py)')
    ap.add_argument('--lenient', action='store_true',
                    help='skip resource statements whose type has no template')
    ap.add_argument('--rom-image', action='append', default=[], metavar='FILE',
                    help='add the resources of a ROM image (Plus/SE resource fork '
                         'layout), e.g. to --list them or write them with --rsrc')
    ap.add_argument('--list', action='store_true', help='print a summary of all resources to stdout')
    ap.add_argument('--hexdump', action='append', default=[], metavar="'TYPE'=ID",
                    help="print the data of a resource, e.g. --hexdump CURS=1")
    ap.add_argument('--verbose', '-v', action='store_true')
    args = ap.parse_args(argv)

    c = Compiler(verbose=args.verbose, include_dirs=args.include_dir,
                 search_dirs=args.search_dir, lenient=args.lenient)
    try:
        for name, value in DEFAULT_DEFINES:
            if name not in args.undef:
                c.define(name, value)
        for d in args.define:
            name, _, value = d.partition('=')
            c.define(name, value if _ else '1')
        for tf in args.types or TYPES_FILES:
            c.compile_file(tf, os.path.relpath(tf))
        c.resources.clear()         # the template files only declare types
        c.order.clear()
        for path in args.inputs:
            c.compile_file(path)
        for path in args.rom_image:
            with open(path, 'rb') as fp:
                try:
                    found, _ = read_rom_resource_fork(fp.read())
                except ValueError as e:
                    raise RezError(f'{path}: {e}')
            for r in found:
                r.where = (path, 0)
                c.add_resource(r)
        if args.rom_asm:
            write_if_changed(args.rom_asm, generate_rom_asm(c, args.inputs,
                                                            os.path.basename(args.rom_asm)))
    except RezError as e:
        print(str(e), file=sys.stderr)
        return 1
    except OSError as e:
        print(f'error: {e}', file=sys.stderr)
        return 1

    if args.list:
        list_resources(c, sys.stdout)
    for spec in args.hexdump:
        t, _, i = spec.partition('=')
        key = (t.ljust(4)[:4].encode('mac_roman'), int(i, 0))
        r = c.resources.get(key)
        if r is None:
            print(f'{spec}: no such resource', file=sys.stderr)
            continue
        print(f"'{t}' ({i}): {len(r.data)} bytes")
        for k in range(0, len(r.data), 16):
            print(f'  {k:06X}: ' + ' '.join(f'{b:02X}' for b in r.data[k:k + 16]))
    rom_layout_keys = {k for k in c.resources if k[0] in ROM_LAYOUT_TYPES}
    if args.rsrc:
        res = [c.resources[k] for k in c.order if k not in rom_layout_keys]
        tmp = args.rsrc + '.tmp'
        with open(tmp, 'wb') as fp:
            fp.write(write_resource_fork(res))
        os.replace(tmp, args.rsrc)
    if args.cpp:
        write_if_changed(args.cpp, generate_cpp(c, args.inputs))
    if args.verbose:
        print(f'{len(c.resources)} resources, {_warning_count} warnings', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
