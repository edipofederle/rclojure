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

;; Marks the var private with the non-standard Var#private!, since there's
;; no metadata (^:private) yet.
(defmacro defn- [name & decl]
  `(do (defn ~name ~@decl)
       (.private! (var ~name))
       (var ~name)))

;;; Lazy seqs

(defmacro lazy-seq [& body]
  `(RClojure::LazySeq/new (fn* [] ~@body)))

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

;; Ported from Clojure's doseq, without chunked-seq handling. step returns
;; [needs-recur? form]: :while and :when take over the recur themselves.
(defmacro doseq [bindings & body]
  (check-bindings "doseq" bindings)
  (let [step (fn step [recform exprs]
               (if-not exprs
                 [true `(do ~@body)]
                 (let [k (first exprs)
                       v (second exprs)]
                   (if (keyword? k)
                     (let [[needrec subform] (step recform (nnext exprs))]
                       (cond
                         (= k :let) [needrec `(let ~v ~subform)]
                         (= k :while) [false `(when ~v ~subform ~@(when needrec [recform]))]
                         (= k :when) [false `(if ~v (do ~subform ~@(when needrec [recform])) ~recform)]
                         :else (throw (ex-info (str "Invalid 'doseq' keyword " k) {:keyword k}))))
                     (let [s (gensym "seq__")
                           recform `(recur (next ~s))
                           [needrec subform] (step recform (nnext exprs))]
                       [true `(loop [~s (seq ~v)]
                                (when ~s
                                  (let [~k (first ~s)]
                                    ~subform
                                    ~@(when needrec [recform]))))])))))]
    (second (step nil (seq bindings)))))

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

;;; Eager sequence functions

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

;;; Lazy sequences
;;
;; Ported from Clojure's core.clj, minus chunked seqs and transducer
;; arities. range is backed by RClojure::RangeSeq, as Clojure's is by
;; LongRange; concat is a Ruby primitive (see core/collections.rb).

(defn dorun
  ([coll]
   (loop [s (seq coll)]
     (when s (recur (next s)))))
  ([n coll]
   (loop [n n s (seq coll)]
     (when (and s (pos? n)) (recur (dec n) (next s))))))

(defn doall
  ([coll] (dorun coll) coll)
  ([n coll] (dorun n coll) coll))

(defn map
  ([f coll]
   (lazy-seq
    (when-let [s (seq coll)]
      (cons (f (first s)) (map f (rest s))))))
  ([f c1 c2]
   (lazy-seq
    (let [s1 (seq c1) s2 (seq c2)]
      (when (and s1 s2)
        (cons (f (first s1) (first s2))
              (map f (rest s1) (rest s2)))))))
  ([f c1 c2 c3]
   (lazy-seq
    (let [s1 (seq c1) s2 (seq c2) s3 (seq c3)]
      (when (and s1 s2 s3)
        (cons (f (first s1) (first s2) (first s3))
              (map f (rest s1) (rest s2) (rest s3)))))))
  ([f c1 c2 c3 & colls]
   (let [step (fn step [cs]
                (lazy-seq
                 (let [ss (map seq cs)]
                   (when (every? identity ss)
                     (cons (map first ss) (step (map rest ss)))))))]
     (map (fn [args] (apply f args)) (step (conj colls c3 c2 c1))))))

(defn mapcat [f & colls]
  (apply concat (apply map f colls)))

(defn filter [pred coll]
  (lazy-seq
   (when-let [s (seq coll)]
     (let [f (first s) r (rest s)]
       (if (pred f)
         (cons f (filter pred r))
         (filter pred r))))))

(defn remove [pred coll]
  (filter (complement pred) coll))

(defn keep [f coll]
  (lazy-seq
   (when-let [s (seq coll)]
     (let [x (f (first s))]
       (if (nil? x)
         (keep f (rest s))
         (cons x (keep f (rest s))))))))

(defn map-indexed [f coll]
  (let [mapi (fn mapi [idx coll]
               (lazy-seq
                (when-let [s (seq coll)]
                  (cons (f idx (first s)) (mapi (inc idx) (rest s))))))]
    (mapi 0 coll)))

(defn mapv
  ([f coll] (reduce (fn [v x] (conj v (f x))) [] coll))
  ([f c1 c2 & colls] (into [] (apply map f c1 c2 colls))))

(defn filterv [pred coll]
  (reduce (fn [v x] (if (pred x) (conj v x) v)) [] coll))

(defn take [n coll]
  (lazy-seq
   (when (pos? n)
     (when-let [s (seq coll)]
       (cons (first s) (take (dec n) (rest s)))))))

(defn take-while [pred coll]
  (lazy-seq
   (when-let [s (seq coll)]
     (when (pred (first s))
       (cons (first s) (take-while pred (rest s)))))))

(defn drop [n coll]
  (let [step (fn [n coll]
               (let [s (seq coll)]
                 (if (and (pos? n) s)
                   (recur (dec n) (rest s))
                   s)))]
    (lazy-seq (step n coll))))

(defn drop-while [pred coll]
  (let [step (fn [pred coll]
               (let [s (seq coll)]
                 (if (and s (pred (first s)))
                   (recur pred (rest s))
                   s)))]
    (lazy-seq (step pred coll))))

(defn take-nth [n coll]
  (lazy-seq
   (when-let [s (seq coll)]
     (cons (first s) (take-nth n (drop n s))))))

(defn take-last [n coll]
  (loop [s (seq coll) lead (seq (drop n coll))]
    (if lead
      (recur (next s) (next lead))
      s)))

(defn drop-last
  ([coll] (drop-last 1 coll))
  ([n coll] (map (fn [x _] x) coll (drop n coll))))

(defn split-at [n coll]
  [(take n coll) (drop n coll)])

(defn split-with [pred coll]
  [(take-while pred coll) (drop-while pred coll)])

(defn repeat
  ([x] (lazy-seq (cons x (repeat x))))
  ([n x] (take n (repeat x))))

(defn repeatedly
  ([f] (lazy-seq (cons (f) (repeatedly f))))
  ([n f] (take n (repeatedly f))))

(defn iterate [f x]
  (cons x (lazy-seq (iterate f (f x)))))

(defn cycle [coll]
  (lazy-seq
   (when-let [s (seq coll)]
     (concat s (cycle s)))))

(defn range
  ([] (iterate inc 0))
  ([end] (range 0 end 1))
  ([start end] (range start end 1))
  ([start end step]
   (cond
     (not (zero? step)) (or (RClojure::RangeSeq/create start end step) ())
     (= start end) ()
     :else (repeat start))))

(defn interleave
  ([] ())
  ([c1] (lazy-seq c1))
  ([c1 c2]
   (lazy-seq
    (let [s1 (seq c1) s2 (seq c2)]
      (when (and s1 s2)
        (cons (first s1) (cons (first s2) (interleave (rest s1) (rest s2))))))))
  ([c1 c2 & colls]
   (lazy-seq
    (let [ss (map seq (conj colls c2 c1))]
      (when (every? identity ss)
        (concat (map first ss) (apply interleave (map rest ss))))))))

(defn interpose [sep coll]
  (drop 1 (interleave (repeat sep) coll)))

(defn partition
  ([n coll] (partition n n coll))
  ([n step coll]
   (lazy-seq
    (when-let [s (seq coll)]
      (let [p (doall (take n s))]
        (when (= n (count p))
          (cons p (partition n step (nthrest s step))))))))
  ([n step pad coll]
   (lazy-seq
    (when-let [s (seq coll)]
      (let [p (doall (take n s))]
        (if (= n (count p))
          (cons p (partition n step pad (nthrest s step)))
          (list (take n (concat p pad)))))))))

(defn partition-all
  ([n coll] (partition-all n n coll))
  ([n step coll]
   (lazy-seq
    (when-let [s (seq coll)]
      (let [seg (doall (take n s))]
        (cons seg (partition-all n step (nthrest s step))))))))

(defn distinct [coll]
  (let [step (fn step [xs seen]
               (lazy-seq
                ((fn [[f :as xs] seen]
                   (when-let [s (seq xs)]
                     (if (contains? seen f)
                       (recur (rest s) seen)
                       (cons f (step (rest s) (conj seen f))))))
                 xs seen)))]
    (step coll #{})))

(defmacro lazy-cat [& colls]
  `(concat ~@(map (fn [c] (list `lazy-seq c)) colls)))

;; Ported from Clojure's for, without the chunked-seq fast path. Each
;; binding becomes a fn walking its seq; inner bindings are concatenated.
(defmacro for [seq-exprs body-expr]
  (check-bindings "for" seq-exprs)
  (let [to-groups (fn [seq-exprs]
                    (reduce (fn [groups [k v]]
                              (if (keyword? k)
                                (conj (pop groups) (conj (peek groups) [k v]))
                                (conj groups [k v])))
                            [] (partition 2 seq-exprs)))
        emit-bind (fn emit-bind [[[bind expr & mod-pairs]
                                  & [[_ next-expr] :as next-groups]]]
                    (let [giter (gensym "iter__")
                          gxs (gensym "s__")
                          do-mod (fn do-mod [[[k v] & etc]]
                                   (cond
                                     (= k :let) `(let ~v ~(do-mod etc))
                                     (= k :while) `(when ~v ~(do-mod etc))
                                     (= k :when) `(if ~v
                                                    ~(do-mod etc)
                                                    (recur (rest ~gxs)))
                                     (keyword? k) (throw (ex-info (str "Invalid 'for' keyword " k) {:keyword k}))
                                     next-groups
                                     `(let [iterys# ~(emit-bind next-groups)
                                            fs# (seq (iterys# ~next-expr))]
                                        (if fs#
                                          (concat fs# (~giter (rest ~gxs)))
                                          (recur (rest ~gxs))))
                                     :else `(cons ~body-expr
                                                  (~giter (rest ~gxs)))))]
                      `(fn ~giter [~gxs]
                         (lazy-seq
                          (loop [~gxs ~gxs]
                            (when-let [~gxs (seq ~gxs)]
                              (let [~bind (first ~gxs)]
                                ~(do-mod mod-pairs))))))))]
    `(let [iter# ~(emit-bind (to-groups seq-exprs))]
       (iter# ~(second seq-exprs)))))

;;; Ruby interop

(defmacro ..
  ([x form] `(. ~x ~form))
  ([x form & more] `(.. (. ~x ~form) ~@more)))

(defmacro doto [x & forms]
  (let [gx (gensym)]
    `(let [~gx ~x]
       ~@(map (fn [f]
                (if (seq? f)
                  `(~(first f) ~gx ~@(next f))
                  `(~f ~gx)))
              forms)
       ~gx)))

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

;;; Namespaces and libs
;;
;; Ported from Clojure's core.clj. Libs are found on the Runtime's load
;; path. *loaded-libs* and *pending-paths* are atoms, since rclojure has no
;; refs or dynamic vars; :verbose is accepted but ignored, and :reload-all
;; reloads only the named lib, like :reload.

;; clojure.core counts as loaded: it isn't on the load path to be found.
(def *loaded-libs* (atom #{'clojure.core}))
(.private! (var *loaded-libs*))
(def *pending-paths* (atom ()))
(.private! (var *pending-paths*))

(defn loaded-libs [] @*loaded-libs*)

(defmacro refer-clojure [& filters]
  `(clojure.core/refer '~'clojure.core ~@filters))

(defmacro ns [name & references]
  (let [process-reference (fn [[kname & args]]
                            `(~(symbol "clojure.core" (clojure.core/name kname))
                              ~@(map (fn [arg] (list 'quote arg)) args)))
        references (if (string? (first references)) (next references) references)
        references (if (map? (first references)) (next references) references)
        references (remove (fn [r] (= :gen-class (first r))) references)]
    `(do
       (clojure.core/in-ns '~name)
       ~@(when (and (not= name 'clojure.core)
                    (not-any? (fn [r] (= :refer-clojure (first r))) references))
           `((clojure.core/refer '~'clojure.core)))
       ~@(map process-reference references)
       (if (= '~name 'clojure.core)
         nil
         (do (swap! (deref (var *loaded-libs*)) conj '~name) nil)))))

(defn- throw-if [pred & message]
  (when pred
    (throw (ex-info (apply str message) {}))))

(defn- libspec? [x]
  (or (symbol? x)
      (and (vector? x)
           (or (nil? (second x))
               (keyword? (second x))))))

(defn- prependss [x coll]
  (if (symbol? x) (cons x coll) (concat x coll)))

(defn- root-resource [lib]
  (str "/" (-> (name lib) (.tr "-" "_") (.tr "." "/"))))

(defn- root-directory [lib]
  (let [d (root-resource lib)]
    (subs d 0 (.rindex d "/"))))

(defn- check-cyclic-dependency [path]
  (when (some #{path} (rest @*pending-paths*))
    (let [pending (map (fn [p] (if (= p path) (str "[ " p " ]") p))
                       (cons path @*pending-paths*))
          chain (apply str (interpose "->" pending))]
      (throw-if true "Cyclic load dependency: " chain))))

(defn load [& paths]
  (doseq [path paths]
    (let [path (if (.start-with? path "/")
                 path
                 (str (root-directory (ns-name *ns*)) "/" path))]
      (check-cyclic-dependency path)
      (when-not (= path (first @*pending-paths*))
        (swap! *pending-paths* conj path)
        (try
          (load-resource (subs path 1))
          (finally (swap! *pending-paths* rest)))))))

(defn- load-one [lib need-ns require]
  (load (root-resource lib))
  (throw-if (and need-ns (not (find-ns lib)))
            "namespace '" lib "' not found after loading '" (root-resource lib) "'")
  (when require
    (swap! *loaded-libs* conj lib)))

(defn- load-lib [prefix lib & options]
  (throw-if (and prefix (.include? (name lib) "."))
            "Found lib name '" (name lib) "' containing period with prefix '" prefix
            "'.  lib names inside prefix lists must not contain periods")
  (let [lib (if prefix (symbol (str prefix "." lib)) lib)
        opts (apply hash-map options)
        {:keys [as reload reload-all require use as-alias]} opts
        loaded (contains? @*loaded-libs* lib)
        need-ns (or as use)
        load (cond reload-all load-one
                   reload load-one
                   (not loaded) (cond need-ns load-one
                                      as-alias (fn [lib _need _require] (create-ns lib))
                                      :else load-one))
        filter-opts (select-keys opts [:exclude :only :rename :refer])
        undefined-on-entry (not (find-ns lib))]
    (if load
      (try
        (load lib need-ns require)
        (catch :default e
          (when undefined-on-entry
            (remove-ns lib))
          (throw e)))
      (throw-if (and need-ns (not (find-ns lib)))
                "namespace '" lib "' not found"))
    (when as
      (alias as lib))
    (when as-alias
      (alias as-alias lib))
    (when (or use (:refer filter-opts))
      (apply refer lib (mapcat seq filter-opts)))))

(defn- load-libs [& args]
  (let [flags (filter keyword? args)
        opts (interleave flags (repeat true))
        args (filter (complement keyword?) args)
        supported #{:as :reload :reload-all :require :use :verbose :refer :as-alias}
        unsupported (seq (remove supported flags))]
    (throw-if unsupported
              (apply str "Unsupported option(s) supplied: " (interpose "," unsupported)))
    (throw-if (not (seq args)) "Nothing specified to load")
    (doseq [arg args]
      (if (libspec? arg)
        (apply load-lib nil (prependss arg opts))
        (let [[prefix & args] arg]
          (throw-if (nil? prefix) "prefix cannot be nil")
          (doseq [arg args]
            (apply load-lib prefix (prependss arg opts))))))))

(defn require [& args]
  (apply load-libs :require args))

(defn use [& args]
  (apply load-libs :require :use args))
