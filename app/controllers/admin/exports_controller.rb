# app/controllers/admin/exports_controller.rb
require "csv"

class Admin::ExportsController < ApplicationController
  # si tu veux limiter l'accès: before_action :authenticate_user!

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
      count: payload.size,
      professions: payload
    }
  end

  # === 2) EXPORT CSV “MATRIX” : /admin/professions_matrix.csv
  def professions_matrix
    carriers = Carrier.order(:name).to_a
    header = ["Référentiel OGGO"] + carriers.map(&:name)

    rows_enum = Enumerator.new do |y|
      y << header

      Profession
        .joins(:profession_mappings)
        .where.not(profession_mappings: { status: "rejected" })
        .distinct
        .order(:name)
        .find_each do |p|

        mappings = ProfessionMapping
          .joins(carrier_profession: { carrier_referential: :carrier })
          .where(profession_id: p.id)
          .where.not(status: "rejected")
          .select(
            "profession_mappings.id",
            "carriers.id AS carrier_id",
            "carrier_professions.external_label AS carrier_label"
          )

        by_carrier = {}
        mappings.each do |m|
          if by_carrier[m.carrier_id]
            by_carrier[m.carrier_id] = [by_carrier[m.carrier_id], m.carrier_label].uniq.join(" | ")
          else
            by_carrier[m.carrier_id] = m.carrier_label
          end
        end

        row = [p.name] + carriers.map { |c| by_carrier[c.id].to_s }
        y << row
      end
    end

    response.headers["Content-Type"] = "text/csv; charset=utf-8"
    response.headers["Content-Disposition"] = "attachment; filename=professions_matrix.csv"
    self.response_body = csv_with_bom(rows_enum)
  end

  # === 3) EXPORT PHP : /admin/professions_php  (+ ?include_aliases=1)
  # -> n’inclut que les professions / alias rattachés à AU MOINS 1 mapping NON "rejected"
  def professions_php
    map = {}

    # a) noms officiels (on ne touche pas aux accents)
    Profession
      .joins(:profession_mappings)
      .where.not(profession_mappings: { status: "rejected" })
      .distinct
      .order(:name)
      .find_each do |p|
      name = p.name.to_s
      map[name] = name
    end

    # b) alias (pareil, on sort tel quel)
    include_aliases = ActiveModel::Type::Boolean.new.cast(params[:include_aliases]) && defined?(ProfessionSynonym)
    alias_count = 0

    if include_aliases
      ProfessionSynonym
        .joins(profession: :profession_mappings)
        .where.not(profession_mappings: { status: "rejected" })
        .select(
          "profession_synonyms.id",
          "profession_synonyms.alias",
          "profession_synonyms.alias_norm",
          "professions.name AS canonical_name"
        )
        .distinct
        .find_each do |row|

        alias_label =
          if row.respond_to?(:alias) && row.alias.present?
            row.alias.to_s
          else
            row.alias_norm.to_s
          end

        next if alias_label.blank?

        canonical = row.canonical_name.to_s
        map[alias_label] = canonical
        alias_count += 1
      end
    end

    exported_at   = Time.current.strftime("%Y-%m-%d %H:%M:%S %Z")
    mode          = include_aliases ? "avec alias" : "sans alias"
    total_entries = map.size

    php = +"<?php\n"
    php << "// Export OGGO — #{mode}\n"
    php << "// Généré le : #{exported_at}\n"
    php << "// Entrées totales : #{total_entries}#{include_aliases ? " (dont ~#{alias_count} alias)" : ""}\n"
    php << "\n"
    php << "\$professions = [\n"

    # on écrit tel quel, juste on échappe les quotes
    map.sort_by { |k, _| k.downcase }.each do |k, v|
      php << "  #{php_quote(k)} => #{php_quote(v)},\n"
    end

    php << "];\n"
    php << "return \$professions;\n"

    send_data php,
              filename: "professions.php",
              type: "application/x-httpd-php; charset=utf-8",
              disposition: "attachment"
  end

  private

  # CSV avec BOM pour que Excel affiche bien les accents
  def csv_with_bom(enum)
    Enumerator.new do |y|
      y << "\uFEFF"
      enum.each do |row|
        y << CSV.generate_line(row, col_sep: ";")
      end
    end
  end

  # Échapper une chaîne pour l’insérer dans du code PHP entre quotes simples
  def php_quote(str)
    s = str.to_s.gsub("\\", "\\\\").gsub("'", "\\'")
    "'#{s}'"
  end
end
