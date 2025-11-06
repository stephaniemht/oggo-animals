# app/controllers/admin/carrier_professions_controller.rb
class Admin::CarrierProfessionsController < ApplicationController
  def index
    # redirection par défaut pour montrer aussi les pending
    if params.permit!.to_h.slice("q","status","carrier_id","only_once","species").values.all?(&:blank?)
      redirect_to admin_carrier_professions_path(status: "all") and return
    end

    @q          = params[:q].to_s.strip
    @status     = params[:status].presence || "all"
    @carrier_id = params[:carrier_id].presence
    @only_once  = ActiveModel::Type::Boolean.new.cast(params[:only_once])
    @species    = params[:species].presence_in(%w[dog cat]) # nil = toutes espèces

    rel = CarrierProfession
            .includes(carrier_referential: :carrier)
            .left_joins(:profession_mappings)

    # filtre texte
    rel = rel.where("carrier_professions.external_label ILIKE ?", "%#{@q}%") if @q.present?

    # filtre compagnie
    if @carrier_id
      rel = rel.where(
        carrier_referential_id: CarrierReferential.where(carrier_id: @carrier_id).select(:id)
      )
    end

    # filtre status
    case @status
    when "all"
      rel = rel.where("profession_mappings.id IS NULL OR profession_mappings.status != ?", "rejected")
    when "unmapped"
      rel = rel.where.not(
        id: ProfessionMapping.select(:carrier_profession_id).distinct
      )
    when "approved"
      approved_ids = ProfessionMapping.where(status: "approved").select(:carrier_profession_id)
      rejected_ids = ProfessionMapping.where(status: "rejected").select(:carrier_profession_id)
      rel = rel.where(id: approved_ids).where.not(id: rejected_ids)
    when "pending"
      pending_ids = ProfessionMapping.where(status: "pending").select(:carrier_profession_id)
      rel = rel.where(id: pending_ids)
    when "rejected"
      rejected_ids = ProfessionMapping.where(status: "rejected").select(:carrier_profession_id)
      rel = rel.where(id: rejected_ids)
    else
      rel = rel.where("profession_mappings.id IS NULL OR profession_mappings.status != ?", "rejected")
    end

    # filtre "présent dans une seule compagnie"
    if @only_once
      mapping_status_filter =
        case @status
        when "approved", "pending", "rejected"
          { status: @status }
        else
          { status: ["approved", "pending"] }
        end

      one_carrier_prof_ids = ProfessionMapping
        .joins(carrier_profession: { carrier_referential: :carrier })
        .where(mapping_status_filter)
        .group(:profession_id)
        .having("COUNT(DISTINCT carriers.id) = 1")
        .select(:profession_id)

      rel = rel.joins(:profession_mappings)
               .where(profession_mappings: { profession_id: one_carrier_prof_ids })
    end

    # filtre espèce
    rel = rel.where(species: @species) if @species.present?

    rel = rel.distinct

    @carrier_professions = rel.order("carrier_professions.id ASC").limit(2000)
    @carriers = Carrier.order(:name)

    # pour la colonne "nb compagnies"
  profession_ids = @carrier_professions.map { |cp|
    cp.profession_mappings.find { |pm| pm.status != "rejected" && pm.profession_id.present? }&.profession_id
  }.compact.uniq

  @carriers_count_by_prof =
    if profession_ids.any?
      ProfessionMapping
        .joins(carrier_profession: { carrier_referential: :carrier })
        .where(profession_id: profession_ids)
        .where.not(status: "rejected")
        .group(:profession_id)
        .count("DISTINCT carriers.id")
    else
      {}
    end
  end

  def show
    @carrier_profession = CarrierProfession
      .includes(carrier_referential: :carrier, profession_mappings: :profession)
      .find(params[:id])

    @mapping = @carrier_profession.profession_mappings.first
  end

  # =========================
  # BULK SELECT / ASSIGN
  # =========================

  def bulk_select
    @selected   ||= []
    @ids          = Array(params[:ids]).map(&:to_i).uniq
    bulk_action   = params[:bulk_action].to_s
    @species      = params[:species].presence_in(%w[dog cat]) || "dog"
    @q            = params[:q].to_s

    if @ids.empty?
      redirect_to admin_carrier_professions_path(status: "all", species: @species),
                  alert: "Sélection vide."
      return
    end

    case bulk_action
    when "mark_rejected"
      updated = 0
      CarrierProfession.includes(:profession_mappings).where(id: @ids).find_each do |cp|
        m = cp.profession_mappings.first
        next unless m
        if m.status != "rejected"
          m.update(status: "rejected")
          updated += 1
        end
      end

      redirect_to admin_carrier_professions_path(status: "all", species: @species),
                  notice: "#{updated} élément(s) passé(s) en 'rejected'."
      return

    when "mark_approved"
      updated = 0
      CarrierProfession.includes(:profession_mappings).where(id: @ids).find_each do |cp|
        m = cp.profession_mappings.first
        next unless m
        if m.status != "approved"
          attrs = { status: "approved" }
          attrs[:confidence] = 1.0 if m.confidence.nil?
          m.update(attrs)
          updated += 1
        end
      end

      redirect_to admin_carrier_professions_path(status: "all", species: @species),
                  notice: "#{updated} élément(s) passé(s) en 'approved'."
      return

    else
      # affichage du formulaire de choix de la cible
      @selected = CarrierProfession
                    .includes(carrier_referential: :carrier, profession_mappings: :profession)
                    .where(id: @ids)

      # Candidats = référentiel de l’espèce
      rel = Profession.where.not(animal_species: nil).where(animal_species: @species)
      rel = rel.joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
               .where.not(profession_mappings: { status: "rejected" })
      rel = rel.left_joins(:profession_synonyms) if defined?(ProfessionSynonym)

      if @q.present?
        norm   = LabelNormalizer.call(@q)
        quoted = ActiveRecord::Base.connection.quote(norm)
        like   = "%#{norm.gsub(/\s+/, '%')}%"

        tokens = norm.split.uniq
        roots  = tokens.map { |t| t.sub(/(es|e|s)\z/, "") }.select { |x| x.length >= 5 }.uniq

        if roots.any?
          like_patterns  = roots.map { |r| "%#{r}%" }
          name_like_sql  = like_patterns.map { "professions.name_norm LIKE ?" }.join(" OR ")

          if defined?(ProfessionSynonym)
            alias_like_sql = like_patterns.map { "profession_synonyms.alias_norm LIKE ?" }.join(" OR ")
            filter_sql     = "(#{name_like_sql}) OR (#{alias_like_sql})"
            filter_args    = like_patterns + like_patterns
          else
            filter_sql  = "(#{name_like_sql})"
            filter_args = like_patterns
          end

          @candidates = rel
            .where([filter_sql, *filter_args])
            .select(%Q{
              professions.*,
              COUNT(DISTINCT carriers.id) AS carriers_count,
              similarity(name_norm, #{quoted}) AS score
            })
            .group("professions.id")
            .order("carriers_count DESC, score DESC, professions.name ASC")
            .limit(200)
        else
          @candidates = rel
            .where("name_norm LIKE ? OR similarity(name_norm, #{quoted}) > 0.30", like)
            .select(%Q{
              professions.*,
              COUNT(DISTINCT carriers.id) AS carriers_count,
              similarity(name_norm, #{quoted}) AS score
            })
            .group("professions.id")
            .order("carriers_count DESC, score DESC, professions.name ASC")
            .limit(200)
        end
      else
        @candidates = []
      end
    end
  end

  def bulk_assign
    target = Profession.find(params.require(:profession_id))
    ids    = Array(params[:ids]).map(&:to_i).uniq

    species = params[:species].presence_in(%w[dog cat]) || "dog"
    q       = params[:q].to_s.presence

    # empêcher chien ↔ chat
    if target.animal_species.present? && target.animal_species != species
      redirect_to bulk_select_admin_carrier_professions_path(ids: ids, species: species, q: q),
                  alert: "Tu ne peux pas assigner un #{target.animal_species} depuis l’onglet #{species}."
      return
    end

    cps = CarrierProfession.includes(:profession_mappings).where(id: ids)

    updated         = 0
    unchanged       = 0
    aliases_created = 0
    aliases_skipped = 0
    alias_conflicts = 0
    cleaned         = 0

    ActiveRecord::Base.transaction do
      cps.each do |cp|
        mapping  = cp.profession_mappings.first || cp.profession_mappings.build
        old_prof = mapping.profession

        if mapping.profession_id == target.id && mapping.status == "approved"
          unchanged += 1
        else
          mapping.profession_id = target.id
          mapping.status        = "approved"
          mapping.confidence  ||= 1.0
          mapping.save!
          updated += 1
        end

        # alias auto depuis le label compagnie
        if defined?(ProfessionSynonym)
          alias_norm = LabelNormalizer.call(cp.external_label)
          syn = ProfessionSynonym.find_by(alias_norm: alias_norm)

          if syn
            if syn.profession_id == target.id
              aliases_skipped += 1
            else
              alias_conflicts += 1
            end
          else
            ProfessionSynonym.create!(profession_id: target.id, alias: cp.external_label)
            aliases_created += 1
          end
        end

        # 👉 c’est ICI qu’on log maintenant la fusion de l’ancienne fiche
        if old_prof && old_prof.id != target.id &&
           ProfessionMapping.where(profession_id: old_prof.id).none?
          if defined?(Professions::MergeService)
            Professions::MergeService.new(source: old_prof, target: target).call
          else
            # fallback ancien comportement
            ProfessionSynonym.where(profession_id: old_prof.id)
                             .update_all(profession_id: target.id) if defined?(ProfessionSynonym)
            old_prof.destroy!
          end
          cleaned += 1
        end
      end
    end

    msg = "Assigné #{updated} élément(s) à « #{target.name} »"
    msg << " (#{unchanged} inchangés)" if unchanged > 0
    msg << ". Alias : +#{aliases_created}"
    msg << ", #{aliases_skipped} déjà présents" if aliases_skipped > 0
    msg << ", #{alias_conflicts} en conflit" if alias_conflicts > 0
    msg << ". Fiches OGGO nettoyées: #{cleaned}" if cleaned > 0

    redirect_to admin_carrier_professions_path(status: "all", species: species),
                notice: msg
  end

  private

  # tu l’avais dans ta version longue : je te le laisse
  def ensure_referential_for(carrier_professions)
    carrier_professions.each do |cp|
      mapping = cp.profession_mappings.first
      needs_mapping = mapping.nil? || mapping.status == "rejected"
      next unless needs_mapping

      label = cp.external_label.to_s.strip
      next if label.blank?

      species = cp.respond_to?(:species) ? cp.species : nil
      species ||= @species

      norm = LabelNormalizer.call(label)

      prof =
        Profession.where(animal_species: species).where(name_norm: norm).first ||
        Profession.find_by(name: label)

      unless prof
        prof = Profession.create!(
          name:           label,
          name_norm:      norm,
          animal_species: species
        )
      end

      if mapping
        mapping.update!(
          profession: prof,
          status:     "approved",
          confidence: 1.0
        )
      else
        cp.profession_mappings.create!(
          profession: prof,
          status:     "approved",
          confidence: 1.0
        )
      end
    end
  end
end
