module Matching
  # Crée des mappings auto : strict (=approved) + fuzzy avec 3 niveaux
  class BuildSuggestionsService
    THRESHOLD_APPROVE = (ENV["THRESHOLD_APPROVE"] || 0.98).to_f
    THRESHOLD_REJECT  = (ENV["THRESHOLD_REJECT"]  || 0.85).to_f

    def initialize(carrier_referential:)
      @ref = carrier_referential
    end

    def call
      strict_match!
      fuzzy_match!
    end

    private

      def strict_match!
        # Approved direct si libellés normalisés identiques
        ref_id_sql = ActiveRecord::Base.connection.quote(@ref.id)

        sql = <<~SQL
          INSERT INTO profession_mappings (profession_id, carrier_profession_id, status, confidence, created_at, updated_at)
          SELECT p.id, cp.id, 'approved', 1.0, NOW(), NOW()
          FROM carrier_professions cp
          JOIN professions p ON p.name_norm = cp.external_label_norm
          LEFT JOIN profession_mappings pm ON pm.carrier_profession_id = cp.id
          WHERE cp.carrier_referential_id = #{ref_id_sql}
            AND pm.id IS NULL
        SQL

        ActiveRecord::Base.connection.execute(sql)
      end

      def fuzzy_match!
        remaining = CarrierProfession
          .where(carrier_referential_id: @ref.id)
          .left_joins(:profession_mappings)
          .where(profession_mappings: { id: nil })

        remaining.find_each(batch_size: 500) do |cp|
          norm   = cp.external_label_norm
          quoted = ActiveRecord::Base.connection.quote(norm)

          sql = <<~SQL
            SELECT id, name_norm, similarity(name_norm, #{quoted}) AS score
            FROM professions
            ORDER BY score DESC
            LIMIT 1
          SQL

          best = Profession.find_by_sql(sql).first
          next unless best

          s = best.score.to_f
          status =
            if s >= THRESHOLD_APPROVE
              "approved"
            elsif s >= THRESHOLD_REJECT
              "pending"
            else
              "rejected"
            end

          ProfessionMapping.create!(
            profession_id: best.id,
            carrier_profession_id: cp.id,
            status: status,
            confidence: s
          )
        end
      end
  end
end
