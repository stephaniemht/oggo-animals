require "roo"
require "roo/excelx"
require "digest"
require "active_support/inflector/transliterate"
require "csv"
# -------------------------------------------------
# Petite fonction utilitaire pour normaliser un label
# ex: "Berger   Allemand!!" -> "berger allemand"
# -------------------------------------------------
def norm(str)
  ActiveSupport::Inflector.transliterate(str.to_s)
    .downcase
    .gsub(/[^a-z0-9]+/, " ")
    .squeeze(" ")
    .strip
end

# -------------------------------------------------
# Déduire l'espèce (dog/cat) et le "kind" (breed/species)
# à partir du NOM DU FICHIER, pas l'onglet.
# -------------------------------------------------
def infer_species_and_kind_from_filename(path)
  fn = File.basename(path).downcase

  species =
    if fn.include?("chien")
      "dog"
    elsif fn.include?("chat")
      "cat"
    else
      nil
    end

  kind =
    if fn.include?("race") || fn.include?("races")
      "breed"
    elsif fn.include?("espece") || fn.include?("espèce") || fn.include?("especes") || fn.include?("espèces")
      "species"
    else
      nil
    end

  [species, kind]
end

namespace :import do
  # =========================================================
  # 1) IMPORT RÉFÉRENTIEL OGGO -> Profession
  #    (chiens/chats officiels)
  #
  # Utilisation :
  #   bundle exec rake "import:animals[/chemin/fichier.xlsx]"
  #
  # Lis l'onglet "OGGO Data" si présent, sinon le 1er onglet.
  # Remplit la table professions (name, name_norm, animal_species...)
  # =========================================================
  desc "Importer des animaux (référentiel OGGO) dans Profession.
       Utilisation : rake \"import:animals[path/to/file.xlsx]\""
  task :animals, [:file] => :environment do |t, args|
    unless args[:file]
      puts "❌ Donne le chemin du fichier : rake \"import:animals[path/to/file.xlsx]\""
      exit 1
    end

    path = File.expand_path(args[:file].to_s)
    unless File.file?(path)
      puts "❌ Fichier introuvable : #{path}"
      exit 1
    end

    filename_species, filename_kind = infer_species_and_kind_from_filename(path)

    # Ouvre l'excel
    xlsx =
      case File.extname(path).downcase
      when ".xlsx" then Roo::Excelx.new(path)
      when ".xls"  then Roo::Excel.new(path)
      else Roo::Excelx.new(path)
      end

    # Prend l'onglet "OGGO Data" si dispo, sinon le premier
    oggo_tab = xlsx.sheets.find { |s| s.to_s.strip.downcase == "oggo data" }
    sheet = oggo_tab ? xlsx.sheet(oggo_tab) : xlsx.sheet(0)

    # Lis l'en-tête (ligne 1)
    header = sheet.row(1).map { |h| h.to_s.strip.downcase }

    i_name      = header.index("name") || header.index("nom") || header.index("label")
    i_category  = header.index("category") || header.index("categorie") || header.index("catégorie")
    i_synonyms  = header.index("synonyms") || header.index("synonymes")

    i_species   = header.index("species") || header.index("animal_species") || header.index("espece") || header.index("espèce")
    i_kind      = header.index("kind")    || header.index("animal_kind")   || header.index("type")

    if i_name.nil?
      puts "❌ La colonne 'name' (ou 'nom'/'label') est obligatoire (ligne 1)."
      exit 1
    end

    created = 0
    updated = 0
    skipped = 0

    # Parcours toutes les lignes de données
    (2..sheet.last_row).each do |row_i|
      row = sheet.row(row_i)

      name         = row[i_name].to_s.strip
      category     = i_category ? row[i_category].to_s.strip : nil
      synonyms_str = i_synonyms ? row[i_synonyms].to_s.strip : nil

      row_species = i_species ? row[i_species].to_s.strip.downcase : nil
      row_kind    = i_kind    ? row[i_kind].to_s.strip.downcase    : nil

      animal_species = row_species.presence || filename_species
      animal_kind    = row_kind.presence    || filename_kind

      if name.empty?
        skipped += 1
        next
      end

      nn = norm(name)

      scope = Profession.where(name_norm: nn)
      scope = scope.where(animal_species: animal_species) if animal_species.present?

      record = scope.first || Profession.new

      # on ne remplace pas le joli nom si déjà présent
      record.name         ||= name
      record.name_norm      = nn
      record.animal_species = animal_species if animal_species.present?
      record.animal_kind    = animal_kind    if animal_kind.present?

      # stocke la catégorie (optionnel)
      if category.present?
        record.description ||= ""
        unless record.description.include?("Catégorie:")
          record.description = "Catégorie: #{category}\n#{record.description}"
        end
      end

      if record.save
        was_new = record.previous_changes.key?("id")
        created += 1 if was_new
        updated += 1 unless was_new
      else
        puts "⚠️ Ligne #{row_i} — Erreur: #{record.errors.full_messages.join(", ")}"
        skipped += 1
        next
      end

      # synonyms ("Bouledogue Français" = "French Bulldog" etc.)
      if synonyms_str.present? && defined?(ProfessionSynonym)
        synonyms = synonyms_str.split("|").map { |s| s.strip }.reject(&:empty?)
        synonyms.each do |syn|
          ProfessionSynonym.find_or_create_by!(profession_id: record.id, name: syn)
        end
      end
    end

    puts "✅ Import terminé : #{created} créés, #{updated} mis à jour, #{skipped} ignorés."
    puts "ℹ️ Contexte détecté (nom du fichier) : species=#{filename_species.inspect}, kind=#{filename_kind.inspect}"
  end

  # =========================================================
  # 2) IMPORTER LES LIBELLÉS DES COMPAGNIES
  #
  # BUT :
  # - Remplir Carrier / CarrierReferential / CarrierProfession / ProfessionMapping
  # - species (dog/cat) est déduite du NOM DU FICHIER
  # - le nom du carrier = le NOM DE L'ONGLET
  #
  # Utilisation :
  #   bundle exec rake "import:carrier_labels[/chemin/fichier.xlsx]"
  #
  # Fonctionnement :
  #   - Pour chaque onglet du fichier :
  #       * on crée (ou récupère) Carrier avec name = nom de l'onglet
  #       * on crée un CarrierReferential lié à ce carrier + ce fichier
  #       * on lit la colonne "label" (ou "libellé"/"nom"/"name")
  #       * on crée une CarrierProfession par ligne
  #       * on met species = "dog" ou "cat"
  #       * on crée un ProfessionMapping status="pending"
  # =========================================================
  desc "Importer les libellés compagnie pour CHAQUE onglet du fichier Excel.
       Utilisation : rake \"import:carrier_labels[path/to/file.xlsx]\""
  task :carrier_labels, [:file] => :environment do |t, args|
    file_path = args[:file].to_s
    if file_path.blank?
      puts "❌ Utilisation : rake \"import:carrier_labels[/chemin/fichier.xlsx]\""
      exit 1
    end

    full_path = File.expand_path(file_path)
    unless File.file?(full_path)
      puts "❌ Fichier introuvable : #{full_path}"
      exit 1
    end

    # On devine l'espèce (dog/cat) une seule fois pour tout le fichier
    file_species, _file_kind = infer_species_and_kind_from_filename(full_path)

    if file_species.nil?
      puts "⚠️ Attention : je n'ai pas reconnu 'dog' ou 'cat' dans le nom du fichier."
      puts "   J'enregistrerai species=nil sur les CarrierProfessions de ce fichier."
    end

    # Ouvrir l'excel
    xlsx =
      case File.extname(full_path).downcase
      when ".xlsx" then Roo::Excelx.new(full_path)
      when ".xls"  then Roo::Excel.new(full_path)
      else Roo::Excelx.new(full_path)
      end

    total_created_cp  = 0
    total_created_map = 0

    file_sha = Digest::SHA256.file(full_path).hexdigest

    # On boucle sur CHAQUE onglet
    xlsx.sheets.each do |sheet_name|
      sheet = xlsx.sheet(sheet_name)

      # le header de l’onglet (ligne 1)
      header = sheet.row(1).map { |h| h.to_s.strip.downcase }

      i_label = header.index("label") ||
                header.index("libellé") ||
                header.index("libelle") ||
                header.index("nom") ||
                header.index("name")

      unless i_label
        puts "⚠️ Onglet #{sheet_name.inspect}: pas de colonne 'label'/'libellé'/'nom'. Je saute cet onglet."
        next
      end

      # 1. carrier = nom de l'onglet
      carrier = Carrier.find_or_create_by!(name: sheet_name.to_s.strip)

      # 2. carrier_referential unique pour (carrier + ce fichier + cet onglet)
      #    On ajoute le nom d'onglet dans source_filename pour les différencier
      cref = CarrierReferential.find_or_create_by!(
        carrier_id: carrier.id,
        source_filename: "#{File.basename(full_path)}:#{sheet_name}",
        file_sha256: file_sha
      )

      created_cp_for_tab  = 0
      created_map_for_tab = 0

      # 3. chaque ligne du sheet → un label
      (2..sheet.last_row).each do |row_i|
        row = sheet.row(row_i)
        raw_label = row[i_label].to_s.strip
        next if raw_label.blank?

        norm_label = norm(raw_label)

        # éviter doublon dans CE référentiel-là
        next if CarrierProfession.exists?(
          carrier_referential_id: cref.id,
          external_label_norm: norm_label
        )

        cp = CarrierProfession.create!(
          carrier_referential: cref,
          external_label: raw_label,
          external_label_norm: norm_label,
          external_code: nil,
          species: file_species # <-- très important
        )
        created_cp_for_tab  += 1
        total_created_cp    += 1

        ProfessionMapping.create!(
          carrier_profession: cp,
          profession: nil,
          status: "pending",
          confidence: nil
        )
        created_map_for_tab += 1
        total_created_map   += 1
      end

      puts "✅ Onglet '#{sheet_name}':"
      puts "   - Carrier     : #{carrier.name}"
      puts "   - Référentiel : #{cref.source_filename}"
      puts "   - Ajouts CarrierProfessions : #{created_cp_for_tab}"
      puts "   - Ajouts ProfessionMappings : #{created_map_for_tab}"
    end

    puts "🎉 Import GLOBAL terminé pour #{File.basename(full_path)}"
    puts "   Total CarrierProfessions créés : #{total_created_cp}"
    puts "   Total ProfessionMappings créés : #{total_created_map}"
    puts "   Espèce appliquée (d'après le nom du fichier) : #{file_species.inspect}"
  end
end

# =========================================================
# 3) IMPORT SPÉCIAL OGGO DATA CHIENS (match exact)
#
# Utilise le fichier db/data/chiens_exact_matches_prod_app.csv
# pour créer des CarrierProfessions dans le référentiel
# "OGGO Data - chiens prod" (carrier OGGO Data).
# =========================================================
namespace :oggo do
  desc "Importe les races chien OGGO Data (match exact) comme carrier_professions"
  task import_dogs: :environment do
    # 1. On récupère la compagnie OGGO Data
    carrier = Carrier.find_by!(name: "OGGO Data")

    # 2. On récupère le référentiel chiens OGGO Data
    referential = CarrierReferential.find_by!(
      carrier: carrier,
      source_filename: "Races de chiens (prod OGGO)"
    )

    puts "Carrier       : #{carrier.id} - #{carrier.name}"
    puts "Referential   : #{referential.id} - #{referential.version_label}"

    # 3. Lire le CSV (214 races match exact)
    path = Rails.root.join("db", "data", "chiens_exact_matches_prod_app.csv")
    unless File.exist?(path)
      puts "❌ Fichier introuvable : #{path}"
      exit 1
    end
    puts "Lecture du fichier : #{path}"

    created = 0
    skipped = 0

    CSV.foreach(path, headers: true) do |row|
      name = row["nom_exact"].to_s.strip
      next if name.blank?

      norm_label = norm(name)

      # On évite les doublons : même référentiel + même label_norm
      cp = CarrierProfession.find_or_initialize_by(
        carrier_referential: referential,
        external_label_norm: norm_label
      )

      if cp.persisted?
        skipped += 1
        next
      end

      cp.external_label = name
      cp.external_code  = nil
      cp.species        = "dog"

      cp.save!
      created += 1
      puts "Créé : #{cp.external_label}"
    end

    puts "-----------------------------"
    puts "CarrierProfessions créés : #{created}"
    puts "Déjà existants / ignorés : #{skipped}"
  end
end

namespace :oggo do
  desc "Importe les races chien OGGO Data (prod) comme Professions + CarrierProfessions + ProfessionMappings.
        Utilisation : rake \"oggo:import_dogs_from_prod\""
  task import_dogs_from_prod: :environment do
    require "csv"
    require "digest"

    # 1. On pointe vers le CSV qu'on a préparé
    csv_path = Rails.root.join("imports", "oggo_data_dogs.csv")

    unless File.exist?(csv_path)
      puts "❌ Fichier introuvable : #{csv_path}"
      exit 1
    end

    puts "📂 Lecture du fichier : #{csv_path}"

    # 2. On récupère / crée la compagnie OGGO Data
    carrier = Carrier.find_or_create_by!(name: "Oggo Data")
    puts "✅ Carrier : ##{carrier.id} — #{carrier.name}"

    # 3. On crée / récupère un CarrierReferential pour ce fichier
    file_sha = Digest::SHA256.file(csv_path).hexdigest

    referential = CarrierReferential.find_or_create_by!(
      carrier: carrier,
      source_filename: File.basename(csv_path),
      file_sha256: file_sha
    ) do |ref|
      ref.version_label = "OGGO Data chiens prod #{Time.current.strftime('%Y-%m-%d %H:%M')}"
      ref.imported_at   = Time.current
    end

    puts "✅ CarrierReferential : ##{referential.id} — #{referential.version_label}"

    professions_created     = 0
    carrier_profs_created   = 0
    mappings_created        = 0

    # 4. On parcourt chaque ligne du CSV
    CSV.foreach(csv_path, headers: true, col_sep: ";") do |row|
      raw_label = row["Nom"] || row["nom"] || row["Name"] || row["name"] || row["label"] || row["Label"]
      raw_id    = row["ID"]  || row["Id"]  || row["id"]  || row["Code"] || row["code"]

      label = raw_label.to_s.strip
      next if label.empty?

      norm_label = norm(label)
      if norm_label.blank?
        puts "⚠️ Norm vide pour : #{label.inspect}, ligne ignorée"
        next
      end

      # 4.a Profession dans TON référentiel
      profession = Profession.find_by(name_norm: norm_label)

      if profession.nil?
        # aucune profession avec ce name_norm → on en crée une
        profession = Profession.create!(
          name:           label,
          name_norm:      norm_label,
          animal_species: "dog",
          animal_kind:    "breed" # on suppose que c'est une race
        )
        professions_created += 1
        puts "🆕 Profession créée : ##{profession.id} — #{profession.name}"
      else
        # une profession existe déjà → on la complète au besoin
        updated = false

        if profession.animal_species.blank?
          profession.animal_species = "dog"
          updated = true
        end

        if profession.animal_kind.blank?
          profession.animal_kind = "breed"
          updated = true
        end

        if updated
          profession.save!
          puts "♻️ Profession mise à jour : ##{profession.id} — #{profession.name}"
        end
      end

      # 4.b CarrierProfession côté OGGO Data
      carrier_prof = CarrierProfession.find_or_initialize_by(
        carrier_referential: referential,
        external_label_norm: norm_label
      )

      carrier_prof.external_label ||= label
      carrier_prof.external_code  ||= raw_id.to_s.strip.presence
      carrier_prof.species        ||= "dog"

      if carrier_prof.new_record?
        carrier_prof.save!
        carrier_profs_created += 1
        puts "   🐶 CarrierProfession créé : ##{carrier_prof.id} — #{carrier_prof.external_label}"
      elsif carrier_prof.changed?
        carrier_prof.save!
      end

      # 4.c Mapping entre les deux
      mapping = ProfessionMapping.find_or_initialize_by(
        profession:         profession,
        carrier_profession: carrier_prof
      )

      if mapping.new_record?
        mapping.status     = "approved"
        mapping.confidence = 1.0
        mapping.save!
        mappings_created += 1
      end
    end

    puts "-------------------------------------"
    puts "🎉 Import OGGO Data chiens terminé"
    puts "   Professions créées       : #{professions_created}"
    puts "   CarrierProfessions créés : #{carrier_profs_created}"
    puts "   Mappings créés           : #{mappings_created}"
  end
end

namespace :oggo do
  desc "Importe les races chat OGGO Data (prod) comme Professions + CarrierProfessions + ProfessionMappings.
        Utilisation : rake \"oggo:import_cats_from_prod\""
  task import_cats_from_prod: :environment do
    require "csv"
    require "digest"

    # 1. On pointe vers le CSV des chats
    csv_path = Rails.root.join("imports", "oggo_data_cats.csv")

    unless File.exist?(csv_path)
      puts "❌ Fichier introuvable : #{csv_path}"
      exit 1
    end

    puts "📂 Lecture du fichier : #{csv_path}"

    # 2. On récupère / crée la compagnie OGGO Data
    carrier = Carrier.find_or_create_by!(name: "Oggo Data")
    puts "✅ Carrier : ##{carrier.id} — #{carrier.name}"

    # 3. On crée / récupère un CarrierReferential pour ce fichier
    file_sha = Digest::SHA256.file(csv_path).hexdigest

    referential = CarrierReferential.find_or_create_by!(
      carrier: carrier,
      source_filename: File.basename(csv_path),
      file_sha256: file_sha
    ) do |ref|
      ref.version_label = "OGGO Data chats prod #{Time.current.strftime('%Y-%m-%d %H:%M')}"
      ref.imported_at   = Time.current
    end

    puts "✅ CarrierReferential : ##{referential.id} — #{referential.version_label}"

    professions_created     = 0
    carrier_profs_created   = 0
    mappings_created        = 0

    # 4. On parcourt chaque ligne du CSV
    CSV.foreach(csv_path, headers: true, col_sep: ";") do |row|
      raw_label = row["Nom"] || row["nom"] || row["Name"] || row["name"] || row["label"] || row["Label"]
      raw_id    = row["ID"]  || row["Id"]  || row["id"]  || row["Code"] || row["code"]

      label = raw_label.to_s.strip
      next if label.empty?

      norm_label = norm(label)
      if norm_label.blank?
        puts "⚠️ Norm vide pour : #{label.inspect}, ligne ignorée"
        next
      end

      # 4.a Profession dans TON référentiel
      profession = Profession.find_by(name_norm: norm_label)

      if profession.nil?
        # aucune profession avec ce name_norm → on en crée une
        profession = Profession.create!(
          name:           label,
          name_norm:      norm_label,
          animal_species: "cat",
          animal_kind:    "breed" # on suppose que ce sont aussi des races
        )
        professions_created += 1
        puts "🆕 Profession créée : ##{profession.id} — #{profession.name}"
      else
        # une profession existe déjà → on la complète au besoin
        updated = false

        if profession.animal_species.blank?
          profession.animal_species = "cat"
          updated = true
        end

        if profession.animal_kind.blank?
          profession.animal_kind = "breed"
          updated = true
        end

        if updated
          profession.save!
          puts "♻️ Profession mise à jour : ##{profession.id} — #{profession.name}"
        end
      end

      # 4.b CarrierProfession côté OGGO Data
      carrier_prof = CarrierProfession.find_or_initialize_by(
        carrier_referential: referential,
        external_label_norm: norm_label
      )

      carrier_prof.external_label ||= label
      carrier_prof.external_code  ||= raw_id.to_s.strip.presence
      carrier_prof.species        ||= "cat"

      if carrier_prof.new_record?
        carrier_prof.save!
        carrier_profs_created += 1
        puts "   🐱 CarrierProfession créé : ##{carrier_prof.id} — #{carrier_prof.external_label}"
      elsif carrier_prof.changed?
        carrier_prof.save!
      end

      # 4.c Mapping entre les deux
      mapping = ProfessionMapping.find_or_initialize_by(
        profession:         profession,
        carrier_profession: carrier_prof
      )

      if mapping.new_record?
        mapping.status     = "approved"
        mapping.confidence = 1.0
        mapping.save!
        mappings_created += 1
      end
    end

    puts "-------------------------------------"
    puts "🎉 Import OGGO Data chats terminé"
    puts "   Professions créées       : #{professions_created}"
    puts "   CarrierProfessions créés : #{carrier_profs_created}"
    puts "   Mappings créés           : #{mappings_created}"
  end
end
