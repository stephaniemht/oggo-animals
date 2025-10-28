# app/services/professions/suggest_merges_service.rb
require "set"

module Professions
  class SuggestMergesService
    STOPWORDS = %w[
      a au aux de des du le la les l d en et ou avec sans hors sur sous pour par
      toutes tous toute tout specialite specialites specialitees specialitee
      medecin medecins metier metiers profession professions
    ].freeze

    # Racines proposées systématiquement (familles clés)
    FORCED_ROOTS = %w[
      mecanicien
      dentiste
      radiologue
    ].freeze

    DEFAULT_MIN_ROOT_FREQ = 3

    # min_root_freq: fréquence min d’apparition d’un token pour être racine candidate
    # forced_roots:  racines ajoutées d’office (pour les familles importantes)
    def initialize(min_group_size: 2, min_token_len: 6, limit_groups: 100, min_root_freq: DEFAULT_MIN_ROOT_FREQ, forced_roots: FORCED_ROOTS)
      @min_group_size = min_group_size
      @min_token_len  = min_token_len
      @limit_groups   = limit_groups
      @min_root_freq  = min_root_freq
      @forced_roots   = forced_roots
    end

    # Retourne des groupes: { token:, size:, target:, members: [Profession,…] }
    def call
      profs = Profession
                .joins(:profession_mappings)
                .distinct
                .select(:id, :name, :name_norm)

      # 1) Tokenisation + fréquence des tokens
      tokens_cache = {}          # { profession_id => [tokens...] }
      token_freq   = Hash.new(0) # { "token" => count }

      profs.find_each(batch_size: 1000) do |p|
        toks = tokens_for(p.name_norm)
        tokens_cache[p.id] = toks
        toks.each { |t| token_freq[t] += 1 }
      end

      # 2) Racines candidates = tokens fréquents + racines forcées (+ leur stem)
      roots = token_freq.keys.select { |t| t.length >= @min_token_len && token_freq[t] >= @min_root_freq }

      forced = @forced_roots.dup
      forced_stems = @forced_roots.map { |r| stem(r) }
      forced |= forced_stems # ex: "dentiste" + "dentist"

      roots |= forced

      # 3) Index des groupes (Set pour éviter les doublons)
      index = Hash.new { |h, k| h[k] = Set.new }

      profs.find_each(batch_size: 1000) do |p|
        toks = tokens_cache[p.id] || []

        # a) groupe par tokens “classiques”
        toks.each { |t| index[t] << p }

        # b) groupe par racine: par token OU par sous-chaîne dans le libellé normalisé
        roots.each do |r|
          r_stem = stem(r)
          if toks.any? { |t| t.include?(r) || t.include?(r_stem) } ||
             p.name_norm.include?(r) || p.name_norm.include?(r_stem)
            index[r] << p
          end
        end
      end

      # 4) Construire les groupes finaux (cible = libellé le plus court)
      groups = []
      index.each do |tok, set|
        arr = set.to_a
        next if arr.size < @min_group_size
        target = arr.min_by { |pr| [pr.name.length, pr.name] }
        groups << { token: tok, size: arr.size, target: target, members: arr }
      end

      groups.sort_by { |g| [-g[:size], g[:token]] }.first(@limit_groups)
    end

    private

    def tokens_for(norm)
      return [] if norm.blank?

      words = norm.split(/\s+/)
                  .map { |w| w.gsub(/[^a-z0-9]/, "") }
                  .reject(&:blank?)
                  .reject { |w| STOPWORDS.include?(w) }
                  .map { |w| stem(w) }

      words.select { |w| w.length >= @min_token_len }.uniq
    end

    # Raccourci grossier (fr): enlève terminaisons simples
    def stem(w)
      w.sub(/(es|e|s)\z/, "")
    end
  end
end
