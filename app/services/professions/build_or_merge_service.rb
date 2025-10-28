module Professions
  # Construit / complète le référentiel OGGO à partir d'un CarrierReferential
  class BuildOrMergeService
    MIN_LEN = 3

    def initialize(carrier_referential:)
      @ref = carrier_referential
    end

    def call
      labels = @ref.carrier_professions.pluck(:external_label, :external_label_norm)
      grouped = labels.group_by { |(_, norm)| norm }

      inserts = []
      grouped.each do |norm, arr|
        next if norm.blank? || norm.length < MIN_LEN
        next if Profession.exists?(name_norm: norm)

        inserts << { name: arr.first.first.to_s, name_norm: norm, created_at: Time.current, updated_at: Time.current }
      end

      Profession.insert_all(inserts) if inserts.any?
    end
  end
end
