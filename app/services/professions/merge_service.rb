# app/services/professions/merge_service.rb
module Professions
  class MergeService
    def initialize(source:, target:)
      @source = source
      @target = target
    end

    # Fusionne @source -> @target et enregistre un log pour pouvoir annuler (undo)
    def call
      raise ArgumentError, "source == target" if @source.id == @target.id

      moved_mapping_ids = ProfessionMapping.where(profession_id: @source.id).pluck(:id)
      moved_synonym_ids = defined?(ProfessionSynonym) ? ProfessionSynonym.where(profession_id: @source.id).pluck(:id) : []
      alias_created_id  = nil

      # snapshot minimal pour pouvoir recréer la fiche source à l'identique si undo
      snapshot = @source.attributes.slice("id", "name", "name_norm", "created_at", "updated_at")

      log = ProfessionMergeLog.new(
        source_id:       @source.id,
        target_id:       @target.id,
        source_attrs:    snapshot,
        mapping_ids:     moved_mapping_ids,
        synonym_ids:     moved_synonym_ids,
        performed_at:    Time.current
      )

      ActiveRecord::Base.transaction do
        # 1) déplacer les mappings vers la cible
        ProfessionMapping.where(id: moved_mapping_ids).update_all(profession_id: @target.id)

        # 2) déplacer les synonymes existants vers la cible
        if defined?(ProfessionSynonym) && moved_synonym_ids.any?
          ProfessionSynonym.where(id: moved_synonym_ids).update_all(profession_id: @target.id)
        end

        # 3) créer un alias du libellé source vers la cible (si pas déjà existant)
        if defined?(ProfessionSynonym)
          alias_norm = LabelNormalizer.call(@source.name)
          existing   = ProfessionSynonym.find_by(alias_norm: alias_norm)
          if existing.nil?
            syn = ProfessionSynonym.create!(profession_id: @target.id, alias: @source.name)
            alias_created_id = syn.id
          end
        end

        # 4) supprimer la fiche source et sauver le log
        @source.destroy!
        log.alias_created_id = alias_created_id
        log.save!
      end

      log
    end

    # Annule une fusion : recrée la source (même id), remet mappings + synonymes, retire l'alias auto
    def self.undo!(log)
      raise ArgumentError, "already undone" if log.undone_at.present?

      attrs = log.source_attrs.symbolize_keys

      ActiveRecord::Base.transaction do
        # Recrée la profession source avec le même id (on bypass les validations)
        source = Profession.new(attrs.except(:id))
        source.id = attrs[:id]
        source.save!(validate: false)

        # Rétablit les mappings et synonymes
        ProfessionMapping.where(id: log.mapping_ids).update_all(profession_id: source.id)

        if defined?(ProfessionSynonym)
          ProfessionSynonym.where(id: log.synonym_ids).update_all(profession_id: source.id)
          # Retire l’alias auto-créé lors de la fusion s’il existe encore
          ProfessionSynonym.where(id: log.alias_created_id).delete_all if log.alias_created_id
        end

        log.update!(undone_at: Time.current)
      end

      true
    end
  end
end
