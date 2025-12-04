# lib/tasks/import_oggo_dogs.rake

namespace :oggo do
  desc "Importe les races chien OGGO Data (match exact) comme carrier_professions"
  task import_dogs: :environment do
    require "csv"

    # 1. On récupère la compagnie OGGO Data
    carrier = Carrier.find_by!(name: "OGGO Data")

    # 2. On récupère le référentiel chiens OGGO Data
    referential = CarrierReferential.find_by!(
      carrier: carrier,
      source_filename: "Races de chiens (prod OGGO)"
    )

    puts "Carrier       : #{carrier.id} - #{carrier.name}"
    puts "Referential   : #{referential.id} - #{referential.version_label}"

    # 3. Lire le CSV
    path = Rails.root.join("db/data/chiens_exact_matches_prod_app.csv")
    puts "Lecture du fichier : #{path}"

    created = 0
    skipped = 0

    CSV.foreach(path, headers: true) do |row|
      name = row["nom_exact"].to_s.strip
      next if name.blank?

      # On cherche s'il existe déjà une ligne pour ce nom dans ce référentiel
      cp = CarrierProfession.find_or_initialize_by(
        carrier_referential: referential,
        external_label: name
      )

      if cp.persisted?
        skipped += 1
        next
      end

      cp.external_code = nil
      cp.species       = "dog"
      cp.save!

      created += 1
      puts "Créé : #{cp.external_label}"
    end

    puts "-----------------------------"
    puts "CarrierProfessions créés : #{created}"
    puts "Déjà existants / ignorés : #{skipped}"
  end
end
