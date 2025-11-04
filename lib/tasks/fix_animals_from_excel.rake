# lib/tasks/fix_animals_from_excel.rake
require "roo"
require "active_support/inflector/transliterate"

# même normalisation que d'hab
def norm_label(str)
  return "" if str.nil?
  if defined?(LabelNormalizer)
    LabelNormalizer.call(str)
  else
    ActiveSupport::Inflector.transliterate(str.to_s).downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
  end
end

# certains fichiers arrivent en mode "Akita Am√©ricain"
# on tente de les re-décoder en UTF-8
def fix_encoding(str)
  return "" if str.nil?
  s = str.to_s
  # si ça ne contient aucun des caractères "moches", on renvoie tel quel
  return s unless s.include?("√") || s.include?("Ã") || s.include?("Â")
  # on ré-interprète comme ISO-8859-1 → UTF-8
  s.encode("UTF-8", "ISO-8859-1", invalid: :replace, undef: :replace, replace: "")
end

namespace :fix do
  desc "Met à jour les noms d'animaux depuis un XLSX SANS créer de nouvelles professions. usage: rake \"fix:animals[/chemin/fichier.xlsx]\""
  task :animals, [:file] => :environment do |t, args|
    path = args[:file].to_s
    if path.blank?
      puts "❌ Donne un fichier : rake \"fix:animals[/chemin/fichier.xlsx]\""
      exit 1
    end

    path = File.expand_path(path)
    unless File.file?(path)
      puts "❌ Fichier introuvable : #{path}"
      exit 1
    end

    # on ouvre
    xlsx =
      case File.extname(path).downcase
      when ".xlsx" then Roo::Excelx.new(path)
      when ".xls"  then Roo::Excel.new(path)
      else              Roo::Excelx.new(path)
      end

    sheet = xlsx.sheet(0)
    header = sheet.row(1).map { |h| h.to_s.strip.downcase }

    i_name = header.index("name") || header.index("nom") || header.index("label")
    unless i_name
      puts "❌ Colonne 'name' / 'nom' / 'label' introuvable en ligne 1"
      exit 1
    end

    fixed   = 0
    missed  = 0
    skipped = 0

    (2..sheet.last_row).each do |row_i|
      raw = sheet.row(row_i)
      original_label = raw[i_name].to_s.strip
      next if original_label.blank?

      # 1) on tente de corriger l'encodage de la valeur venue d'excel
      utf8_label = fix_encoding(original_label)

      # 2) on calcule la forme normalisée "propre"
      wanted_norm = norm_label(utf8_label)

      # 3) on essaie de retrouver une profession existante avec CE name_norm
      prof = Profession.find_by(name_norm: wanted_norm)

      # 4) si pas trouvé, on tente avec la version moche (au cas où elle est déjà stockée comme ça)
      if prof.nil? && original_label != utf8_label
        ugly_norm = norm_label(original_label)
        prof = Profession.find_by(name_norm: ugly_norm)
      end

      if prof.nil?
        # on ne crée rien, on note juste
        missed += 1
        next
      end

      # si c'est déjà le bon nom propre, on ne touche pas
      if prof.name == utf8_label && prof.name_norm == wanted_norm
        skipped += 1
        next
      end

      # on met à jour SANS casser les IDs
      prof.update_columns(
        name: utf8_label,
        name_norm: wanted_norm
      )
      fixed += 1
    end

    puts "✅ Terminé pour #{File.basename(path)}"
    puts "   - corrigés : #{fixed}"
    puts "   - déjà OK : #{skipped}"
    puts "   - introuvables en base (pas touchés) : #{missed}"
  end
end
