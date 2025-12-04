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

    # --------------------------------------------------------------------
    # Méthode PHP détaillée (déjà existante)
    # --------------------------------------------------------------------
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

    # --------------------------------------------------------------------
    # **NOUVEL export ultra simple OGGO → Profession finale**
    #
    # Format :
    #   'Affenpinscher' => 'Affenpinscher'
    #   'Basset Bleu Gascogne' => 'Basset Bleu de Gascogne'
    #   ...
    #
    # --------------------------------------------------------------------
    def build_php_oggo_simple(path, species: nil)
      data = {}

      rel = ProfessionMapping
              .joins(carrier_profession: { carrier_referential: :carrier })
              .includes(:profession, :carrier_profession)
              .where(status: "approved", carriers: { name: "OGGO Data" })

      rel = rel.where(professions: { animal_species: species }) if species.present?

      rel.find_each do |m|
        next unless m.profession && m.carrier_profession

        oggo_label = m.carrier_profession.external_label.to_s
        final_name = m.profession.name.to_s

        data[oggo_label] = final_name
      end

      File.open(path, "w") do |f|
        f.puts "<?php"
        f.puts "$oggo_mapping = ["

        data.sort.each do |oggo_label, final_name|
          safe_key = oggo_label.gsub("'", "\\\\'")
          safe_val = final_name.gsub("'", "\\\\'")
          f.puts "  '#{safe_key}' => '#{safe_val}',"
        end

        f.puts "];"
        f.puts "?>"
      end
    end

    # --------------------------------------------------------------------
    # 2) Exports PHP existants
    # --------------------------------------------------------------------
    build_php_file(out_dir.join("mapping.php"))
    build_php_file(out_dir.join("mapping-dog.php"), species: "dog")
    build_php_file(out_dir.join("mapping-cat.php"), species: "cat")

    # --------------------------------------------------------------------
    # 3) Nouveaux exports simples OGGO Data
    # --------------------------------------------------------------------
    build_php_oggo_simple(out_dir.join("mapping-oggo-dog.php"), species: "dog")
    build_php_oggo_simple(out_dir.join("mapping-oggo-cat.php"), species: "cat")

    puts "Exports écrits dans: #{out_dir}"
    puts "- CSV : #{csv_path}"
    puts "- PHP : #{out_dir.join("mapping.php")}"
    puts "- PHP chiens : #{out_dir.join("mapping-dog.php")}"
    puts "- PHP chats : #{out_dir.join("mapping-cat.php")}"
    puts "- PHP OGGO chiens : #{out_dir.join("mapping-oggo-dog.php")}"
    puts "- PHP OGGO chats : #{out_dir.join("mapping-oggo-cat.php")}"
  end
end
