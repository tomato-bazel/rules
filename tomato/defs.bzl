"""tomato-bazel convention macros.

`tomato_mdbook` — a brand-themed mdBook in one call: wraps rules_mdbook's
`mdbook_book` and stages `@brand//mdbook:theme` at the book's `theme/` dir, so
every docs site is branded by construction (the generalized form of the
genrule + mdbook_book pattern fastverk/docs uses inline).
"""

load("@rules_mdbook//mdbook:defs.bzl", "mdbook_book")

# The @brand//mdbook:theme files (by basename) and where each lands under the
# book's theme/. The theme is `additional-css`-only (it must NOT ship a
# variables.css — that replaces mdBook's default + drops its layout vars). If
# brand adds/removes a theme file, update this map.
_BRAND_THEME = {
    "custom.css": "theme/css/custom.css",
    "fonts.css": "theme/fonts/fonts.css",
    "SpaceGrotesk-Medium.ttf": "theme/fonts/SpaceGrotesk-Medium.ttf",
    "SpaceGrotesk-SemiBold.ttf": "theme/fonts/SpaceGrotesk-SemiBold.ttf",
    "head.hbs": "theme/head.hbs",
    "favicon.svg": "theme/favicon.svg",
}

def tomato_mdbook(name, book_toml = "book.toml", srcs = None, theme = "@brand//mdbook:theme", out = None, **kwargs):
    """A brand-themed mdBook.

    Args:
      name: the mdbook_book target name.
      book_toml: the book.toml (default "book.toml").
      srcs: markdown + assets; default globs src/**/*.md.
      theme: the brand theme filegroup (default @brand//mdbook:theme).
      out: output tarball name (default "<name>.tar.gz").
      **kwargs: forwarded to mdbook_book (e.g. plugins).

    One tomato_mdbook per package (the staged theme/ paths are fixed).
    """
    if srcs == None:
        srcs = native.glob(["src/**/*.md"])
    if out == None:
        out = name + ".tar.gz"

    theme_target = "_{}_brand_theme".format(name)
    cmd = ["mkdir -p \"$(RULEDIR)/theme/css\" \"$(RULEDIR)/theme/fonts\"", "for f in $(SRCS); do", "  case \"$$(basename \"$$f\")\" in"]
    for base, dest in _BRAND_THEME.items():
        cmd.append("    {}) cp \"$$f\" \"$(RULEDIR)/{}\" ;;".format(base, dest))
    cmd += ["  esac", "done"]

    native.genrule(
        name = theme_target,
        srcs = [theme],
        outs = _BRAND_THEME.values(),
        cmd = "\n".join(cmd),
    )

    mdbook_book(
        name = name,
        book_toml = book_toml,
        srcs = srcs + [":" + theme_target],
        out = out,
        **kwargs
    )

# Back-compat alias (deprecated; prefer tomato_mdbook).
fastverk_mdbook = tomato_mdbook
