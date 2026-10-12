"""Reading and writing the Lua files WoW uses for SavedVariables and Verdicts.lua."""

from __future__ import annotations

import re
from pathlib import Path

# ---------------------------------------------------------------------------
# Reading SavedVariables (a small Lua table literal parser)
# ---------------------------------------------------------------------------
NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUM_RE = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
           "\\": "\\", '"': '"', "'": "'"}


class LuaParser:
    """Parses the files WoW writes: `Name = <value>` lines of literal tables.

    The text is decoded as Latin-1 so every byte maps to one character; strings
    are re-decoded as UTF-8 once their escapes are resolved.
    """

    def __init__(self, text: str):
        self.s = text
        self.i = 0

    def error(self, what: str) -> ValueError:
        line = self.s.count("\n", 0, self.i) + 1
        return ValueError(f"{what} at line {line}")

    def skip(self) -> None:
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif s.startswith("--[[", self.i):
                end = s.find("]]", self.i + 4)
                self.i = len(s) if end < 0 else end + 2
            elif s.startswith("--", self.i):
                end = s.find("\n", self.i)
                self.i = len(s) if end < 0 else end + 1
            else:
                break

    def peek(self) -> str:
        self.skip()
        return self.s[self.i] if self.i < len(self.s) else ""

    def expect(self, ch: str) -> None:
        if self.peek() != ch:
            raise self.error(f"expected {ch!r}")
        self.i += 1

    def assignments(self) -> dict:
        result = {}
        while self.peek():
            m = NAME_RE.match(self.s, self.i)
            if not m:
                raise self.error("expected a variable name")
            self.i = m.end()
            self.expect("=")
            result[m.group()] = self.value()
        return result

    def value(self):
        c = self.peek()
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        m = NUM_RE.match(self.s, self.i)
        if m:
            self.i = m.end()
            text = m.group()
            return float(text) if any(ch in text for ch in ".eE") else int(text)
        m = NAME_RE.match(self.s, self.i)
        if m and m.group() in ("true", "false", "nil"):
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}[m.group()]
        raise self.error("unexpected value")

    def string(self) -> str:
        s, quote = self.s, self.s[self.i]
        self.i += 1
        out = []
        while True:
            if self.i >= len(s):
                raise self.error("unterminated string")
            c = s[self.i]
            if c == quote:
                self.i += 1
                break
            if c != "\\":
                out.append(c)
                self.i += 1
                continue
            n = s[self.i + 1]
            if n in ESCAPES:
                out.append(ESCAPES[n])
                self.i += 2
            elif n.isdigit():
                digits = re.match(r"\d{1,3}", s[self.i + 1:self.i + 4]).group()
                out.append(chr(int(digits) & 0xFF))
                self.i += 1 + len(digits)
            elif n == "\r" and s[self.i + 2:self.i + 3] == "\n":
                out.append("\n")
                self.i += 3
            else:
                out.append(n)
                self.i += 2
        return "".join(out).encode("latin-1").decode("utf-8", errors="replace")

    def table(self):
        self.expect("{")
        result, n = {}, 1
        while self.peek() != "}":
            if self.peek() == "[":
                self.i += 1
                key = self.value()
                self.expect("]")
                self.expect("=")
                result[key] = self.value()
            else:
                m = NAME_RE.match(self.s, self.i)
                after = m and self.s[m.end():].lstrip(" \t\r\n")
                if m and after.startswith("=") and not after.startswith("=="):
                    self.i = m.end()
                    self.expect("=")
                    result[m.group()] = self.value()
                else:
                    result[n] = self.value()
                    n += 1
            if self.peek() in (",", ";"):
                self.i += 1
        self.expect("}")
        return result


def read_lua_file(path: Path) -> dict:
    return LuaParser(path.read_bytes().decode("latin-1")).assignments()


def as_list(t) -> list:
    """Lua arrays come back as {1: a, 2: b}; turn them into [a, b]."""
    if isinstance(t, list):
        return t
    if not isinstance(t, dict):
        return []
    return [t[k] for k in sorted(k for k in t if isinstance(k, int))]


def as_dict(t) -> dict:
    return t if isinstance(t, dict) else {}


# ---------------------------------------------------------------------------
# Writing Verdicts.lua
# ---------------------------------------------------------------------------
def lua_string(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_value(v, indent: int = 0) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_string(v)
    pad, inner = "    " * indent, "    " * (indent + 1)
    if isinstance(v, list):
        items = [f"{inner}{lua_value(x, indent + 1)}," for x in v]
    else:
        items = [f"{inner}[{lua_value(k)}] = {lua_value(x, indent + 1)},"
                 for k, x in sorted(v.items(), key=lambda kv: str(kv[0])) if x is not None]
    if not items:
        return "{}"
    return "{\n" + "\n".join(items) + "\n" + pad + "}"

