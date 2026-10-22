;; clojure.string for rclojure: Clojure's API, implemented with Ruby's
;; String methods. Where Ruby and Java behave differently (splitting,
;; replacement strings, what counts as whitespace), the Java behaviour is
;; ported in RClojure::StringSupport. Characters are one-character strings.

(ns clojure.string
  (:refer-clojure :exclude [replace reverse]))

(defn reverse [s] (.reverse s))

(defn re-quote-replacement [replacement]
  (RClojure::StringSupport/quote-replacement (str replacement)))

(defn replace [s match replacement]
  (RClojure::StringSupport/replace s match replacement))

(defn replace-first [s match replacement]
  (RClojure::StringSupport/replace s match replacement true))

(defn join
  ([coll] (apply str coll))
  ([separator coll] (apply str (interpose separator coll))))

(defn capitalize [s]
  (if (< (count s) 2)
    (.upcase s)
    (str (.upcase (subs s 0 1)) (.downcase (subs s 1)))))

(defn upper-case [s] (.upcase s))

(defn lower-case [s] (.downcase s))

(defn split
  ([s re] (RClojure::StringSupport/split s re))
  ([s re limit] (RClojure::StringSupport/split s re limit)))

(defn split-lines [s] (split s #"\r?\n"))

(defn trim [s] (RClojure::StringSupport/trim s))

(defn triml [s] (RClojure::StringSupport/triml s))

(defn trimr [s] (RClojure::StringSupport/trimr s))

(defn trim-newline [s] (.sub s #"[\r\n]+\z" ""))

(defn blank? [s] (RClojure::StringSupport/blank? s))

(defn escape [s cmap]
  (apply str (map (fn [ch] (if-let [replacement (cmap ch)] replacement ch)) s)))

(defn index-of
  ([s value] (.index s value))
  ([s value from-index] (.index s value (max from-index 0))))

(defn last-index-of
  ([s value] (.rindex s value))
  ([s value from-index] (when-not (neg? from-index) (.rindex s value from-index))))

(defn starts-with? [s substr] (.start-with? s substr))

(defn ends-with? [s substr] (.end-with? s substr))

(defn includes? [s substr] (.include? s substr))
