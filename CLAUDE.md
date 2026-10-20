# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

rclojure is a Clojure dialect hosted on Ruby: a tree-walking interpreter (Ruby 3.3+, `.ruby-version` pins 3.4.8). Plain Ruby, no runtime dependencies; tests use minitest.

## Commands

```sh
bundle install
bundle exec rake                                       # full test suite
bundle exec ruby -Ilib -Itest test/test_core.rb        # one test file
bundle exec ruby -Ilib -Itest test/test_core.rb -n test_numbers    # one test
bundle exec ruby -Ilib -Itest test/test_core.rb -n /destructur/    # tests matching a regex
bin/rclj                                               # REPL
bin/rclj file.clj                                      # run a file
ruby -Ilib -e 'require "rclojure"; p RClojure::Runtime.new.eval_string("(+ 1 2)")'
```

There is no linter configured.

## Architecture

```
source ──Reader──▶ forms ──Analyzer (macroexpand)──▶ Nodes ──#eval(env)──▶ values
```

- **Reader** (`reader.rb`) produces forms made of the Ruby value mapping in the README (keywords are Ruby `Symbol`s, Clojure symbols are `RClojure::Symbol`, collections are `RClojure::List/Vector/Map/Set` in `types.rb`; `List.from(array)` builds a list). Syntax-quote is *not* expanded by the reader: it emits `(syntax-quote x)`, which the analyzer expands via `SyntaxQuote` (`syntax_quote.rb`).
- **Analyzer** (`analyzer.rb`) is the compile step: it macroexpands (macros, syntax-quote, and interop shorthands like `(.foo x)` / `(Math/sqrt x)` → the `.` special form), resolves symbols to `LocalBinding`s or `Var`s at analysis time, validates special forms (`SPECIAL_FORMS`), and rejects `recur` outside tail position. A `Scope` struct carries visible locals and the current recur arity.
- **Nodes** (`nodes.rb`) are Structs with `#eval(env)`. `Env` is a frame chain keyed by `LocalBinding` identity (not names), so shadowing is resolved by the analyzer. `recur` *returns* a `Nodes::Recur` value (it is not raised); `Loop` and `Fn#call` loop on it, creating a fresh frame per iteration so closures keep captured values. Milestone 8 plans to compile Nodes to Ruby instead of evaluating them.
- **Runtime** (`runtime.rb`) owns namespaces. Each `Runtime.new` installs Ruby primitives into `clojure.core`, then evaluates `core.clj` from source (~90ms — this dominates test time), then switches to a `user` namespace that refers core. Runtimes are fully independent; tests create one per test in `setup`.
- **Interop** (`analyzer.rb` `analyze_dot`/`analyze_new`/`analyze_set!`, `host.rb`): shorthands `(.m x)`, `(.-attr x)`, `(Foo. x)`, `(Foo/m x)` macroexpand to the `.`/`new` special forms, after macros (as in Clojure, so `..` is a macro). `& f` at the end of a host call's args passes `f` as the Ruby block via `Host.block`; `set!` compiles host attribute targets into a call to the `attr=` setter.
- **Invocation**: anything responding to `#call` is a function (`RClojure.invoke` in `core.rb`); keywords look themselves up. `Fn` (`fn.rb`) is an rclojure closure with arity dispatch; `Builtin` wraps a Ruby lambda.

### Where to add language features

- Ruby primitives go in `lib/rclojure/core/{numbers,collections,text,lang,interop}.rb`, registered with `define.("name", ->(...) { ... })` inside each module's `install`. Shared helpers (`RClojure.items`, `seq`, `equiv?`, `truthy?`, `get`) live in `core.rb`.
- Anything expressible in rclojure goes in `lib/rclojure/core.clj`. **Order matters there**: it bootstraps `defmacro` from `fn*`, and `fn`/`let`/`loop` are plain-symbol versions until `destructure` is defined, after which they're redefined with destructuring.
- Macros are flagged via the non-standard `set-macro!` builtin (no metadata support yet); macro fns take implicit `&form` and `&env` first.
- `=` must use `RClojure.equiv?` semantics: integers/ratios never equal floats, recursively in collections.
- Seqs mirror Clojure's interfaces as Ruby modules in `types.rb`: `Seqable` (has `#seq` → ISeq or nil), `Sequential` (equality walks seqs, like `ASeq.equiv`) and `ISeq` (`first`/`rest`/`next`). `List` is a counted linked list; `Cons`, `ArraySeq` and `LazySeq` each have a file in `seqs/`. Code forms are any `ISeq`, so check `is_a?(ISeq)`, not `List`, when inspecting forms. Ruby-side helpers in `core.rb`: `RClojure.seq/first/rest/next/cons`, `each_item` (walks lazily) and `items` (realizes everything into an Array; avoid it where laziness matters).
- `lazy-seq` is `(RClojure::LazySeq/new (fn* [] ...))`, mirroring Clojure's `(new clojure.lang.LazySeq ...)`. The seq library (`map`, `filter`, `for`, ...) is ported from Clojure's `core.clj` without chunking or transducer arities. Two exceptions live in Ruby: `concat` (in `core/collections.rb`, because syntax-quote expansions call it before `lazy-seq` exists) and `range`, backed by `RangeSeq` (Clojure uses the Java `LongRange` class). Vectors, maps and sets are still immutable wrappers over frozen Ruby collections (copy on update).

## Tests

`test/test_helper.rb` provides `EvalTestHelpers` (`ev(source)`, `assert_ev(expected, source)` against a fresh Runtime) and `RClojureTestHelpers` (`read`, `sym`). Test files are grouped by layer: reader, printer, eval (special forms), core, macros, interop.

## Conventions

- Before implementing a language feature, check how Clojure and ClojureScript do it: clones live in `~/dev/clojure-ref/clojure` (`src/clj/clojure/core.clj`, `src/jvm/clojure/lang/*.java`) and `~/dev/clojure-ref/clojurescript` (`src/main/cljs/cljs/core.cljs`, macros in `src/main/clojure/cljs/core.cljc`). Port ideas rather than copying large chunks (Clojure is EPL, this gem is MIT).

- The README "Known limitations" section must be kept current: add an entry whenever a deliberate gap vs. Clojure is introduced, and remove it when closed. Also update the milestone checklist in the README when a milestone progresses.
