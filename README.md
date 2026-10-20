# rclojure

A Clojure dialect hosted on Ruby.

## Status

- [x] Milestone 0 — gem skeleton, REPL, test suite
- [x] Milestone 1 — reader (numbers, strings, symbols, keywords, lists, vectors, maps, sets, quote/syntax-quote/unquote/deref, comments, `#_`)
- [x] Milestone 2 — analyzer + evaluator with special forms (`def`, `if`, `do`, `let*`, `fn*`, `quote`, `var`, `loop*`/`recur`, `try`/`catch`/`finally`, `throw`)
- [x] Milestone 3 — core primitives in Ruby (collections, numbers, strings/printing, atoms, `apply`/`reduce`/`eval`)
- [x] Milestone 4 — macros, syntax-quote, destructuring, `core.clj` bootstrap (`defn`, `let`, `cond`, `->`, `doseq`, `case`, ...)
- [ ] Milestone 5 — seqs, laziness, persistent collections (*partial*: seq abstraction, `lazy-seq`, lazy seq library and `for`, linked lists; persistent vectors/maps/sets to do)
- [x] Milestone 6 — Ruby interop (method calls, constants, constructors, blocks, attributes and `set!`, `..`/`doto`, `instance?`, `clj->rb`/`rb->clj`, seqable Enumerables)
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
- Syntax-quote is expanded by the analyzer rather than the reader, so ``'`(a b)`` yields the raw `(syntax-quote (a b))` form instead of its expansion
- Floats with an `M` suffix are read as `Float`, not `BigDecimal`

**Language**
- Missing macros/forms: `letfn`, `defonce`, `defmulti`/`defmethod`, protocols and records
- `defn-` is an alias for `defn` (no private vars); `defn` skips attr-maps and ignores `{:pre :post}` conditions
- `case` is a linear chain of `=` tests (no constant-time dispatch or duplicate-constant check)
- Macros are flagged with a non-standard `set-macro!` builtin instead of `:macro` metadata; `&env` maps symbols to internal `LocalBinding` objects
- `def` discards docstrings; no metadata on vars or collections
- No dynamic vars or `binding`
- Single `user` namespace (plus `clojure.core`); no `ns`/`require` — M7
- Ruby interop:
  - Ruby collections print in Ruby format (`[1, 2]`, `{a: 1}`), and conversion is explicit (`clj->rb`/`rb->clj`); `clj->rb` turns sets into Arrays, like ClojureScript's `clj->js`
  - Ruby `Enumerable`s other than Array/Hash are seqable but not `count`able, as Java `Iterable`s aren't in Clojure (use `(count (seq x))`)
  - `set!` only works on Ruby attributes; vars need dynamic vars and `binding`
  - no type hints (they have no use on Ruby)
- `catch` takes a bare Ruby exception class name (looked up at top level, then in `RClojure`) or `:default`; no `Throwable`
- Deep non-tail recursion is limited by the Ruby stack

**Data**
- Vectors, maps and sets copy on every update (O(n)), no structural sharing — M5 (lists are linked, with O(1) `cons`/`rest`)
- No transducers: `map`, `filter`, `take`, ... have no transducer arity, and there is no `reduced`, `transduce`, `sequence` or `eduction`
- Lazy seqs are never chunked, so side effects happen one item at a time rather than 32 at a time as with Clojure's chunked seqs
- `apply` realizes its whole argument seq, so it can't take an infinite seq
- Lazy seq realization isn't synchronized, so sharing an unrealized seq between Ruby threads can run its body twice
- `str` of a lazy seq gives its contents, not Clojure's `clojure.lang.LazySeq@<hash>`
- Strings are not seqable (`(first "abc")` errors) — needs a character type
- Map entries are plain two-element vectors
- `<`/`>` use Ruby semantics, so they also compare strings instead of erroring; `compare` doesn't support collections
- Floats print in Ruby format (`1.0e+20`, not `1.0E20`)

**Performance**
- Tree-walking interpreter: a 1M-iteration `loop*` takes ~7s — M8, and see the YJIT TODO
- Every `Runtime` evaluates `core.clj` from source at startup (~90ms), which also dominates the test suite's run time

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
| other seqs | `RClojure::Cons` / `LazySeq` / `ArraySeq` (all include `RClojure::ISeq`) |
| functions | `RClojure::Fn` (rclojure) / `RClojure::Builtin` (Ruby); anything with `#call` is invocable |
| exceptions | Ruby exceptions; `ex-info` creates `RClojure::ExceptionInfo` |

## Ruby interop

```clojure
(.upcase "hello")                  ; "hello".upcase
(. "hello" (center 11 "*"))        ; the special form underneath
(.start-with? "rclojure" "rc")     ; kebab-case => start_with?
(Math/sqrt 16)                     ; Math.sqrt(16)
Math/PI                            ; Math::PI
(Time/now)  String  File::Stat     ; classes are values
(-> "  some text " .strip .upcase) ; threads through Ruby methods

(String. "abc")  (new String "abc") ; String.new("abc")
(.map [1 2 3] & inc)               ; [1, 2, 3].map(&inc): & passes the block
(Array/new 3 & (fn [i] (* i i)))   ; Array.new(3) { |i| i * i }
(.map ["a" "b"] & :upcase)         ; like Ruby's &:upcase, not a keyword lookup
(.-x point)                        ; point.x (attribute read)
(set! (.-x point) 5)               ; point.x = 5, returns 5
(.. Time (at 0) utc year)          ; Time.at(0).utc.year
(doto (Array/new) (.push 1) (.push 2))
(instance? String "a")
(clj->rb {:a [1 2]})               ; {a: [1, 2]}; rb->clj goes back
(take 3 (Range/new 1 nil))         ; Ruby Enumerables are lazily seqable
```

The value after `&` becomes the block the way Ruby's `&` does, via
`to_proc` when it has one (rclojure fns, Ruby symbols, procs, methods);
maps, sets and vectors are invoked as rclojure functions. Ruby code can
pass rclojure fns as blocks too: `xs.map(&f)`.

## Architecture

```
source ──Reader──▶ forms ──Analyzer (macroexpand)──▶ Nodes ──#eval(env)──▶ values
```

The analyzer expands macros and syntax-quote, resolves symbols to locals or
Vars, validates special forms and rejects `recur` outside tail position.
Nodes are evaluated directly for now; milestone 8 will compile them to Ruby
instead.

Seqs follow Clojure's model: anything `Seqable` has `#seq`, returning an
`ISeq` (`first`/`rest`/`next`) or nil. `List` is a counted linked list;
`seq` on vectors, sets, maps and Ruby collections gives an `ArraySeq`;
`cons` builds a `Cons`; `lazy-seq` builds a `LazySeq`. Code forms are any
`ISeq`, so macros may return conses or lazy seqs.

Ruby primitives live in `lib/rclojure/core/`, grouped as `numbers`,
`collections`, `text` (strings, symbols, keywords, printing) and `lang`
(equality, atoms, `apply`, `eval`, exceptions, macro support). Everything
that can be written in rclojure itself lives in `lib/rclojure/core.clj`, which
bootstraps `defmacro` from `fn*` and builds up `defn`, destructuring `let`/
`loop`/`fn`, the control-flow macros and collection helpers.
