(ns greeter.core
  (:require [clojure.string :as str]
            ["json"]))

(defn greet [name]
  (str "Hello, " (str/capitalize name) "!"))

(defn report
  "Counts the words in text; Ruby's (helpers/stopword? w) filters them."
  [text]
  (->> (str/split (str/lower-case text) #"\W+")
       (remove helpers/stopword?)
       frequencies
       (sort-by val >)
       (take 3)))

(defn to-json [data]
  (JSON/generate (clj->rb data)))
