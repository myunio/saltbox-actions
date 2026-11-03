module Saltbox
  module Actions
    # find_action's search: the actions someone may use, ranked by the plain
    # words of a request against each action's title, name and description.
    # Titles and descriptions are written in people's words, so "log my hours"
    # or "mark it done" finds the right action without knowing its name.
    #
    # A match counts only when it hits the action's title or name, or its
    # description holds at least two of the request's words, carrying at least
    # half the weight of the words any action uses. A request for something
    # the app does not do then finds nothing, rather than an action whose
    # description happens to share one word with it; a word no action uses,
    # such as a person's name, neither helps nor hurts.
    # @api private
    class Finder
      # Words that carry no meaning for choosing an action.
      STOP_WORDS = %w[a an and any are as at be by can could do does for from get give have how i in is it me my of on or our please show some that the this to up was we what when where which who will with would you your].to_set.freeze
      WEIGHTS = {title: 4, name: 3, description: 1}.freeze
      LIMIT = 8

      # @param actions [Array<Class>]
      def initialize(actions)
        @actions = actions
        @words = actions.to_h do |action|
          fields = {title: action.title, name: action.action_name.tr("_", " "), description: action.description}
          [action, fields.transform_values { |text| self.class.terms(text).to_set }]
        end
      end

      # @param query [String]
      # @param limit [Integer]
      # @return [Array<Class>] matching actions in rank order
      def find(query, limit: LIMIT)
        terms = self.class.terms(query)
        return [] if terms.empty?

        used = terms.to_h { |term| [term, @actions.count { uses?(it, term) }] }
        rarity = used.transform_values { |count| rarity(count) }
        known = terms.select { |term| used.fetch(term).positive? }
        @actions.select { |action| relevant?(action, terms, rarity, known) }
          .map { |action| [action, score(action, terms, rarity)] }
          .sort_by { |action, score| [-score, action.action_name] }
          .first(limit).map(&:first)
      end

      # @param text [String]
      # @return [Array<String>] meaningful search terms
      def self.terms(text)
        text.to_s.downcase.scan(/[a-z0-9]+/).reject { |word| STOP_WORDS.include?(word) }.map { |word| stem(word) }.uniq
      end

      # Enough stemming that "timers", "types" and "boxes" meet "timer", "type"
      # and "box": "es" comes off only after the sounds that need it.
      # @param word [String]
      # @return [String] normalized word form
      def self.stem(word)
        return word if word.length <= 3
        word.sub(/ies\z/, "y").sub(/(ing|ed|(?<=ss|[xz]|ch|sh)es|s)\z/, "").then { |stem| (stem.length >= 3) ? stem : word }
      end

      private

      # Whether some term is in the title or name, or at least two are in the
      # description and they carry at least half the weight of the terms some
      # action uses. "say why the meeting was called off" finds cancel_event
      # through "say" and "why"; "say hello" does not find whoami through
      # "say" alone.
      def relevant?(action, terms, rarity, known)
        found = terms.select { |term| uses?(action, term) }
        return false if found.empty?
        words = @words.fetch(action)
        return true if found.any? { |term| (words.fetch(:title) | words.fetch(:name)).any? { |word| matches?(word, term) } }
        found.size >= 2 && found.sum { rarity.fetch(it) } * 2 >= known.sum { rarity.fetch(it) }
      end

      def uses?(action, term) = @words.fetch(action).values.any? { |field| field.any? { |word| matches?(word, term) } }

      def score(action, terms, rarity)
        words = @words.fetch(action)
        terms.sum do |term|
          rarity.fetch(term) * WEIGHTS.sum { |field, weight| (words.fetch(field).any? { |word| matches?(word, term) }) ? weight : 0 }
        end
      end

      # A word few actions use says more than one most of them use ("comment"
      # against "card").
      def rarity(used) = Math.log(1 + @actions.size.to_f / (1 + used))

      # Exactly, or by a shared start of four letters or more ("comment" and "comments").
      def matches?(word, term)
        return true if word == term
        shorter, longer = (word.length <= term.length) ? [word, term] : [term, word]
        shorter.length >= 4 && longer.start_with?(shorter)
      end
    end
  end
end
