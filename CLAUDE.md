# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

rclojure is a Clojure dialect hosted on Ruby, compiling each form to Ruby source (CRuby 3.3+, `.ruby-version` pins 3.4.8). Plain Ruby, no runtime dependencies; tests use minitest.

## Commands

```sh
bundle install
bundle exec rake                                       # full test suite
RCLOJURE_CACHE_DIR= bundle exec rake                   # ... without the core cache (much slower)
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
source ──Reader──▶ forms ──Analyzer (macroexpand)──▶ Nodes ──Compiler──▶ Ruby source ──RubyVM::InstructionSequence──▶ values
```

- **Reader** (`reader.rb`) produces forms made of the Ruby value mapping in the README (keywords are Ruby `Symbol`s, Clojure symbols are `RClojure::Symbol`, collections are `RClojure::List/Vector/Map/Set` in `types.rb`; `List.from(array)` builds a list). Syntax-quote is *not* expanded by the reader: it emits `(syntax-quote x)`, which the analyzer expands via `SyntaxQuote` (`syntax_quote.rb`).
- **Analyzer** (`analyzer.rb`) is the compile step: it macroexpands (macros, syntax-quote, and interop shorthands like `(.foo x)` / `(Math/sqrt x)` → the `.` special form), resolves symbols to `LocalBinding`s or `Var`s at analysis time, validates special forms (`SPECIAL_FORMS`), and rejects `recur` outside tail position. A `Scope` struct carries visible locals and the current recur arity.
- **Nodes** (`nodes.rb`) are plain Structs: the AST. Locals are `LocalBinding` objects (identity, not names), so shadowing is resolved by the analyzer.
- **Compiler** (`compiler.rb`, modeled on ClojureScript's `compiler.cljc`) turns a top-level node into the source of a Ruby lambda `->(k) { ... }`, where `k` is an array of constants (Vars, quoted data, classes, strings); `Compiler.run` compiles it with `RubyVM::InstructionSequence` and calls it. Each `LocalBinding` becomes a uniquely named Ruby local (`l_<name>__<n>`). Ruby's truthiness is Clojure's, so `if` is a ternary. `loop*`, and fn methods whose body recurs, become `while true` with tail positions compiled by `tail` (`break value`; `recur` assigns temps, then the locals, then `next`). The trap: Ruby closures capture variables, and loops reassign them. Like ClojureScript, a fn created inside a loop that uses the loop's locals (or names itself) is wrapped in an immediately-called lambda binding their current values (`compile_fn`); `test_compiler.rb` covers this. Calls with ≤ 3 args compile to `RClojure.invokeN`, which calls `Fn#callN`/`Builtin#callN` (like Clojure's `IFn.invoke` overloads) to avoid splatting. A `Builtin` can be given fixed-arity fast paths for a variadic impl (`Core.define(ns, name, impl, { 2 => ->(x, y) {...} })`); hot operators (`+ - * < > <= >= =`) have them.
- **Runtime** (`runtime.rb`) owns namespaces. Each `Runtime.new` installs Ruby primitives into `clojure.core`, then loads `core.clj`, then switches to a `user` namespace that refers core. `Runtime#eval` unrolls a top-level `do` (like Clojure's `Compiler.eval`) so `ns`/`in-ns` take effect before later subforms are analyzed. Runtimes are fully independent; tests create one per test in `setup`.
- **Core cache** (`core_cache.rb`): loading `core.clj` from source takes ~160ms (reading, analysis and compiling to Ruby). The first `Runtime` records each top-level form's compiled `[source, constants]`, joins the sources into one lambda, and stores its `InstructionSequence#to_binary` plus the `Marshal`ed constants in `core-<digest>.bin`; later Runtimes load the bytecode and run it (~5ms). The digest covers every file under `lib/rclojure` plus the Ruby version, revision and platform, so editing the analyzer, compiler or `core.clj` invalidates it automatically. Vars are dumped by name and re-interned into the loading Runtime (`Var._dump`/`_load`); value types define `marshal_dump`/`marshal_load` so they come back frozen. A constant Marshal can't dump (a proc, say) in core's compiled code makes the cache silently fall back to source loading, so new value types that can appear as constants need marshal support. `test_helper.rb` points `RCLOJURE_CACHE_DIR` at a temp dir; an empty value disables the cache. Code that runs while core loads must not depend on analysis-time side effects other than interning vars and the gensym counter, which the cache restores.
- **Interop** (`analyzer.rb` `analyze_dot`/`analyze_new`/`analyze_set!`, `host.rb`): shorthands `(.m x)`, `(.-attr x)`, `(Foo. x)`, `(Foo/m x)` macroexpand to the `.`/`new` special forms, after macros (as in Clojure, so `..` is a macro). `& f` at the end of a host call's args passes `f` as the Ruby block via `Host.block`; `set!` compiles host attribute targets into a call to the `attr=` setter.
- **Namespaces** follow Clojure's model: a `Namespace` has `mappings` (name → Var, its own and referred ones, copied at `refer` time) and `aliases`; `clojure.core/*ns*` holds the current one (a plain var: `in-ns` sets its root, `Runtime#load_file` restores it). Primitives operating on namespaces are in `core/namespaces.rb`; `ns`, `require`, `use` and `load` are ported to `core.clj`. `require` searches `Runtime#load_path` (`RCLOJURE_PATH`). The reader resolves `::kw` through a callback into the runtime, so read and eval one form at a time (`Runtime#eval_string`, the REPL) rather than reading a whole buffer up front.
- **Invocation**: anything responding to `#call` is a function (`RClojure.invoke` in `core.rb`); keywords look themselves up. `Fn` (`fn.rb`) holds a compiled lambda per fixed arity plus an optional variadic one (taking the required args, then the rest as a seq or nil); `Builtin` wraps a Ruby lambda.
- **Adding a special form** means an analyzer method producing a node, and `Compiler#expr` (plus `#tail` if it can hold a tail position) emitting Ruby for it.

### Where to add language features

- Characters are one-character frozen Strings, as in ClojureScript (the reader turns `\a` into `"a"`); `RClojure.seq` on a String gives an `ArraySeq` of them.
- rclojure's own libs (`clojure.string`, `clojure.set`) live in `lib/rclojure/clj/`, which `Runtime#load_resource` searches after the load path (`Runtime::BUILTIN_SOURCES`, like the Clojure jar on the classpath). Where Clojure's version calls Java, they call Ruby helpers through interop; Java semantics Ruby lacks (`Pattern.split`, `$1` replacement strings, `Character.isWhitespace`) are ported in `string_support.rb`.
- Ruby primitives go in `lib/rclojure/core/{numbers,collections,text,lang,interop,namespaces}.rb`, registered with `define.("name", ->(...) { ... })` inside each module's `install`. Shared helpers (`RClojure.items`, `seq`, `equiv?`, `truthy?`, `get`) live in `core.rb`.
- Anything expressible in rclojure goes in `lib/rclojure/core.clj`. **Order matters there**: it bootstraps `defmacro` from `fn*`, and `fn`/`let`/`loop` are plain-symbol versions until `destructure` is defined, after which they're redefined with destructuring.
- Macros are flagged via the non-standard `set-macro!` builtin (no metadata support yet); macro fns take implicit `&form` and `&env` first.
- `=` must use `RClojure.equiv?` semantics: integers/ratios never equal floats, recursively in collections.
- Seqs mirror Clojure's interfaces as Ruby modules in `types.rb`: `Seqable` (has `#seq` → ISeq or nil), `Sequential` (equality walks seqs, like `ASeq.equiv`) and `ISeq` (`first`/`rest`/`next`). `List` is a counted linked list; `Cons`, `ArraySeq` and `LazySeq` each have a file in `seqs/`. Code forms are any `ISeq`, so check `is_a?(ISeq)`, not `List`, when inspecting forms. Ruby-side helpers in `core.rb`: `RClojure.seq/first/rest/next/cons`, `each_item` (walks lazily) and `items` (realizes everything into an Array; avoid it where laziness matters).
- `lazy-seq` is `(RClojure::LazySeq/new (fn* [] ...))`, mirroring Clojure's `(new clojure.lang.LazySeq ...)`. The seq library (`map`, `filter`, `for`, ...) is ported from Clojure's `core.clj` without chunking or transducer arities. Two exceptions live in Ruby: `concat` (in `core/collections.rb`, because syntax-quote expansions call it before `lazy-seq` exists) and `range`, backed by `RangeSeq` (Clojure uses the Java `LongRange` class). Vectors, maps and sets (`collections/`) are ported from Clojure's `PersistentVector` (trie + tail; nodes are frozen Arrays holding only the children present, so Clojure's "null out a slot" becomes dropping the last element), `PersistentArrayMap` (≤ 8 entries: a frozen Ruby Hash) and `PersistentHashMap` (`HashTrie`: bitmap-indexed and collision nodes, no `ArrayNode`). `test_collections.rb` checks them against Ruby Array/Hash at trie boundaries and asserts a vector's trie always equals what `Vector.new(items)` builds, which catches stale leaves that results alone wouldn't show.

## Tests

`test/test_helper.rb` provides `EvalTestHelpers` (`ev(source)`, `assert_ev(expected, source)` against a fresh Runtime) and `RClojureTestHelpers` (`read`, `sym`). Test files are grouped by layer: reader, printer, eval (special forms), compiler, core, macros, seqs, collections, everyday (chars, regexes, sorting, letfn, `clojure.string`/`clojure.set`), interop, namespaces, core cache. `test_namespaces.rb` gives each test a Runtime whose load path is a temp dir, and writes lib files into it.

## Conventions

- Before implementing a language feature, check how Clojure and ClojureScript do it: clones live in `~/dev/clojure-ref/clojure` (`src/clj/clojure/core.clj`, `src/jvm/clojure/lang/*.java`) and `~/dev/clojure-ref/clojurescript` (`src/main/cljs/cljs/core.cljs`, macros in `src/main/clojure/cljs/core.cljc`). Port ideas rather than copying large chunks (Clojure is EPL, this gem is MIT).

- The README "Known limitations" section must be kept current: add an entry whenever a deliberate gap vs. Clojure is introduced, and remove it when closed. Also update the milestone checklist in the README when a milestone progresses.
