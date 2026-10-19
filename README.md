# rclojure

A Clojure dialect hosted on Ruby.

## Status

- [x] Milestone 0 — gem skeleton, REPL, test suite
- [x] Milestone 1 — reader (numbers, strings, symbols, keywords, lists, vectors, maps, sets, quote/syntax-quote/unquote/deref, comments, `#_`)
- [x] Milestone 2 — analyzer + evaluator with special forms (`def`, `if`, `do`, `let*`, `fn*`, `quote`, `var`, `loop*`/`recur`, `try`/`catch`/`finally`, `throw`)
- [x] Milestone 3 — core primitives in Ruby (collections, numbers, strings/printing, atoms, `apply`/`reduce`/`eval`)
- [ ] Milestone 4 — macros + `core.clj` bootstrap
- [ ] Milestone 5 — seqs, laziness, persistent collections
- [ ] Milestone 6 — Ruby interop
- [ ] Milestone 7 — namespaces
- [ ] Milestone 8 — compile to Ruby

## TODO

- [ ] Rebuild the local Ruby with YJIT (`sudo apt install rustc && rvm reinstall 3.4.8`, check with `ruby --yjit -v`) and benchmark the interpreter with `RUBY_YJIT_ENABLE=1`; a 1M-iteration `loop*` currently takes ~7s without it

## Known limitations

Gaps compared to Clojure, with the milestone expected to address each.
Keep this list current: add an entry whenever a deliberate gap is
introduced, and remove it when the gap is closed.

**Reader**
- No character literals (`\a`, `\newline`) — no character type yet
- No metadata (`^{:doc ...}`, `^String`)
- No `#()` anonymous functions, `#'x` var quote, `#"regex"`, `::auto-resolved` keywords or tagged literals (`#inst`)
- Syntax-quote is read as a `(syntax-quote ...)` form and not yet expanded — M4
- Floats with an `M` suffix are read as `Float`, not `BigDecimal`

**Language**
- No macros, so no `defn`, `when`, `cond`, `and`/`or`, `->`, `let`/`fn` (only `let*`/`fn*`) — M4
- No destructuring — M4
- `def` discards docstrings; no metadata on vars or collections
- No dynamic vars or `binding`
- Single `user` namespace (plus `clojure.core`); no `ns`/`require` — M7
- No Ruby interop (`.method`, `Class/new`) — M6
- `catch` takes a bare Ruby exception class name (looked up at top level, then in `RClojure`) or `:default`; no `Throwable`
- Deep non-tail recursion is limited by the Ruby stack

**Data**
- Collections copy on every update (O(n)), no structural sharing — M5
- No lazy seqs; seq functions are eager, and `map`/`filter`/`range`/`take` don't exist yet — M5
- Strings are not seqable (`(first "abc")` errors) — needs a character type
- Map entries are plain two-element vectors
- `<`/`>` use Ruby semantics, so they also compare strings instead of erroring; `compare` doesn't support collections
- Floats print in Ruby format (`1.0e+20`, not `1.0E20`)

**Performance**
- Tree-walking interpreter: a 1M-iteration `loop*` takes ~7s — M8, and see the YJIT TODO

## Usage

Requires Ruby 3.3+ (the repo pins 3.4.8 in `.ruby-version`).

```sh
bundle install
bin/rclj          # REPL
bin/rclj file.clj # run a file
bundle exec rake  # run tests
```

## Value mapping

| Clojure | Ruby |
|---|---|
| `nil` / `true` / `false` | `nil` / `true` / `false` |
| integers, `N` bigints | `Integer` |
| `1/2` | `Rational` |
| floats | `Float` |
| strings | frozen `String` |
| keywords `:foo` | `Symbol` |
| symbols `foo` | `RClojure::Symbol` |
| `()` `[]` `{}` `#{}` | `RClojure::List` / `Vector` / `Map` / `Set` |
| functions | `RClojure::Fn` (rclojure) / `RClojure::Builtin` (Ruby); anything with `#call` is invocable |
| exceptions | Ruby exceptions; `ex-info` creates `RClojure::ExceptionInfo` |

## Architecture

```
source ──Reader──▶ forms ──Analyzer──▶ Nodes ──#eval(env)──▶ values
```

The analyzer resolves symbols to locals or Vars, validates special forms and
rejects `recur` outside tail position. Nodes are evaluated directly for now;
milestone 8 will compile them to Ruby instead.

Ruby primitives live in `lib/rclojure/core/`, grouped as `numbers`,
`collections`, `text` (strings, symbols, keywords, printing) and `lang`
(equality, atoms, `apply`, `eval`, exceptions). Functions that are easy to
write in rclojure itself will go in `core.clj` once macros exist.
