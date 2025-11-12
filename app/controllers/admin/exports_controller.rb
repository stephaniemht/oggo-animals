# app/controllers/admin/exports_controller.rb
require "csv"

class Admin::ExportsController < ApplicationController
  # === 1) EXPORT JSON : /admin/professions_export.json
  # -> n’inclut que les professions ayant au moins 1 mapping NON "rejected"
  def professions
    rel = Profession
            .joins(:profession_mappings)
            .where.not(profession_mappings: { status: "rejected" })
            .distinct
            .order(:name)

    syns_by_prof = {}

    if defined?(ProfessionSynonym)
      syns = ProfessionSynonym
               .select(:profession_id, :alias, :alias_norm)
               .group_by(&:profession_id)

      syns_by_prof = syns.transform_values do |rows|
        rows.map { |r| r.respond_to?(:alias) && r.alias.present? ? r.alias : r.alias_norm }
      end
    end

    payload = rel.map do |p|
      {
        id:         p.id,
        name:       p.name,
        name_norm:  (p.respond_to?(:name_norm) ? p.name_norm : nil),
        synonyms:   syns_by_prof[p.id] || []
      }
    end

    render json: {
      exported_at: Time.current.iso8601,
      count:        payload.size,
      professions:  payload
    }
  end

  # === 2) EXPORT CSV “MATRIX” : /admin/professions_matrix.csv
  # /admin/professions_matrix.csv?species=dog|cat|nil
  # - Ne liste que les compagnies qui ont des données pour l’espèce choisie
  # - Regroupe les colonnes par nom de compagnie “normalisé” (accents/casse/espaces)
  def professions_matrix
    species = params[:species].presence_in(%w[dog cat])

    # 1) Restreindre aux carriers ayant des données pour l'espèce (si species présent)
    carriers_rel =
      if species.present?
        Carrier
          .joins(carrier_referentials: { carrier_professions: :profession_mappings })
          .joins("JOIN professions ON professions.id = profession_mappings.profession_id")
          .where.not(profession_mappings: { status: "rejected" })
          .where(professions: { animal_species: species })
          .distinct
      else
        Carrier.all
      end

    carriers = carriers_rel.select(:id, :name).order(:name).to_a

    # 2) Regrouper par nom normalisé (fusionne “SantéVet”/“Santévet”/etc.)
    grouped = carriers.group_by { |c| normalize_carrier_name(c.name) }
    # Colonnes triées par clé canonique
    columns = grouped.keys.sort.map { |k| [k, grouped[k]] } # [[canon_key, [Carrier,...]], ...]

    header = ["Référentiel OGGO"] + columns.map { |_canon, arr| arr.first.name }

    rows_enum = Enumerator.new do |y|
      y << header

      rel = Profession
              .joins(:profession_mappings)
              .where.not(profession_mappings: { status: "rejected" })
              .distinct
      rel = rel.where(animal_species: species) if species.present?

      rel.order(:name).find_each do |p|
        # toutes les étiquettes par carrier_id pour cette profession
        mappings = ProfessionMapping
          .joins(carrier_profession: { carrier_referential: :carrier })
          .where(profession_id: p.id)
          .where.not(status: "rejected")
          .select(
            "profession_mappings.id",
            "carriers.id AS carrier_id",
            "carrier_professions.external_label AS carrier_label"
          )

        by_carrier_id = {}
        mappings.each do |m|
          if by_carrier_id[m.carrier_id]
            by_carrier_id[m.carrier_id] = [by_carrier_id[m.carrier_id], m.carrier_label].uniq.join(" | ")
          else
            by_carrier_id[m.carrier_id] = m.carrier_label
          end
        end

        # Pour chaque colonne (groupe), fusionner les labels des carriers du groupe
        row_cells = columns.map do |_canon, arr|
          labels = arr.map { |c| by_carrier_id[c.id] }.compact
          labels.present? ? labels.uniq.join(" | ") : ""
        end

        y << [p.name] + row_cells
      end
    end

    response.headers["Content-Type"]        = "text/csv; charset=utf-8"
    response.headers["Content-Disposition"] = "attachment; filename=professions_matrix#{species ? "-#{species}" : ""}.csv"
    self.response_body = csv_with_bom(rows_enum)
  end

  # === 3) EXPORT PHP : /admin/professions_php
  # paramètres :
  #   ?species=dog|cat
  #   ?include_aliases=1
  #
  # exemples :
  #   /admin/professions_php
  #   /admin/professions_php?include_aliases=1
  #   /admin/professions_php?species=dog
  #   /admin/professions_php?species=cat&include_aliases=1
  def professions_php
    species         = params[:species].presence_in(%w[dog cat])
    include_aliases = ActiveModel::Type::Boolean.new.cast(params[:include_aliases]) && defined?(ProfessionSynonym)

    map = {}

    # a) noms officiels
    prof_rel = Profession
      .joins(:profession_mappings)
      .where.not(profession_mappings: { status: "rejected" })
      .distinct
    prof_rel = prof_rel.where(animal_species: species) if species.present?

    prof_rel.order(:name).find_each do |p|
      clean = fix_mojibake(p.name.to_s)
      map[clean] = clean
    end

    # b) alias (optionnel)
    alias_count = 0
    if include_aliases
      syn_rel = ProfessionSynonym
        .joins(profession: :profession_mappings)
        .where.not(profession_mappings: { status: "rejected" })
        .select(
          "profession_synonyms.id",
          "profession_synonyms.alias",
          "profession_synonyms.alias_norm",
          "professions.name AS canonical_name",
          "professions.animal_species"
        )
        .distinct
      syn_rel = syn_rel.where(professions: { animal_species: species }) if species.present?

      syn_rel.find_each do |row|
        alias_label =
          if row.respond_to?(:alias) && row.alias.present?
            fix_mojibake(row.alias)
          else
            fix_mojibake(row.alias_norm)
          end

        canonical = fix_mojibake(row.canonical_name)
        next if alias_label.blank?

        map[alias_label] = canonical
        alias_count += 1
      end
    end

    exported_at   = Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")
    mode          = include_aliases ? "avec alias" : "sans alias"
    total_entries = map.size
    species_label = species.present? ? "Espèce : #{species}" : "Espèce : toutes"

    filename_parts = ["professions"]
    filename_parts << species if species.present?
    filename_parts << "with-aliases" if include_aliases
    filename = filename_parts.join("-") + ".php"

    php = +"<?php\n"
    php << "// Export OGGO — #{mode}\n"
    php << "// #{species_label}\n"
    php << "// Généré le : #{exported_at}\n"
    php << "// Entrées totales : #{total_entries}#{include_aliases ? " (dont ~#{alias_count} alias)" : ""}\n"
    php << "\n"
    php << "\$professions = [\n"

    last_letter = nil
    map.sort_by { |k, _| k.downcase }.each do |k, v|
      first_letter = k[0]&.upcase
      if include_aliases && first_letter && first_letter != last_letter
        php << "\n" if last_letter
        last_letter = first_letter
      end
      php << "  #{php_quote(fix_mojibake(k))} => #{php_quote(fix_mojibake(v))},\n"
    end

    php << "];\n"
    php << "return \$professions;\n"

    send_data php,
              filename:   filename,
              type:       "application/x-httpd-php; charset=utf-8",
              disposition: "attachment"
  end

  private

  # Normalise un nom de compagnie pour regrouper les variantes d’écriture
  def normalize_carrier_name(name)
    s = name.to_s.strip.downcase
    s = I18n.respond_to?(:transliterate) ? I18n.transliterate(s) : s
    s.gsub(/[ \t\r\n]+/, " ").gsub(/\s*-\s*/, "-")
  end

  # Essaie de réparer les chaînes doublement mal lues (Ã… Â…)
  def fix_mojibake(str)
    return "" if str.nil?
    s = str.to_s.dup

    suspicious = ["Ã", "Â", "¢", "", ""]
    needs_fix  = suspicious.any? { |c| s.include?(c) }
    return s unless needs_fix

    5.times do
      break unless suspicious.any? { |c| s.include?(c) }
      s = s.force_encoding("ISO-8859-1").encode(
        "UTF-8",
        invalid: :replace,
        undef:   :replace,
        replace: ""
      )
    end

    s
  rescue
    str.to_s
  end

  def csv_with_bom(enum)
    Enumerator.new do |y|
      y << "\uFEFF"
      enum.each do |row|
        y << CSV.generate_line(row, col_sep: ";")
      end
    end
  end

  def php_quote(str)
    s = str.to_s.gsub("\\", "\\\\").gsub("'", "\\'")
    "'#{s}'"
  end
end
