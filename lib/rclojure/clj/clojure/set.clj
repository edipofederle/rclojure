;; clojure.set for rclojure: set operations, and relational algebra on
;; relations (sets of maps), with Clojure's semantics.

(ns clojure.set)

(defn- bigger-first [s1 s2]
  (if (< (count s1) (count s2)) [s2 s1] [s1 s2]))

(defn union
  ([] #{})
  ([s1] s1)
  ([s1 s2]
   (let [[big small] (bigger-first s1 s2)]
     (reduce conj big small)))
  ([s1 s2 & sets]
   (reduce union (union s1 s2) sets)))

(defn intersection
  ([s1] s1)
  ([s1 s2]
   (let [[big small] (bigger-first s1 s2)]
     (reduce (fn [result item] (if (contains? big item) result (disj result item)))
             small
             small)))
  ([s1 s2 & sets]
   (reduce intersection (intersection s1 s2) sets)))

(defn difference
  ([s1] s1)
  ([s1 s2]
   (if (< (count s1) (count s2))
     (reduce (fn [result item] (if (contains? s2 item) (disj result item) result))
             s1
             s1)
     (reduce disj s1 s2)))
  ([s1 s2 & sets]
   (reduce difference s1 (conj sets s2))))

(defn select [pred xset]
  (reduce (fn [s k] (if (pred k) s (disj s k))) xset xset))

(defn project [xrel ks]
  (set (map #(select-keys % ks) xrel)))

(defn rename-keys [m kmap]
  (reduce (fn [result [old new]]
            (if (contains? m old)
              (assoc result new (get m old))
              result))
          (apply dissoc m (keys kmap))
          kmap))

(defn rename [xrel kmap]
  (set (map #(rename-keys % kmap) xrel)))

(defn index [xrel ks]
  (reduce (fn [m x]
            (let [ik (select-keys x ks)]
              (assoc m ik (conj (get m ik #{}) x))))
          {}
          xrel))

(defn map-invert [m]
  (reduce (fn [result [k v]] (assoc result v k)) {} m))

(defn join
  ;; natural join, on the keys the relations' first maps have in common
  ([xrel yrel]
   (if (and (seq xrel) (seq yrel))
     (let [ks (intersection (set (keys (first xrel))) (set (keys (first yrel))))
           [r s] (if (<= (count xrel) (count yrel)) [xrel yrel] [yrel xrel])
           idx (index r ks)]
       (reduce (fn [ret x]
                 (if-let [found (idx (select-keys x ks))]
                   (reduce #(conj %1 (merge %2 x)) ret found)
                   ret))
               #{}
               s))
     #{}))
  ;; join on keys related by km (xrel's key to yrel's key)
  ([xrel yrel km]
   (let [[r s k] (if (<= (count xrel) (count yrel))
                   [xrel yrel (map-invert km)]
                   [yrel xrel km])
         idx (index r (vals k))]
     (reduce (fn [ret x]
               (if-let [found (idx (rename-keys (select-keys x (keys k)) k))]
                 (reduce #(conj %1 (merge %2 x)) ret found)
                 ret))
             #{}
             s))))

(defn subset? [set1 set2]
  (and (<= (count set1) (count set2))
       (every? #(contains? set2 %) set1)))

(defn superset? [set1 set2]
  (and (>= (count set1) (count set2))
       (every? #(contains? set1 %) set2)))
