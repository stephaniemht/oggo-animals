namespace :exports do
  desc "Export des mappings en CSV et PHP. Dossier: tmp/exports/<timestamp>"
  task all: :environment do
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
          cp = m.carrier_profession
          csv << [
            cp.carrier_referential.carrier.name,
            cp.external_code,
            cp.external_label,
            m.profession&.name,
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

      # On regroupe par profession OGGO normalisée
      data = {}
      ProfessionMapping
        .includes(:profession, carrier_profession: { carrier_referential: :carrier })
        .where(status: "approved")
        .find_each do |m|
          next unless m.profession
          oggo_norm = LabelNormalizer.call(m.profession.name)
          carrier   = m.carrier_profession.carrier_referential.carrier.name.upcase
          data[oggo_norm] ||= {}
          data[oggo_norm][carrier] = {
            code:  m.carrier_profession.external_code,
            label: m.carrier_profession.external_label
          }
        end

      # Écriture PHP
      data.sort.each do |oggo_norm, carriers|
        f.puts "  '#{oggo_norm.gsub("'", "\\\\'")}' => ["
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
