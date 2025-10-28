# lib/tasks/professions.rake
namespace :professions do
  desc "Canonise les libellés OGGO (supprime les '=> 87', numéros, etc.) et fusionne les doublons"
  task canonize_labels: :environment do
    total = 0
    merged = 0

    Profession.find_each do |p|
      clean_name, _ = LabelPrecleaner.clean(p.name)
      clean_norm    = LabelNormalizer.call(clean_name)

      # déjà propre → on passe
      next if clean_norm == p.name_norm

      total += 1
      target = Profession.find_by(name_norm: clean_norm)

      ActiveRecord::Base.transaction do
        if target.nil?
          # on crée la fiche OGGO "propre"
          target = Profession.create!(name: clean_name, name_norm: clean_norm)
          puts "Créé: #{target.name} (##{target.id}) pour remplacer « #{p.name} »"
        else
          puts "Fusion vers existant: #{target.name} (##{target.id})  <=  « #{p.name} »"
        end

        # on repointe tous les mappings vers la cible propre
        ProfessionMapping.where(profession_id: p.id).update_all(profession_id: target.id)

        # si la table des synonymes existe, on repointe aussi
        if defined?(ProfessionSynonym)
          ProfessionSynonym.where(profession_id: p.id).update_all(profession_id: target.id)
        end

        # si la source n'est plus utilisée, on la supprime
        if ProfessionMapping.where(profession_id: p.id).none?
          p.destroy!
          merged += 1
        end
      end
    end

    puts "Canonisation terminée. Traitements: #{total}, fiches fusionnées/supprimées: #{merged}."
  end
end
