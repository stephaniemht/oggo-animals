# lib/tasks/referentials.rake
namespace :referentials do
  desc "Import d'un fichier Excel multi-onglets (1 onglet = 1 compagnie). Option: FORCE=1 pour réimporter."
  task import_file: :environment do
    path = ENV["FILE"] or abort "Usage: FILE=/chemin/vers/fichier.xlsx [FORCE=1]"
    force = ENV["FORCE"].to_s == "1"
    puts "Import du fichier: #{path} (force=#{force})"

    refs = Referentials::ImportFileService.new(xlsx_path: path, force: force).call
    puts "→ Référentiels (onglets) créés/repérés: #{refs.size}"

    refs.each do |ref|
      puts "→ Construction du référentiel OGGO depuis: #{ref.carrier.name} (ref_id=#{ref.id})"
      Professions::BuildOrMergeService.new(carrier_referential: ref).call
      Matching::BuildSuggestionsService.new(carrier_referential: ref).call
    end

    puts "Terminé."
  end
end
