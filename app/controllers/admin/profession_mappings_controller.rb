class Admin::ProfessionMappingsController < ApplicationController
  def index
    @status   = params[:status].presence || "approved"
    @carriers = Carrier.order(:name)

    base = ProfessionMapping
             .includes(:profession, carrier_profession: { carrier_referential: :carrier })

    base = base.where(status: @status) unless @status == "all"
    base = base.where(carrier_professions: { carrier_referential_id: CarrierReferential.where(carrier_id: params[:carrier_id]) }) if params[:carrier_id].present?

    @mappings = base.order("carriers.name ASC, profession_mappings.confidence DESC")
  end

  def edit
    @mapping = ProfessionMapping.find(params[:id])
    @q = params[:q].to_s

    # 👉 nb de compagnies (hors rejected) où la profession actuelle est présente
    @current_carriers_count =
      if @mapping.profession_id
        ProfessionMapping
          .joins(carrier_profession: { carrier_referential: :carrier })
          .where(profession_id: @mapping.profession_id)
          .where.not(status: "rejected")
          .distinct
          .count("carriers.id")
      else
        0
      end

    if @q.present?
      norm   = LabelNormalizer.call(@q)
      quoted = ActiveRecord::Base.connection.quote(norm)
      like   = "%#{norm.gsub(/\s+/, '%')}%"

      rel = Profession
              .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
              .where.not(profession_mappings: { status: "rejected" })
      rel = rel.left_joins(:profession_synonyms) if defined?(ProfessionSynonym)

      tokens = norm.split.uniq
      roots  = tokens.map { |t| t.sub(/(es|e|s)\z/, "") }.select { |x| x.length >= 5 }.uniq

      if roots.any?
        like_patterns = roots.map { |r| "%#{r}%" }
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

  def update
    @mapping = ProfessionMapping.find(params[:id])
    if @mapping.update(mapping_params)
      redirect_to admin_profession_mappings_path(status: @mapping.status), notice: "Mise à jour OK"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def assign
    mapping     = ProfessionMapping.find(params[:id])
    cp          = mapping.carrier_profession
    old_prof    = mapping.profession
    chosen_prof = Profession.find(params.require(:profession_id))

    cleaned_old = false

    ActiveRecord::Base.transaction do
      # 1) approuve et repointe
      mapping.update!(profession_id: chosen_prof.id, status: "approved")

      # 2) apprend l’alias, sans jamais planter si déjà existant
      if defined?(ProfessionSynonym)
        alias_label = cp&.external_label.to_s.strip
        if alias_label.present?
          existing =
            if defined?(LabelNormalizer)
              alias_norm = LabelNormalizer.call(alias_label)
              ProfessionSynonym.find_by(alias_norm: alias_norm)
            else
              ProfessionSynonym.find_by(alias: alias_label)
            end

          if existing.nil?
            begin
              ProfessionSynonym.create!(profession_id: chosen_prof.id, alias: alias_label)
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
              Rails.logger.info "[assign] Alias '#{alias_label}' ignoré (#{e.class}: #{e.message})"
            end
          elsif existing.profession_id != chosen_prof.id
            Rails.logger.info "[assign] Alias '#{alias_label}' déjà pris par profession ##{existing.profession_id} : ignoré."
          end
        end
      end

      # 3) si l’ancienne fiche OGGO n’a plus de mappings → on la supprime
      if old_prof && old_prof.id != chosen_prof.id &&
         ProfessionMapping.where(profession_id: old_prof.id).none?
        if defined?(ProfessionSynonym)
          ProfessionSynonym.where(profession_id: old_prof.id)
                           .update_all(profession_id: chosen_prof.id)
        end
        old_prof.destroy!
        cleaned_old = true
      end
    end

    msg = "OK : « #{cp.external_label} » → « #{chosen_prof.name} » (+ alias appris)"
    msg += " — ancienne fiche supprimée car plus utilisée" if cleaned_old

    respond_to do |format|
      format.turbo_stream { redirect_to admin_carrier_professions_path, notice: msg, status: :see_other }
      format.html        { redirect_to admin_carrier_professions_path, notice: msg, status: :see_other }
    end

  rescue ActiveRecord::RecordInvalid => e
    alert_msg = "Impossible d’assigner : #{e.record.errors.full_messages.to_sentence}"
    respond_to do |format|
      format.turbo_stream { redirect_back fallback_location: admin_carrier_professions_path, alert: alert_msg, status: :see_other }
      format.html        { redirect_back fallback_location: admin_carrier_professions_path, alert: alert_msg, status: :see_other }
    end
  end


  private

  def mapping_params
    params.require(:profession_mapping).permit(:status)
  end
end
