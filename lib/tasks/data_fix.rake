# lib/tasks/data_fix.rake
namespace :data do
  desc "Remplace '?' par 'É' et fusionne les doublons créés (professions, carrier_professions, synonyms)"
  task fix_e_acute: :environment do
    updated_prof = 0
    merged_prof  = 0
    updated_cp   = 0
    merged_cp    = 0
    updated_syn  = 0
    dropped_syn  = 0

    puts "[1/3] Professions (référentiel OGGO)…"
    Profession.find_each do |p|
      next unless p.name&.include?("?")
      clean_name = p.name.gsub("?", "É")
      clean_norm = LabelNormalizer.call(clean_name)

      ActiveRecord::Base.transaction do
        if p.name_norm != clean_norm
          # Une cible propre existe déjà ?
          target = Profession.find_by(name_norm: clean_norm)

          if target && target.id != p.id
            # Fusion : on repointe tout vers la cible, puis on supprime l'ancienne fiche
            ProfessionMapping.where(profession_id: p.id).update_all(profession_id: target.id)
            if defined?(ProfessionSynonym)
              ProfessionSynonym.where(profession_id: p.id).update_all(profession_id: target.id)
            end
            p.destroy!
            merged_prof += 1
            puts "  Fusion: « #{p.name} » -> « #{target.name} »"
          else
            p.update!(name: clean_name, name_norm: clean_norm)
            updated_prof += 1
          end
        else
          # Même norm, juste le visuel change
          p.update!(name: clean_name)
          updated_prof += 1
        end
      end
    end

    puts "[2/3] CarrierProfessions (libellés compagnies)…"
    CarrierProfession.includes(:carrier_referential).find_each do |cp|
      next unless cp.external_label&.include?("?")
      new_label = cp.external_label.gsub("?", "É")
      new_norm  = LabelNormalizer.call(new_label)

      ActiveRecord::Base.transaction do
        # Y a-t-il déjà une ligne identique (même référentiel + même norm) ?
        existing = CarrierProfession.find_by(
          carrier_referential_id: cp.carrier_referential_id,
          external_label_norm:    new_norm
        )

        if existing && existing.id != cp.id
          # Fusion : on repointe les mappings vers la ligne existante
          ProfessionMapping.where(carrier_profession_id: cp.id)
                           .update_all(carrier_profession_id: existing.id)
          cp.destroy!
          merged_cp += 1
          puts "  Fusion CP: « #{cp.external_label} » -> « #{existing.external_label} » (réf ##{cp.carrier_referential_id})"
        else
          cp.update!(external_label: new_label, external_label_norm: new_norm)
          updated_cp += 1
        end
      end
    end

    if defined?(ProfessionSynonym)
      puts "[3/3] ProfessionSynonyms…"
      ProfessionSynonym.find_each do |s|
        next unless s.alias&.include?("?")
        new_alias = s.alias.gsub("?", "É")
        new_norm  = LabelNormalizer.call(new_alias)

        ActiveRecord::Base.transaction do
          dup = ProfessionSynonym.find_by(alias_norm: new_norm)
          if dup && dup.id != s.id
            # Un synonyme identique existe déjà -> on supprime le doublon
            s.destroy!
            dropped_syn += 1
          else
            s.update!(alias: new_alias, alias_norm: new_norm)
            updated_syn += 1
          end
        end
      end
    end

    puts "OK. Professions: #{updated_prof} modifiées, #{merged_prof} fusionnées."
    puts "    CarrierProfessions: #{updated_cp} modifiées, #{merged_cp} fusionnées."
    puts "    Synonyms: #{updated_syn} modifiés, #{dropped_syn} supprimés."
  end
end
