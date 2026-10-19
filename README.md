# rclojure

A Clojure dialect hosted on Ruby.

## Status

- [x] Milestone 0 — gem skeleton, REPL, test suite
- [x] Milestone 1 — reader (numbers, strings, symbols, keywords, lists, vectors, maps, sets, quote/syntax-quote/unquote/deref, comments, `#_`)
- [x] Milestone 2 — analyzer + evaluator with special forms (`def`, `if`, `do`, `let*`, `fn*`, `quote`, `var`, `loop*`/`recur`, `try`/`catch`/`finally`, `throw`)
- [ ] Milestone 3 — core functions
- [ ] Milestone 4 — macros + `core.clj` bootstrap
- [ ] Milestone 5 — seqs, laziness, persistent collections
- [ ] Milestone 6 — Ruby interop
- [ ] Milestone 7 — namespaces
- [ ] Milestone 8 — compile to Ruby

## TODO

- [ ] Rebuild the local Ruby with YJIT (`sudo apt install rustc && rvm reinstall 3.4.8`, check with `ruby --yjit -v`) and benchmark the interpreter with `RUBY_YJIT_ENABLE=1`; a 1M-iteration `loop*` currently takes ~7s without it

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

Primitives in `lib/rclojure/core.rb`: `+ - * / < > <= >= = not= ex-info ex-data ex-message`.
