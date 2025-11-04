namespace :exports do
  desc "Export des mappings en CSV et PHP. Dossier: tmp/exports/<timestamp>"
  task all: :environment do
    # petite fonction pour réparer les chaînes mal encodées
    def normalize_utf8(str)
      return "" if str.nil?

      s = str.dup
      # on réinterprète comme si ça venait d'ISO-8859-1 puis on passe en UTF-8
      s.force_encoding("ISO-8859-1").encode("UTF-8")
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      # au cas où c’est vraiment tordu, on fait au moins un UTF-8 propre
      str.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end

    ts = Time.now.strftime("%Y%m%d-%H%M%S")
    out_dir = Rails.root.join("tmp/exports", ts)
    FileUtils.mkdir_p(out_dir)

    # 1) CSV global
    csv_path = out_dir.join("mappings.csv")
    require "csv"
    CSV.open(csv_path, "w") do |csv|
      csv << %w[carrier external_code external_label oggo_profession status confidence]
      ProfessionMapping
        .includes(:profession, carrier_profession: { carrier_referential: :carrier })
        .find_each do |m|
          cp        = m.carrier_profession
          carrier   = normalize_utf8(cp.carrier_referential.carrier.name)
          code      = normalize_utf8(cp.external_code)
          label     = normalize_utf8(cp.external_label)
          oggo_name = m.profession ? normalize_utf8(m.profession.name) : ""

          csv << [
            carrier,
            code,
            label,
            oggo_name,
            m.status,
            m.confidence
          ]
        end
    end

    # 2) PHP (array) : $mapping[oggo_norm][CARRIER] = ['code' => ..., 'label' => ...]
    php_path = out_dir.join("mapping.php")
    File.open(php_path, "w") do |f|
      f.puts "<?php"
      f.puts "$mapping = ["

      data = {}
      ProfessionMapping
        .includes(:profession, carrier_profession: { carrier_referential: :carrier })
        .where(status: "approved")
        .find_each do |m|
          next unless m.profession

          # on nettoie le nom OGGO AVANT de le normaliser
          cleaned_prof_name = normalize_utf8(m.profession.name)
          oggo_norm         = LabelNormalizer.call(cleaned_prof_name)

          carrier_name = normalize_utf8(m.carrier_profession.carrier_referential.carrier.name).upcase

          data[oggo_norm] ||= {}
          data[oggo_norm][carrier_name] = {
            code:  normalize_utf8(m.carrier_profession.external_code),
            label: normalize_utf8(m.carrier_profession.external_label)
          }
        end

      # écriture PHP
      data.sort.each do |oggo_norm, carriers|
        # on échappe les apostrophes dans la clé PHP
        oggo_key = oggo_norm.gsub("'", "\\\\'")
        f.puts "  '#{oggo_key}' => ["
        carriers.sort.each do |carrier, h|
          code  = (h[:code]  || "").gsub("'", "\\\\'")
          label = (h[:label] || "").gsub("'", "\\\\'")
          f.puts "    '#{carrier}' => ['code' => '#{code}', 'label' => '#{label}'],"
        end
        f.puts "  ],"
      end

      f.puts "];"
      f.puts "?>"
    end

    puts "Exports écrits dans: #{out_dir}"
    puts "- CSV : #{csv_path}"
    puts "- PHP : #{php_path}"
  end
end
