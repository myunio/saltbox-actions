module Saltbox
  module Actions
    # find_action's search: the actions someone may use, ranked by the plain
    # words of a request against each action's title, name and description.
    # Titles and descriptions are written in people's words, so "log my hours"
    # or "mark it done" finds the right action without knowing its name.
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

        rarity = terms.to_h { |term| [term, rarity(term)] }
        @actions.map { |action| [action, score(action, terms, rarity)] }
          .select { |_, score| score.positive? }
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

      def score(action, terms, rarity)
        words = @words.fetch(action)
        terms.sum do |term|
          rarity.fetch(term) * WEIGHTS.sum { |field, weight| (words.fetch(field).any? { |word| matches?(word, term) }) ? weight : 0 }
        end
      end

      # A word few actions use says more than one most of them use ("comment"
      # against "card").
      def rarity(term)
        used = @words.count { |_, fields| fields.values.any? { |words| words.any? { |word| matches?(word, term) } } }
        Math.log(1 + @actions.size.to_f / (1 + used))
      end

      # Exactly, or by a shared start of four letters or more ("comment" and "comments").
      def matches?(word, term)
        return true if word == term
        shorter, longer = (word.length <= term.length) ? [word, term] : [term, word]
        shorter.length >= 4 && longer.start_with?(shorter)
      end
    end
  end
end
