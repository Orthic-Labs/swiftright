"""Blank out comments and string-literal text in Swift source, keeping every offset.

String interpolation `\\( ... )` stays as code.  Raw strings (#"..."#) and multi-line
strings are handled.  This is a lexical pass, not a parser.
"""


def strip(src):
    out = list(src)
    n = len(src)
    i = 0
    # stack of ("str", hashes, multiline) frames and ("interp", paren_depth) frames
    stack = []

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        top = stack[-1] if stack else None
        if top and top[0] == "str":
            _, hashes, multi = top
            closer = ('"""' if multi else '"') + "#" * hashes
            esc = "\\" + "#" * hashes
            if src.startswith(esc + "(", i):
                blank(i, i + len(esc) + 1)
                stack.append(("interp", 1))
                i += len(esc) + 1
                continue
            if src.startswith(esc, i):
                blank(i, i + len(esc) + 1)
                i += len(esc) + 1
                continue
            if src.startswith(closer, i):
                blank(i, i + len(closer))
                stack.pop()
                i += len(closer)
                continue
            if not multi and src[i] == "\n":      # unterminated: recover
                stack.pop()
                continue
            blank(i, i + 1)
            i += 1
            continue
        # code context (top-level or interpolation)
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            blank(i, j)
            i = j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1
                    j += 2
                elif src.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            blank(i, j)
            i = j
            continue
        h = 0
        j = i
        while j < n and src[j] == "#":
            h += 1
            j += 1
        if j < n and src[j] == '"' and (h > 0 or True):
            if src.startswith('"""', j):
                blank(i, j + 3)
                stack.append(("str", h, True))
                i = j + 3
            else:
                blank(i, j + 1)
                stack.append(("str", h, False))
                i = j + 1
            continue
        if top and top[0] == "interp":
            if c == "(":
                stack[-1] = ("interp", top[1] + 1)
            elif c == ")":
                if top[1] == 1:
                    stack.pop()
                    blank(i, i + 1)
                    i += 1
                    continue
                stack[-1] = ("interp", top[1] - 1)
        i += 1
    return "".join(out)


if __name__ == "__main__":
    t = 'let a = "x \\(foo(1)) y" // c\nlet b = """\n z\n"""\nText("hi").frame(width: 1)'
    print(strip(t))
