# rclojure

A Clojure dialect hosted on Ruby.

## Status

- [x] Milestone 0 — gem skeleton, REPL, test suite
- [x] Milestone 1 — reader (numbers, strings, symbols, keywords, lists, vectors, maps, sets, quote/syntax-quote/unquote/deref, comments, `#_`)
- [ ] Milestone 2 — evaluator with special forms (`def`, `if`, `do`, `let*`, `fn*`, `quote`, `loop*`/`recur`, `try`/`throw`)
- [ ] Milestone 3 — core functions
- [ ] Milestone 4 — macros + `core.clj` bootstrap
- [ ] Milestone 5 — seqs, laziness, persistent collections
- [ ] Milestone 6 — Ruby interop
- [ ] Milestone 7 — namespaces
- [ ] Milestone 8 — compile to Ruby

## Usage

```sh
bundle install
bin/rclj          # REPL (currently read + print only)
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
