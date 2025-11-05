# lib/tasks/exports.rake
namespace :exports do
  desc "Export des mappings en CSV et PHP. Dossier: tmp/exports/<timestamp>"
  task all: :environment do
    ts = Time.now.strftime("%Y%m%d-%H%M%S")
    out_dir = Rails.root.join("tmp/exports", ts)
    FileUtils.mkdir_p(out_dir)

    # 1) CSV global (toutes espèces)
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

    # petite méthode locale pour éviter de répéter
    def build_php_file(path, species: nil)
      data = {}
      rel = ProfessionMapping
              .includes(:profession, carrier_profession: { carrier_referential: :carrier })
              .where(status: "approved")

      rel = rel.where(professions: { animal_species: species }) if species.present?

      rel.find_each do |m|
        next unless m.profession
        oggo_norm = LabelNormalizer.call(m.profession.name)
        carrier   = m.carrier_profession.carrier_referential.carrier.name.upcase
        data[oggo_norm] ||= {}
        data[oggo_norm][carrier] = {
          code:  m.carrier_profession.external_code,
          label: m.carrier_profession.external_label
        }
      end

      File.open(path, "w") do |f|
        f.puts "<?php"
        f.puts "// export OGGO #{species ? "(#{species})" : "(toutes espèces)"}"
        f.puts "$mapping = ["
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
    end

    # 2) PHP global
    build_php_file(out_dir.join("mapping.php"))
    # 3) PHP chiens
    build_php_file(out_dir.join("mapping-dog.php"), species: "dog")
    # 4) PHP chats
    build_php_file(out_dir.join("mapping-cat.php"), species: "cat")

    puts "Exports écrits dans: #{out_dir}"
    puts "- CSV : #{csv_path}"
    puts "- PHP : #{out_dir.join("mapping.php")}"
    puts "- PHP chiens : #{out_dir.join("mapping-dog.php")}"
    puts "- PHP chats : #{out_dir.join("mapping-cat.php")}"
  end
end
