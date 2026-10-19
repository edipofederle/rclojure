;; clojure.core, the part written in rclojure itself.
;;
;; Loaded into the clojure.core namespace when a Runtime starts, on top of
;; the Ruby primitives in lib/rclojure/core/. Order matters: until
;; `destructure` is defined below, let/loop/fn take plain symbols only.

;;; Bootstrap: defmacro, fn, defn, let

(def defmacro
  (fn* defmacro [&form &env name & decl]
    (let* [decl (if (string? (first decl)) (next decl) decl)
           sigs (if (vector? (first decl)) (list decl) decl)
           ;; every macro arity takes the implicit &form and &env first
           sigs (reduce (fn* [acc sig]
                          (conj acc (cons (apply vector '&form '&env (first sig)) (rest sig))))
                        []
                        sigs)]
      `(do (def ~name (fn* ~@sigs))
           (set-macro! (var ~name))
           (var ~name)))))
(set-macro! (var defmacro))

;; Redefined with destructuring support once `destructure` exists.
(defmacro fn [& sigs] `(fn* ~@sigs))
(defmacro let [bindings & body] `(let* ~bindings ~@body))
(defmacro loop [bindings & body] `(loop* ~bindings ~@body))

(defmacro defn [name & decl]
  (let [decl (if (string? (first decl)) (next decl) decl)
        decl (if (map? (first decl)) (next decl) decl)]
    `(def ~name (fn ~@decl))))

;; Private vars aren't supported yet; defn- is an alias for defn.
(defmacro defn- [name & decl] `(defn ~name ~@decl))

;;; Basic functions

(defn identity [x] x)
(defn second [coll] (first (next coll)))
(defn ffirst [coll] (first (first coll)))
(defn nfirst [coll] (next (first coll)))
(defn fnext [coll] (first (next coll)))
(defn nnext [coll] (next (next coll)))

(defn list*
  ([args] (seq args))
  ([a args] (cons a args))
  ([a b args] (cons a (cons b args)))
  ([a b c & more] (cons a (cons b (cons c (apply list* more))))))

(defn nthnext [coll n]
  (loop [xs (seq coll) n n]
    (if (if xs (pos? n) false)
      (recur (next xs) (dec n))
      xs)))

(defn nthrest [coll n]
  (loop [xs coll n n]
    (if (if (seq xs) (pos? n) false)
      (recur (rest xs) (dec n))
      xs)))

(defn last [coll]
  (loop [xs (seq coll)]
    (if (next xs) (recur (next xs)) (first xs))))

(defn butlast [coll]
  (loop [ret [] xs (seq coll)]
    (if (next xs)
      (recur (conj ret (first xs)) (next xs))
      (seq ret))))

;;; Control-flow macros

(defmacro when [test & body] `(if ~test (do ~@body)))
(defmacro when-not [test & body] `(if ~test nil (do ~@body)))

(defmacro if-not
  ([test then] `(if-not ~test ~then nil))
  ([test then else] `(if ~test ~else ~then)))

(defmacro and
  ([] true)
  ([x] x)
  ([x & more] `(let [and# ~x] (if and# (and ~@more) and#))))

(defmacro or
  ([] nil)
  ([x] x)
  ([x & more] `(let [or# ~x] (if or# or# (or ~@more)))))

(defmacro cond [& clauses]
  (when clauses
    (when-not (next clauses)
      (throw (ex-info "cond requires an even number of forms" {:form &form})))
    `(if ~(first clauses)
       ~(second clauses)
       (cond ~@(nnext clauses)))))

(defmacro comment [& body] nil)

(defmacro declare [& names]
  `(do ~@(reduce (fn [acc name] (conj acc (list 'def name))) [] names)))

(defmacro ->
  [x & forms]
  (loop [x x forms forms]
    (if forms
      (let [form (first forms)]
        (recur (if (seq? form) `(~(first form) ~x ~@(next form)) (list form x))
               (next forms)))
      x)))

(defmacro ->>
  [x & forms]
  (loop [x x forms forms]
    (if forms
      (let [form (first forms)]
        (recur (if (seq? form) `(~@form ~x) (list form x))
               (next forms)))
      x)))

;;; Destructuring

(declare destructure-binding)

(defn- destructure-vector [bvec b v]
  (let [gvec (gensym "vec__")]
    (loop [ret (-> bvec (conj gvec) (conj v))
           n 0
           bs (seq b)
           seen-rest? false]
      (if bs
        (let [firstb (first bs)]
          (cond
            (= firstb '&) (recur (destructure-binding ret (second bs) (list `nthnext gvec n))
                                 n
                                 (nnext bs)
                                 true)
            (= firstb :as) (destructure-binding ret (second bs) gvec)
            :else (if seen-rest?
                    (throw (ex-info "Unsupported binding form, only :as can follow & parameter" {:binding b}))
                    (recur (destructure-binding ret firstb (list `nth gvec n nil))
                           (inc n)
                           (next bs)
                           seen-rest?))))
        ret))))

;; Turns :keys/:strs/:syms entries of a map binding into {local key} pairs.
(defn- expand-key-shorthands [b]
  (reduce (fn [acc entry]
            (let [kind (first entry)
                  make-key (second entry)]
              (reduce (fn [acc k]
                        (assoc acc (symbol (name k)) (make-key k)))
                      acc
                      (get b kind))))
          (dissoc b :as :or :keys :strs :syms)
          [[:keys (fn [k] (keyword (namespace k) (name k)))]
           [:strs (fn [k] (str k))]
           [:syms (fn [k] (list 'quote k))]]))

(defn- destructure-map [bvec b v]
  (let [gmap (gensym "map__")
        defaults (get b :or)
        ret (-> bvec
                (conj gmap) (conj v)
                ;; keyword arguments: a seq is turned into a map
                (conj gmap) (conj `(if (seq? ~gmap) (apply hash-map ~gmap) ~gmap)))
        ret (if (get b :as) (-> ret (conj (get b :as)) (conj gmap)) ret)]
    (reduce (fn [ret entry]
              (let [local (key entry)
                    k (val entry)
                    lookup (if (and (symbol? local) (contains? defaults local))
                             (list `get gmap k (get defaults local))
                             (list `get gmap k))]
                (destructure-binding ret local lookup)))
            ret
            (expand-key-shorthands b))))

(defn- destructure-binding [bvec b v]
  (cond
    (symbol? b) (-> bvec (conj b) (conj v))
    (vector? b) (destructure-vector bvec b v)
    (map? b) (destructure-map bvec b v)
    :else (throw (ex-info (str "Unsupported binding form: " (pr-str b)) {:binding b}))))

;; Expands a destructuring binding vector into plain symbol/expr pairs.
(defn destructure [bindings]
  (loop [ret [] bs (seq bindings)]
    (if bs
      (recur (destructure-binding ret (first bs) (second bs)) (nnext bs))
      ret)))

(defn- check-bindings [form-name bindings]
  (when-not (vector? bindings)
    (throw (ex-info (str form-name " requires a vector for its binding") {:bindings bindings})))
  (when-not (even? (count bindings))
    (throw (ex-info (str form-name " requires an even number of forms in binding vector") {:bindings bindings}))))

(defmacro let [bindings & body]
  (check-bindings "let" bindings)
  `(let* ~(destructure bindings) ~@body))

(defmacro loop [bindings & body]
  (check-bindings "loop" bindings)
  (let [plain (destructure bindings)]
    (if (= plain bindings)
      `(loop* ~bindings ~@body)
      ;; loop over generated symbols, destructuring them inside each iteration
      (loop [bs (seq bindings) outer [] loop-binds [] inner []]
        (if bs
          (let [b (first bs)
                g (if (symbol? b) b (gensym "loop__"))]
            (recur (nnext bs)
                   (conj outer g (second bs))
                   (conj loop-binds g g)
                   (if (symbol? b) inner (conj inner b g))))
          `(let ~outer
             (loop* ~loop-binds
               (let ~inner ~@body))))))))

;; Replaces destructuring params with generated symbols bound by a let.
(defn- destructure-sig [sig]
  (let [params (first sig)
        body (rest sig)]
    (loop [ps (seq params) new-params [] lets []]
      (if ps
        (let [p (first ps)]
          (if (or (symbol? p) (= p '&))
            (recur (next ps) (conj new-params p) lets)
            (let [g (gensym "p__")]
              (recur (next ps) (conj new-params g) (conj lets p g)))))
        (if (seq lets)
          (list new-params `(let ~lets ~@body))
          sig)))))

(defmacro fn [& decl]
  (let [name (when (symbol? (first decl)) (first decl))
        decl (if name (next decl) decl)
        sigs (if (vector? (first decl)) (list decl) decl)
        sigs (reduce (fn* [acc sig] (conj acc (destructure-sig sig))) [] sigs)]
    (if name
      `(fn* ~name ~@sigs)
      `(fn* ~@sigs))))

;;; More macros

(defmacro if-let
  ([bindings then] `(if-let ~bindings ~then nil))
  ([bindings then else]
   (check-bindings "if-let" bindings)
   (let [form (first bindings) test (second bindings)]
     `(let [temp# ~test]
        (if temp# (let [~form temp#] ~then) ~else)))))

(defmacro when-let [bindings & body]
  (check-bindings "when-let" bindings)
  (let [form (first bindings) test (second bindings)]
    `(let [temp# ~test]
       (when temp# (let [~form temp#] ~@body)))))

(defmacro if-some
  ([bindings then] `(if-some ~bindings ~then nil))
  ([bindings then else]
   (check-bindings "if-some" bindings)
   (let [form (first bindings) test (second bindings)]
     `(let [temp# ~test]
        (if (nil? temp#) ~else (let [~form temp#] ~then))))))

(defmacro when-some [bindings & body]
  (check-bindings "when-some" bindings)
  (let [form (first bindings) test (second bindings)]
    `(let [temp# ~test]
       (if (nil? temp#) nil (let [~form temp#] ~@body)))))

(defmacro while [test & body]
  `(loop [] (when ~test ~@body (recur))))

(defmacro dotimes [bindings & body]
  (check-bindings "dotimes" bindings)
  (let [i (first bindings) n (second bindings)]
    `(let [n# ~n]
       (loop [~i 0]
         (when (< ~i n#) ~@body (recur (inc ~i)))))))

(defn- emit-doseq [bindings body]
  (if (seq bindings)
    (let [b (first bindings) v (second bindings) more (nnext bindings)]
      (cond
        (= b :let) `(let ~v ~(emit-doseq more body))
        (= b :when) `(when ~v ~(emit-doseq more body))
        (keyword? b) (throw (ex-info (str "Unsupported doseq modifier: " b) {:modifier b}))
        :else (let [s (gensym "seq__")]
                `(loop [~s (seq ~v)]
                   (when ~s
                     (let [~b (first ~s)] ~(emit-doseq more body))
                     (recur (next ~s)))))))
    `(do ~@body)))

(defmacro doseq [bindings & body]
  (check-bindings "doseq" bindings)
  `(do ~(emit-doseq (seq bindings) body) nil))

(defn- case-test [g test]
  (if (seq? test)
    `(or ~@(reduce (fn [acc t] (conj acc `(= ~g '~t))) [] test))
    `(= ~g '~test)))

(defmacro case [e & clauses]
  (let [g (gensym "case__")
        default (if (odd? (count clauses))
                  (last clauses)
                  `(throw (ex-info (str "No matching clause: " (pr-str ~g)) {:value ~g})))
        pairs (if (odd? (count clauses)) (butlast clauses) clauses)]
    `(let [~g ~e]
       (cond ~@(loop [ps (seq pairs) acc []]
                 (if ps
                   (recur (nnext ps) (conj acc (case-test g (first ps)) (second ps)))
                   acc))
             :else ~default))))

(defmacro condp [pred expr & clauses]
  (let [gpred (gensym "pred__") gexpr (gensym "expr__")
        emit (fn emit [clauses]
               (cond
                 (nil? clauses) `(throw (ex-info (str "No matching clause: " (pr-str ~gexpr)) {:value ~gexpr}))
                 (nil? (next clauses)) (first clauses)
                 :else `(if (~gpred ~(first clauses) ~gexpr)
                          ~(second clauses)
                          ~(emit (nnext clauses)))))]
    `(let [~gpred ~pred ~gexpr ~expr]
       ~(emit (seq clauses)))))

(defmacro assert
  ([x] `(assert ~x nil))
  ([x message]
   `(when-not ~x
      (throw (ex-info (str "Assert failed: " (let [m# ~message] (if m# (str m# "\n") "")) (pr-str '~x))
                      {:form '~x})))))

;;; Sequence functions (eager until lazy seqs land)

(defn reverse [coll] (reduce conj () coll))

(defn into
  ([] [])
  ([to] to)
  ([to from] (reduce conj to from)))

(defn every? [pred coll]
  (loop [xs (seq coll)]
    (cond
      (nil? xs) true
      (pred (first xs)) (recur (next xs))
      :else false)))

(defn some [pred coll]
  (loop [xs (seq coll)]
    (when xs
      (or (pred (first xs)) (recur (next xs))))))

(defn not-every? [pred coll] (not (every? pred coll)))
(defn not-any? [pred coll] (not (some pred coll)))
(defn not-empty [coll] (when (seq coll) coll))

(defn frequencies [coll]
  (reduce (fn [counts x] (assoc counts x (inc (get counts x 0)))) {} coll))

(defn group-by [f coll]
  (reduce (fn [groups x]
            (let [k (f x)]
              (assoc groups k (conj (get groups k []) x))))
          {}
          coll))

(defn interpose [sep coll]
  (loop [ret [] xs (seq coll)]
    (cond
      (nil? xs) (seq ret)
      (empty? ret) (recur (conj ret (first xs)) (next xs))
      :else (recur (conj ret sep (first xs)) (next xs)))))

;;; Function combinators

(defn complement [f]
  (fn [& args] (not (apply f args))))

(defn constantly [x]
  (fn [& args] x))

(defn comp
  ([] identity)
  ([f] f)
  ([f g] (fn [& args] (f (apply g args))))
  ([f g & fs]
   (reduce (fn [composed h] (comp composed h)) (comp f g) fs)))

(defn partial
  ([f] f)
  ([f & bound] (fn [& args] (apply f (concat bound args)))))

(defn juxt [& fs]
  (fn [& args]
    (reduce (fn [acc f] (conj acc (apply f args))) [] fs)))

(defn fnil [f default]
  (fn [x & args] (apply f (if (nil? x) default x) args)))

;;; Map functions

(defn merge [& maps]
  (when (some identity maps)
    (reduce (fn [acc m] (conj (or acc {}) m)) maps)))

(defn merge-with [f & maps]
  (when (some identity maps)
    (reduce (fn [acc m]
              (reduce (fn [acc entry]
                        (let [k (key entry) v (val entry)]
                          (if (contains? acc k)
                            (assoc acc k (f (get acc k) v))
                            (assoc acc k v))))
                      (or acc {})
                      m))
            maps)))

(defn select-keys [m ks]
  (reduce (fn [acc k]
            (if (contains? m k) (assoc acc k (get m k)) acc))
          {}
          ks))

(defn zipmap [ks vs]
  (loop [ret {} ks (seq ks) vs (seq vs)]
    (if (and ks vs)
      (recur (assoc ret (first ks) (first vs)) (next ks) (next vs))
      ret)))

(defn get-in
  ([m ks] (reduce get m ks))
  ([m ks not-found]
   (loop [m m ks (seq ks)]
     (if ks
       (if (contains? m (first ks))
         (recur (get m (first ks)) (next ks))
         not-found)
       m))))

(defn update [m k f & args]
  (assoc m k (apply f (get m k) args)))

(defn assoc-in [m [k & ks] v]
  (if ks
    (assoc m k (assoc-in (get m k) ks v))
    (assoc m k v)))

(defn update-in [m [k & ks] f & args]
  (if ks
    (assoc m k (apply update-in (get m k) ks f args))
    (assoc m k (apply f (get m k) args))))
