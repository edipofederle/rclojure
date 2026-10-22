# rclojure

A Clojure dialect hosted on Ruby.

## Status

- [x] Milestone 0 — gem skeleton, REPL, test suite
- [x] Milestone 1 — reader (numbers, strings, symbols, keywords, lists, vectors, maps, sets, quote/syntax-quote/unquote/deref, comments, `#_`)
- [x] Milestone 2 — analyzer + evaluator with special forms (`def`, `if`, `do`, `let*`, `fn*`, `quote`, `var`, `loop*`/`recur`, `try`/`catch`/`finally`, `throw`)
- [x] Milestone 3 — core primitives in Ruby (collections, numbers, strings/printing, atoms, `apply`/`reduce`/`eval`)
- [x] Milestone 4 — macros, syntax-quote, destructuring, `core.clj` bootstrap (`defn`, `let`, `cond`, `->`, `doseq`, `case`, ...)
- [x] Milestone 5 — seqs, laziness, persistent collections (seq abstraction, `lazy-seq`, lazy seq library and `for`, persistent lists, vectors, maps and sets)
- [x] Milestone 6 — Ruby interop (method calls, constants, constructors, blocks, attributes and `set!`, `..`/`doto`, `instance?`, `clj->rb`/`rb->clj`, seqable Enumerables)
- [x] Milestone 7 — namespaces (`ns`, `require`/`use`/`load`, aliases, `refer` filters, private vars, `::kw`, `ns-*` introspection)
- [x] Milestone 8 — compile to Ruby

## TODO

- [x] Benchmark with YJIT: CI's `yjit` job times a 1M-iteration `loop*` in its run summary. On GitHub's runners it took 3.50s without YJIT and 1.90s with it under the tree-walking interpreter, and takes 0.27s and 0.13s compiled (M8). To try it locally, rebuild Ruby with YJIT (`sudo apt install rustc && rvm reinstall 3.4.8`, check with `ruby --yjit -v`) and run with `RUBY_YJIT_ENABLE=1`

## Known limitations

Gaps compared to Clojure, with the milestone expected to address each.
Keep this list current: add an entry whenever a deliberate gap is
introduced, and remove it when the gap is closed.

**Reader**
- Characters are one-character strings, as in ClojureScript: `\a` reads as `"a"`, so `(= \a "a")` is true and `(pr-str \a)` gives `"a"`
- The reader doesn't add `:line`/`:column` metadata, and type hints (`^String`) are kept as `:tag` metadata but otherwise ignored
- No tagged literals (`#inst`, `#uuid`)
- Regexes are Ruby `Regexp`s, so `#"..."` uses Ruby's regex syntax (close to Java's, but not identical); there's no `re-matcher` or `re-groups`, as Ruby has no matcher objects to pass around
- Syntax-quote is expanded by the analyzer rather than the reader, so ``'`(a b)`` yields the raw `(syntax-quote (a b))` form instead of its expansion
- Floats with an `M` suffix are read as `Float`, not `BigDecimal`

**Language**
- No protocols, types or records (`defprotocol`, `deftype`, `defrecord`, `reify`)
- `defn` ignores `{:pre :post}` conditions
- `case` is a linear chain of `=` tests (no constant-time dispatch or duplicate-constant check)
- `&env` maps symbols to internal `LocalBinding` objects
- Dynamic bindings aren't conveyed to other threads (there are no futures or agents): a Ruby `Thread` started inside `binding` sees root values
- No validators or watches on vars and atoms
- Namespaces:
  - `ns` has no `:import` (Ruby constants are always reachable by name)
  - `require` only loads `.clj` files (no `.cljc`), `:reload-all` reloads just the named lib like `:reload`, and `:verbose` is ignored
- Ruby interop:
  - Ruby collections print in Ruby format (`[1, 2]`, `{a: 1}`), and conversion is explicit (`clj->rb`/`rb->clj`); `clj->rb` turns sets into Arrays, like ClojureScript's `clj->js`
  - Ruby `Enumerable`s other than Array/Hash are seqable but not `count`able, as Java `Iterable`s aren't in Clojure (use `(count (seq x))`)
  - no type hints (they have no use on Ruby)
- `catch` takes a bare Ruby exception class name (looked up at top level, then in `RClojure`) or `:default`; no `Throwable`
- Deep non-tail recursion is limited by the Ruby stack

**Data**
- No transients (`transient`, `persistent!`, `conj!`, ...), sorted collections (`sorted-map`, `sorted-set`) or `subvec`
- Maps with more than 8 entries iterate in hash order, like Clojure's hash maps, but Ruby seeds `String` and `Symbol` hashes per process, so that order (and how such maps print) can change between runs
- No transducers: `map`, `filter`, `take`, ... have no transducer arity, and there is no `reduced`, `transduce`, `sequence` or `eduction`
- Lazy seqs are never chunked, so side effects happen one item at a time rather than 32 at a time as with Clojure's chunked seqs
- `apply` realizes its whole argument seq, so it can't take an infinite seq
- Lazy seq realization isn't synchronized, so sharing an unrealized seq between Ruby threads can run its body twice
- `str` of a lazy seq gives its contents, not Clojure's `clojure.lang.LazySeq@<hash>`
- Map entries are plain two-element vectors
- `<`/`>` use Ruby semantics, so they also compare strings instead of erroring
- Floats print in Ruby format (`1.0e+20`, not `1.0E20`)

**Performance**
- A 1M-iteration `loop*` takes ~0.27s on CI, ~0.13s with YJIT (`RUBY_YJIT_ENABLE=1`); the tree-walking interpreter M8 replaced took 3.50s and 1.90s
- Compiling uses `RubyVM::InstructionSequence`, so rclojure needs CRuby (not JRuby or TruffleRuby)
- Ruby backtraces from rclojure code point into the generated Ruby (`(rclojure)`), not at rclojure source lines
- Loading `core.clj` from source takes ~160ms, so its compiled form is cached (see Usage) and later `Runtime`s start in ~5ms; the cache is per rclojure version, so checkouts sharing a cache directory replace each other's cache

## Usage

Requires Ruby 3.3+ (the repo pins 3.4.8 in `.ruby-version`).

```sh
bundle install
bin/rclj          # REPL
bin/rclj file.clj # run a file
bundle exec rake  # run tests
```

The first `Runtime` writes a cache of `core.clj` compiled to Ruby bytecode
to `~/.cache/rclojure` (or `$XDG_CACHE_HOME/rclojure`) so later ones skip
reading, macroexpanding and compiling it. Set `RCLOJURE_CACHE_DIR` to use another
directory, or to an empty value to turn the cache off. The cache is
keyed by a digest of rclojure's sources, so changes invalidate it.

## Namespaces

rclojure ships `clojure.string` and `clojure.set`: `(require '[clojure.string :as str])`.

`require` finds `my-app.util` in `my_app/util.clj` under one of the
directories on the load path: `RCLOJURE_PATH` (separated like `PATH`),
or the current directory when unset.

```clojure
(ns my-app.core
  (:require [my-app.util :as u :refer [shout]]))

(defn- helper [] ::done) ; private; ::done is :my-app.core/done
(u/whisper (shout "hi"))
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
(isa? Integer Numeric)             ; classes and modules work in hierarchies,
(defmulti kind class)              ; so multimethods can dispatch on them
(clj->rb {:a [1 2]})               ; {a: [1, 2]}; rb->clj goes back
(take 3 (Range/new 1 nil))         ; Ruby Enumerables are lazily seqable
```

The value after `&` becomes the block the way Ruby's `&` does, via
`to_proc` when it has one (rclojure fns, Ruby symbols, procs, methods);
maps, sets and vectors are invoked as rclojure functions. Ruby code can
pass rclojure fns as blocks too: `xs.map(&f)`.

## Architecture

```
source ──Reader──▶ forms ──Analyzer (macroexpand)──▶ Nodes ──Compiler──▶ Ruby source ──▶ values
```

The analyzer expands macros and syntax-quote, resolves symbols to locals or
Vars, validates special forms and rejects `recur` outside tail position.
The compiler, modeled on ClojureScript's, turns each top-level form's nodes
into the source of a Ruby lambda and runs it through
`RubyVM::InstructionSequence`, so YJIT can compile rclojure code like any
other Ruby. Locals become Ruby locals, `if` a Ruby conditional (the two
languages agree on truthiness), and `loop`/`recur` a `while` loop; fns
created in a loop that close over its locals are wrapped so each keeps the
values of its own iteration.

Seqs follow Clojure's model: anything `Seqable` has `#seq`, returning an
`ISeq` (`first`/`rest`/`next`) or nil. `List` is a counted linked list;
`seq` on a vector walks its trie leaves (`VectorSeq`), and on sets, maps
and Ruby collections gives an `ArraySeq`;
`cons` builds a `Cons`; `lazy-seq` builds a `LazySeq`. Code forms are any
`ISeq`, so macros may return conses or lazy seqs.

Collections are persistent, ported from Clojure (`lib/rclojure/collections/`):
vectors are a 32-way trie plus a tail, like `PersistentVector`; maps of up
to 8 entries are frozen Ruby Hashes copied on write (like
`PersistentArrayMap`, keeping insertion order), and larger ones a hash
array mapped trie (like `PersistentHashMap`); sets wrap a map. Keys are
compared like Ruby Hash keys, with `hash` and `eql?`.

Ruby primitives live in `lib/rclojure/core/`, grouped as `numbers`,
`collections`, `text` (strings, symbols, keywords, printing) and `lang`
(equality, atoms, `apply`, `eval`, exceptions, macro support). Everything
that can be written in rclojure itself lives in `lib/rclojure/core.clj`, which
bootstraps `defmacro` from `fn*` and builds up `defn`, destructuring `let`/
`loop`/`fn`, the control-flow macros and collection helpers.
