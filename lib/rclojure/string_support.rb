module RClojure
  # Host helpers for clojure.string (lib/rclojure/clj/clojure/string.clj),
  # where Clojure's version calls Java's String, Pattern and Matcher:
  # their semantics differ from Ruby's in places, so they're ported here.
  module StringSupport
    # Java's Character.isWhitespace (unlike Ruby's \s or strip, it
    # excludes no-break spaces and includes the information separators).
    WHITESPACE = "[ \\t\\n\\u000B\\f\\r\\u001C-\\u001F\\u1680\\u2000-\\u2006\\u2008-\\u200A\\u2028\\u2029\\u205F\\u3000]".freeze
    LEADING_WHITESPACE = /\A#{WHITESPACE}+/
    TRAILING_WHITESPACE = /#{WHITESPACE}+\z/
    BLANK = /\A#{WHITESPACE}*\z/

    module_function

    def trim(s)
      triml(trimr(s))
    end

    def triml(s)
      s.sub(LEADING_WHITESPACE, "")
    end

    def trimr(s)
      s.sub(TRAILING_WHITESPACE, "")
    end

    def blank?(s)
      s.nil? || BLANK.match?(s)
    end

    # Java's Pattern.split: unlike Ruby's String#split, capture groups
    # aren't included. A zero-width match at the start makes no leading
    # empty string; limit > 0 caps the parts, and limit 0 drops trailing
    # empty strings.
    def split(s, re, limit = 0)
      parts = []
      index = 0
      each_match(re, s) do |match|
        if limit <= 0 || parts.size < limit - 1
          next if index.zero? && match.begin(0).zero? && match.end(0).zero?

          parts << s[index...match.begin(0)]
          index = match.end(0)
        elsif parts.size == limit - 1
          break
        end
      end
      return Vector[s] if index.zero?

      parts << s[index..]
      parts.pop while limit.zero? && parts.last&.empty?
      Vector.new(parts)
    end

    # Each match of re in s, moving on a character after an empty match,
    # as Java's Matcher.find does.
    def each_match(re, s)
      pos = 0
      while pos <= s.length && (match = re.match(s, pos))
        yield match
        pos = match.end(0) == match.begin(0) ? match.end(0) + 1 : match.end(0)
      end
    end

    # replace / replace-first: literal for string and char matches; for a
    # regex, replacement is a Java-style replacement string ($1, ${name},
    # \ escapes) or a fn of the match (see re-groups), used literally.
    def replace(s, match, replacement, first = false)
      method = first ? :sub : :gsub
      case match
      when ::String then s.public_send(method, match) { replacement }
      when Regexp
        s.public_send(method, match) do
          found = Regexp.last_match
          if replacement.is_a?(::String)
            expand_replacement(replacement, found)
          else
            Printer.str(RClojure.invoke(replacement, [Core::Text.re_groups(found)]))
          end
        end
      else raise ArgumentError, "Invalid match arg: #{Printer.pr_str(match)}"
      end
    end

    # Matcher.appendReplacement's syntax: $n and ${name} are groups, a
    # backslash makes the next character literal. As in Java, $12 means
    # group 12 only if there is one, else group 1 followed by "2".
    def expand_replacement(replacement, match)
      result = +""
      i = 0
      while i < replacement.length
        char = replacement[i]
        if char == "\\"
          result << replacement[i + 1].to_s
          i += 2
        elsif char == "$" && replacement[i + 1] == "{"
          close = replacement.index("}", i) or raise ArgumentError, "named capturing group is missing trailing '}'"
          result << match[replacement[(i + 2)...close]].to_s
          i = close + 1
        elsif char == "$"
          digits = replacement[(i + 1)..][/\A\d+/] or raise ArgumentError, "Illegal group reference"
          group = digits[0].to_i
          digits[1..].each_char do |digit|
            break if group * 10 + digit.to_i >= match.size

            group = group * 10 + digit.to_i
          end
          raise IndexError, "No group #{group}" if group >= match.size

          result << match[group].to_s
          i += 1 + group.to_s.length
        else
          result << char
          i += 1
        end
      end
      result
    end

    # Matcher.quoteReplacement: makes a replacement string literal.
    def quote_replacement(s)
      s.gsub(/[\\$]/) { |char| "\\#{char}" }
    end
  end
end
