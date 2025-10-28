# app/services/referentials/import_file_service.rb
require "digest"
require "set"

module Referentials
  # Import XLSX multi-onglets robuste :
  # - scan jusqu'à 30 lignes pour trouver l'entête
  # - davantage de variantes d'entêtes
  # - si entête introuvable → fallback heuristique (colonne libellé/code)
  # - FORCE=1 : réutilise le référentiel existant et purge ses données avant réimport
  class ImportFileService
    HEADER_SCAN_MAX = 30
    SAMPLE_ROWS_FOR_HEURISTIC = 100

    LABEL_KEYS = %w[
      libelle libellé libelle_de_la_profession libelle_profession libelleprofession
      profession professions metier métier
      intitule intitulé intitule_de_la_profession
      titre
      profession_exercee profession exercée libelle_metier libellé_metier libelle metier
      libelle_activite activite activité libellé_activite
      description libelle_long libellé_long
    ].freeze

    CODE_KEYS = %w[
      code code_profession code_profession_retenue code_professionnelle
      code\ profession code_metier code_métier
    ].freeze

    def initialize(xlsx_path:, force: false)
      @xlsx_path = xlsx_path
      @force = force
    end

    def call
      raise "File not found: #{@xlsx_path}" unless File.exist?(@xlsx_path)

      sha = Digest::SHA256.file(@xlsx_path).hexdigest
      xls = Roo::Spreadsheet.open(@xlsx_path)

      referentials = []

      xls.sheets.each do |sheet_name|
        sheet        = xls.sheet(sheet_name)
        carrier_name = sheet_name.to_s.strip
        carrier      = Carrier.find_or_create_by!(name: carrier_name)

        # Réutilise le référentiel existant si même fichier (compagnie + nom + sha)
        existing = carrier.carrier_referentials.find_by(
          file_sha256: sha, source_filename: File.basename(@xlsx_path)
        )

        ref =
          if existing
            if @force
              # purge propre
              ProfessionMapping.joins(:carrier_profession)
                               .where(carrier_professions: { carrier_referential_id: existing.id })
                               .delete_all
              CarrierProfession.where(carrier_referential_id: existing.id).delete_all
            end
            existing.update!(imported_at: Time.current)
            existing
          else
            carrier.carrier_referentials.create!(
              version_label: nil,
              imported_at: Time.current,
              source_filename: File.basename(@xlsx_path),
              file_sha256: sha
            )
          end

        # --- 1) Détection d'entête ---
        header_row_idx, header = find_header_row(sheet)

        if header_row_idx # cas standard : entête trouvée
          label_idx = find_column_index(header, LABEL_KEYS)
          code_idx  = find_column_index(header, CODE_KEYS)

          unless label_idx
            # essai heuristique même si entête trouvée mais colonne libellé non détectée
            label_idx = autodetect_label_column(sheet, header_row_idx + 1)
            if label_idx
              puts "[Import] #{carrier_name}: libellé détecté heuristiquement sur la colonne ##{label_idx}"
            else
              puts "[Import] #{carrier_name}: colonne 'libellé' introuvable – onglet ignoré"
              referentials << ref
              next
            end
          end

          start_row = header_row_idx + 1

        else
          # --- 2) Fallback : entête introuvable → heuristique sur tout l'onglet ---
          puts "[Import] #{carrier_name}: entête introuvable → fallback heuristique"
          label_idx = autodetect_label_column(sheet, 1)
          if label_idx.nil?
            puts "[Import] #{carrier_name}: impossible de détecter une colonne 'libellé' – onglet ignoré"
            referentials << ref
            next
          end
          code_idx  = autodetect_code_column(sheet, 1, prefer_diff_from: label_idx)
          start_row = 1
        end

        # --- 3) Parcours des lignes ---
        rows = []
        (start_row..sheet.last_row).each do |i|
          row = safe_row(sheet, i)
          next if row.nil? || row.empty?

          # 1) libellé brut depuis l'Excel
          raw_label = (row[label_idx] || "").to_s

          # 2) pré-nettoyage (ex: "Coiffeur" => "87",  Coiffeur 91, etc.)
          clean_label, code_from_label = LabelPrecleaner.clean(raw_label)

          # 3) choix du code (colonne code si dispo, sinon celui détecté)
          code =
            if code_idx
              (row[code_idx] || "").to_s.strip.presence || code_from_label
            else
              code_from_label
            end

          # 4) si le libellé est vide après nettoyage → on saute
          next if clean_label.strip.empty?

          # 5) on enregistre la ligne avec le libellé PROPRE
          rows << {
            carrier_referential_id: ref.id,
            external_code: code.presence,
            external_label: clean_label,
            external_label_norm: LabelNormalizer.call(clean_label)
          }
        end

        # --- 4) Insert ---
        if rows.any?
          CarrierProfession.insert_all(rows, unique_by: %i[carrier_referential_id external_label_norm])
          msg_header = header_row_idx ? "header ligne #{header_row_idx}" : "fallback sans entête"
          puts "[Import] #{carrier_name}: #{rows.size} lignes insérées (#{msg_header})"
        else
          puts "[Import] #{carrier_name}: 0 ligne importée"
        end

        referentials << ref
      end

      referentials
    end

    private

    # renvoie [index_de_ligne, tableau_entete_normalisé] ou [nil, nil]
    def find_header_row(sheet)
      (1..[HEADER_SCAN_MAX, sheet.last_row].min).each do |i|
        raw = safe_row(sheet, i)
        next unless raw

        header = raw.map { |h| normalize_header(h) }
        if (header & (LABEL_KEYS + CODE_KEYS)).any?
          return [i, header]
        end
      end
      [nil, nil]
    end

    def normalize_header(value)
      s = value.to_s
      s = I18n.transliterate(s) rescue s
      s = s.downcase
      s = s.gsub(/[^a-z0-9\s]/, " ")
      s = s.gsub(/\s+/, " ").strip
      s
    end

    def find_column_index(header_array, keys)
      header_array.each_with_index do |h, idx|
        next if h.blank?
        keys.each { |k| return idx if h.include?(k) }
      end
      nil
    end

    # Heuristique : choisir la colonne la plus "textuelle" sur un échantillon
    def autodetect_label_column(sheet, start_row)
      last = sheet.last_row
      sample_last = [start_row + SAMPLE_ROWS_FOR_HEURISTIC - 1, last].min
      max_cols = (start_row..sample_last).map { |i| safe_row(sheet, i)&.length.to_i }.max.to_i
      return nil if max_cols.zero?

      scores = Array.new(max_cols, 0.0)
      seen_values = Array.new(max_cols) { Set.new }

      (start_row..sample_last).each do |i|
        row = safe_row(sheet, i) || []
        max_cols.times do |j|
          cell = (row[j] || "").to_s.strip
          next if cell.empty?

          letters = cell.count("A-Za-z")
          digits  = cell.count("0-9")
          words   = cell.split(/\s+/).size

          scores[j] += 2 if letters >= 3
          scores[j] += 1 if words >= 2
          scores[j] -= 1 if digits > letters * 2 # plutôt un code que du texte

          seen_values[j] << cell.downcase
        end
      end

      max_cols.times do |j|
        scores[j] += [seen_values[j].size / 50.0, 5].min
      end

      best_idx, best_score = nil, -Float::INFINITY
      scores.each_with_index do |s, idx|
        if s > best_score
          best_score = s
          best_idx = idx
        end
      end

      best_idx
    end

    # Heuristique : colonne "code" = courte, plutôt chiffres, peu de mots
    def autodetect_code_column(sheet, start_row, prefer_diff_from: nil)
      last = sheet.last_row
      sample_last = [start_row + SAMPLE_ROWS_FOR_HEURISTIC - 1, last].min
      max_cols = (start_row..sample_last).map { |i| safe_row(sheet, i)&.length.to_i }.max.to_i
      return nil if max_cols.zero?

      scores = Array.new(max_cols, 0.0)

      (start_row..sample_last).each do |i|
        row = safe_row(sheet, i) || []
        max_cols.times do |j|
          next if !prefer_diff_from.nil? && j == prefer_diff_from
          cell = (row[j] || "").to_s.strip
          next if cell.empty?

          letters = cell.count("A-Za-z")
          digits  = cell.count("0-9")
          words   = cell.split(/\s+/).size
          length  = cell.length

          # on "récompense" les colonnes courtes et numériques
          scores[j] += 1 if digits > 0 && letters == 0
          scores[j] += 1 if length <= 10
          scores[j] -= 1 if words >= 2
        end
      end

      best_idx, best_score = nil, -Float::INFINITY
      scores.each_with_index do |s, idx|
        next if !prefer_diff_from.nil? && idx == prefer_diff_from
        if s > best_score
          best_score = s
          best_idx = idx
        end
      end

      best_idx if best_score > 0
    end

    # robustesse : certaines lignes peuvent être plus courtes/vides
    def safe_row(sheet, i)
      row = sheet.row(i)
      row.is_a?(Array) ? row : Array(row)
    rescue
      nil
    end
  end
end
