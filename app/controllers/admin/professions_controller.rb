class Admin::ProfessionsController < ApplicationController
  def index
    @q = params[:q].to_s
    @company_span = params[:company_span].presence
    @per_page = (params[:per_page] || 200).to_i.clamp(10, 1000)
    @page     = [params[:page].to_i, 1].max
    offset    = (@page - 1) * @per_page

    begin
      # Base : métiers OGGO ayant au moins 1 mapping NON "rejected"
      base = Profession
              .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
              .where.not(id: Profession
                .joins(:profession_mappings)
                .group(:id)
                .having("BOOL_AND(profession_mappings.status = 'rejected')")
                .select(:id)
              )
              .distinct


      # Filtre "Présence" (one/multi) — toujours sur mappings non-rejected
      if @company_span == "one" || @company_span == "multi"
        sub = Profession
                .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
                .where.not(profession_mappings: { status: "rejected" })
                .group("professions.id")
        sub = (@company_span == "one") ? sub.having("COUNT(DISTINCT carriers.id) = 1") :
                                        sub.having("COUNT(DISTINCT carriers.id) >= 2")
        base = base.where(id: sub.select(:id))
      end

      rel_for_count = base

      if @q.present?
        norm   = LabelNormalizer.call(@q)
        quoted = ActiveRecord::Base.connection.quote(norm)
        like   = "%#{norm.gsub(/\s+/, '%')}%"

        rel = base
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

          rel_for_count = rel.where([filter_sql, *filter_args]).distinct
          @total        = rel_for_count.count(:id)

          # si aucun résultat → on affiche “Aucun résultat” sans planter
          if @total.zero?
            @professions = []
            @total_pages = 0
            return
          end

          total_pages = (@total.to_f / @per_page).ceil
          if @page > total_pages
            @page = total_pages
            offset = (@page - 1) * @per_page
          end

          @professions = rel_for_count
            .select("professions.*, similarity(name_norm, #{quoted}) AS score")
            .order("score DESC, professions.name ASC")
            .offset(offset)
            .limit(@per_page)
            .distinct
        else
          rel_for_count = base.where("name_norm LIKE ? OR similarity(name_norm, #{quoted}) > 0.30", like).distinct
          @total        = rel_for_count.count(:id)

          if @total.zero?
            @professions = []
            @total_pages = 0
            return
          end

          total_pages = (@total.to_f / @per_page).ceil
          if @page > total_pages
            @page = total_pages
            offset = (@page - 1) * @per_page
          end

          @professions = base
            .select("professions.*, similarity(name_norm, #{quoted}) AS score")
            .where("name_norm LIKE ? OR similarity(name_norm, #{quoted}) > 0.30", like)
            .order("score DESC, professions.name ASC")
            .offset(offset)
            .limit(@per_page)
            .distinct
        end
      else
        @total = rel_for_count.count(:id)
        if @total.zero?
          @professions = []
          @total_pages = 0
          return
        end

        total_pages = (@total.to_f / @per_page).ceil
        if @page > total_pages
          @page = total_pages
          offset = (@page - 1) * @per_page
        end

        @professions = base.order(:name).offset(offset).limit(@per_page)
      end

      @total_pages = (@total.to_f / @per_page).ceil
      @counts = ProfessionMapping.group(:status).count

    rescue => e
      # filet de sécu : on log, on n’explose pas
      Rails.logger.error("[Admin::Professions#index] #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
      @professions = []
      @total = 0
      @total_pages = 0
      flash.now[:alert] = "Oups, la recherche a rencontré un souci."
      # on rend quand même la vue index (200) avec “Aucun résultat”
      render :index
    end
  end

  def show
    @profession = Profession.find(params[:id])
    @status = params[:status].presence || "approved"

    base = ProfessionMapping
             .includes(:profession, carrier_profession: { carrier_referential: :carrier })
             .where(profession_id: @profession.id)

    base = base.where(status: @status) unless @status == "all"
    @mappings = base.order("carriers.name ASC, profession_mappings.confidence DESC")

    @possible_duplicates = Profession
      .where.not(id: @profession.id)
      .where(name_norm: @profession.name_norm)
      .order(:name)
  end

  def merge_into
    source = Profession.find(params[:id])
    target_id = params.require(:target_id)
    target = Profession.find(target_id)

    ActiveRecord::Base.transaction do
      ProfessionMapping.where(profession_id: source.id).update_all(profession_id: target.id)
      if defined?(ProfessionSynonym)
        ProfessionSynonym.where(profession_id: source.id).update_all(profession_id: target.id)
      end
      source.destroy!
    end

    redirect_to admin_profession_path(target), notice: "Fusion OK : #{source.name} → #{target.name}"
  end
end
