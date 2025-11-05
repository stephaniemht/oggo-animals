# app/controllers/admin/merge_suggestions_controller.rb
class Admin::MergeSuggestionsController < ApplicationController
  protect_from_forgery with: :exception

  # --- petit helper interne pour créer l’alias après fusion ---
  private def create_alias_for(source, target)
    return unless defined?(ProfessionSynonym)

    original = source.name.to_s
    norm     = LabelNormalizer.call(original)

    ps = ProfessionSynonym.find_or_create_by!(profession: target, alias_norm: norm)
    ps.alias = original if ps.respond_to?(:alias=)
    ps.save! if ps.changed?
  rescue ActiveRecord::RecordInvalid
    true
  end

  public

  def index
    # --------- PARAMS (GROUPES) ----------
    @token     = params[:token].to_s.strip.downcase
    @min_len   = (params[:min_len]   || 6).to_i
    @min_group = (params[:min_group] || 2).to_i
    @per_page  = (params[:per_page]  || 200).to_i.clamp(50, 2000)
    @page      = [params[:page].to_i, 1].max
    offset     = (@page - 1) * @per_page

    # --------- LOGS ----------
    @logs = ProfessionMergeLog.order(performed_at: :desc).limit(1000)
    target_ids = @logs.map(&:target_id).uniq
    @targets_by_id = Profession.where(id: target_ids).pluck(:id, :name).to_h

    # --------- GROUPES PROPOSÉS ----------
    all_groups = Professions::SuggestMergesService.new(
      min_group_size: @min_group,
      min_token_len:  @min_len,
      limit_groups:   50_000,
      min_root_freq:  2
    ).call

    if @token.present?
      tok = @token.gsub(/[^a-z0-9]/, "")
      all_groups = all_groups.select { |g| g[:token].include?(tok) }
    end

    @total       = all_groups.size
    @total_pages = (@total.to_f / @per_page).ceil
    @groups_page = all_groups.slice(offset, @per_page) || []

    # --------- SINGLETONS (présents dans 1 seule compagnie) ----------
    @s_q         = params[:s_q].to_s
    @s_per_page  = (params[:s_per_page].presence || 200).to_i
    @s_per_page  = 200 if @s_per_page <= 0
    @s_page      = (params[:s_page].presence || 1).to_i
    @s_page      = 1 if @s_page <= 0

    singles = Profession
      .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
      .group("professions.id")
      .having("COUNT(DISTINCT carriers.id) = 1")
      .select("professions.id, professions.name, professions.name_norm, MIN(carriers.name) AS carrier_name")

    if @s_q.present?
      norm = LabelNormalizer.call(@s_q)
      like = "%#{norm.gsub(/\s+/, '%')}%"
      singles = singles.where("professions.name_norm LIKE ?", like)
    end

    rows = singles.map { |r| { id: r.id, name: r.name, name_norm: r.name_norm, carrier_name: r.carrier_name } }

    @s_total = rows.length
    @s_pages = ((@s_total.to_f / @s_per_page.to_f).ceil).clamp(1, 10_000)
    s_offset = (@s_page - 1) * @s_per_page
    page_rows = rows.slice(s_offset, @s_per_page) || []

    ids = page_rows.map { |h| h[:id] }
    @singletons_page = ids.any? ? Profession.where(id: ids).order(:name) : Profession.none
    @singleton_carrier = page_rows.each_with_object({}) { |h, acc| acc[h[:id]] = h[:carrier_name] }

    # --------- CANDIDATS POUR CIBLE (GROUPES) ----------
    @for_token = params[:for_token].to_s.presence
    @target_q  = params[:target_q].to_s.presence

    @target_candidates = {}
    if @for_token.present? && @target_q.present?
      norm   = LabelNormalizer.call(@target_q)
      quoted = ActiveRecord::Base.connection.quote(norm)
      like   = "%#{norm.gsub(/\s+/, '%')}%"

      rel = defined?(ProfessionSynonym) ? Profession.left_joins(:profession_synonyms) : Profession.all

      where_sql = ["professions.name_norm LIKE ? OR similarity(name_norm, #{quoted}) > 0.30", like]
      if defined?(ProfessionSynonym)
        where_sql[0] = "(#{where_sql[0]}) OR profession_synonyms.alias_norm LIKE ?"
        where_sql << like
      end

      @target_candidates[@for_token] = rel
        .select("professions.*, similarity(name_norm, #{quoted}) AS score")
        .where(where_sql)
        .distinct
        .order("score DESC, professions.name ASC")
        .limit(50)
    end

    # Turbo-frame pour recherche de cible d’un GROUPE
    if turbo_frame_request? && @for_token.present?
      g = all_groups.find { |gr| gr[:token] == @for_token }

      html = render_to_string(
        partial: "admin/merge_suggestions/group",
        formats: [:html],
        locals: { g: g, for_token: @for_token, target_candidates: @target_candidates }
      )
      render html: view_context.turbo_frame_tag("group-#{@for_token}") { html.html_safe }
      return
    end

    # --------- CANDIDATS + COMPTE COMPAGNIES (SINGLETON) ----------
    @for_singleton_id = params[:for_singleton_id].presence
    @singleton_candidates = {}
    @singleton_candidate_counts = {}

    if @for_singleton_id.present? && params[:singleton_q].present?
      norm   = LabelNormalizer.call(params[:singleton_q].to_s)
      quoted = ActiveRecord::Base.connection.quote(norm)
      like   = "%#{norm.gsub(/\s+/, '%')}%"

      rel = defined?(ProfessionSynonym) ? Profession.left_joins(:profession_synonyms) : Profession.all

      where_sql = ["professions.name_norm LIKE ? OR similarity(name_norm, #{quoted}) > 0.30", like]
      if defined?(ProfessionSynonym)
        where_sql[0] = "(#{where_sql[0]}) OR profession_synonyms.alias_norm LIKE ?"
        where_sql << like
      end

      pid = @for_singleton_id.to_i
      @singleton_candidates[pid] = rel
        .select("professions.*, similarity(name_norm, #{quoted}) AS score")
        .where(where_sql)
        .distinct
        .order("score DESC, professions.name ASC")
        .limit(50)

      # 👉 nombre de compagnies distinctes par candidat
      candidate_ids = @singleton_candidates[pid].map(&:id)
      counts = if candidate_ids.any?
        ProfessionMapping
          .joins(carrier_profession: { carrier_referential: :carrier })
          .where(profession_id: candidate_ids)
          .group(:profession_id)
          .count("DISTINCT carriers.id")
      else
        {}
      end
      @singleton_candidate_counts[pid] = counts

      if turbo_frame_request?
        p = Profession.find_by(id: pid)
        carrier_name = @singleton_carrier[pid] || begin
          Profession
            .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
            .where(professions: { id: pid })
            .pluck("MIN(carriers.name)").first
        end

        html = render_to_string(
          partial: "admin/merge_suggestions/singleton",
          formats: [:html],
          locals: {
            p: p,
            carrier_name: carrier_name,
            candidates: @singleton_candidates[pid],
            candidate_company_counts: @singleton_candidate_counts[pid]
          }
        )
        render html: view_context.turbo_frame_tag("singleton-#{pid}") { html.html_safe }
        return
      end
    end
  end

    def merge_group
    target     = Profession.find(params.require(:target_id))
    member_ids = Array(params[:member_ids]).map(&:to_i).uniq
    back_token = params[:back_anchor].to_s.sub(/\Agroup-/, "")

    # 👉 garde-fou : rien sélectionné
    if member_ids.blank?
      respond_to do |format|
        format.html { redirect_to admin_merge_suggestions_path(anchor: "group-#{back_token}"), alert: "Aucun membre sélectionné pour la fusion." }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash",
            "<div class='flash alert'>Aucun membre sélectionné pour la fusion.</div>".html_safe
          )
        end
      end
      return
    end

    to_merge = Profession.where(id: member_ids).where.not(id: target.id)
    to_merge_count = to_merge.count # ← safe (même si relation vide)

    ActiveRecord::Base.transaction do
      to_merge.find_each do |source|
        Professions::MergeService.new(source: source, target: target).call
        # si tu crées un alias après fusion :
        create_alias_for(source, target) if respond_to?(:create_alias_for, true)
      end
    end

    respond_to do |format|
      # --- HTML classique : on revient sur l’ancre du groupe
      format.html do
        redirect_to admin_merge_suggestions_path(anchor: "group-#{back_token}"),
                    notice: "Fusions effectuées (#{to_merge_count})."
      end

      # --- TURBO STREAM : on met à jour logs, le groupe concerné ET la section singletons
      format.turbo_stream do
        streams = []

        # 1) Logs
        logs = ProfessionMergeLog.order(performed_at: :desc).limit(50)
        targets_by_id = Profession.where(id: logs.map(&:target_id).uniq).pluck(:id, :name).to_h
        streams << turbo_stream.replace(
          "logs",
          partial: "admin/merge_suggestions/logs",
          locals: { logs: logs, targets_by_id: targets_by_id }
        )

        # 2) Groupe (rafraîchir la carte du groupe back_token)
        min_len   = (params[:min_len]   || 6).to_i
        min_group = (params[:min_group] || 2).to_i
        token     = params[:token].to_s.strip.downcase

        all_groups = Professions::SuggestMergesService.new(
          min_group_size: min_group,
          min_token_len:  min_len,
          limit_groups:   50_000,
          min_root_freq:  2
        ).call
        if token.present?
          tok = token.gsub(/[^a-z0-9]/, "")
          all_groups = all_groups.select { |g| g[:token].include?(tok) }
        end
        g = all_groups.find { |gr| gr[:token] == back_token }

        if g
          streams << turbo_stream.replace(
            "group-#{back_token}",
            partial: "admin/merge_suggestions/group",
            locals: { g: g, for_token: nil, target_candidates: {} }
          )
        else
          streams << turbo_stream.remove("group-#{back_token}")
        end

        # 3) SINGLETONS — recalcul complet avec les mêmes règles que l’index
        @s_q         = params[:s_q].to_s
        @s_per_page  = (params[:s_per_page].presence || 200).to_i
        @s_per_page  = 200 if @s_per_page <= 0
        @s_page      = (params[:s_page].presence || 1).to_i
        @s_page      = 1 if @s_page <= 0

        singles = Profession
          .joins(profession_mappings: { carrier_profession: { carrier_referential: :carrier } })
          .group("professions.id")
          .having("COUNT(DISTINCT carriers.id) = 1")
          .select("professions.id, professions.name, professions.name_norm, MIN(carriers.name) AS carrier_name")

        if @s_q.present?
          norm = LabelNormalizer.call(@s_q)
          like = "%#{norm.gsub(/\s+/, '%')}%"
          singles = singles.where("professions.name_norm LIKE ?", like)
        end

        rows = singles.map { |r| { id: r.id, name: r.name, name_norm: r.name_norm, carrier_name: r.carrier_name } }

        @s_total = rows.length
        @s_pages = ((@s_total.to_f / @s_per_page.to_f).ceil).clamp(1, 10_000)
        s_offset = (@s_page - 1) * @s_per_page
        page_rows = rows.slice(s_offset, @s_per_page) || []

        ids = page_rows.map { |h| h[:id] }
        @singletons_page = ids.any? ? Profession.where(id: ids).order(:name) : Profession.none
        @singleton_carrier = page_rows.each_with_object({}) { |h, acc| acc[h[:id]] = h[:carrier_name] }

        streams << turbo_stream.replace(
          "singletons",
          partial: "admin/merge_suggestions/singletons_section"
        )

        # petit flash succès en haut
        streams << turbo_stream.append(
          "flash",
          "<div class='flash notice'>Fusions effectuées (#{to_merge_count}).</div>".html_safe
        )

        render turbo_stream: streams
      end
    end
  rescue => e
    respond_to do |format|
      format.html { redirect_to admin_merge_suggestions_path, alert: "Erreur fusion: #{e.message}" }
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "flash",
          "<div class='flash alert'>Erreur fusion : #{ERB::Util.h(e.message)}</div>".html_safe
        )
      end
    end
  end


  def merge_singleton
    source = Profession.find(params.require(:source_id))
    target = Profession.find(params.require(:target_id))

    # 1) fusion
    Professions::MergeService.new(source: source, target: target).call
    # 2) alias pour prochains imports
    create_alias_for(source, target)

    # Succès : on retire la carte
    render turbo_stream: turbo_stream.remove("singleton-#{source.id}")
  rescue => e
    Rails.logger.error("[merge_singleton] #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}")
    render turbo_stream: turbo_stream.append(
      "flash",
      "<div class='flash alert' style='background:#fdecea; border:1px solid #f5c6cb; padding:8px;'>
        Erreur fusion : #{ERB::Util.h(e.message)}
      </div>".html_safe
    )
  end

  def undo
    log = ProfessionMergeLog.find(params[:id])
    Professions::MergeService.undo!(log)

    respond_to do |format|
      format.html { redirect_to admin_merge_suggestions_path, notice: "Undo OK" }
      format.turbo_stream do
        logs = ProfessionMergeLog.order(performed_at: :desc).limit(50)
        target_ids = logs.map(&:target_id).uniq
        targets_by_id = Profession.where(id: target_ids).pluck(:id, :name).to_h

        render turbo_stream: turbo_stream.replace(
          "logs",
          partial: "admin/merge_suggestions/logs",
          locals: { logs: logs, targets_by_id: targets_by_id }
        )
      end
    end
  end

  def logs
  @logs = ProfessionMergeLog.order(performed_at: :desc).limit(1000)
  @targets_by_id = Profession.where(id: @logs.map(&:target_id)).pluck(:id, :name).to_h
  end


  def bulk_undo
    ids  = Array(params[:log_ids]).map(&:to_i).uniq
    logs = ProfessionMergeLog.where(id: ids)

    undone = 0
    skipped = 0
    failed = 0
    errors = []

    logs.each do |log|
      begin
        if log.undone_at.present?
          skipped += 1
        else
          Professions::MergeService.undo!(log)
          undone += 1
        end
      rescue => e
        failed += 1
        errors << "##{log.id}: #{e.message}"
      end
    end

    msg = "Undo: #{undone} ok"
    msg << ", #{skipped} déjà annulé(s)" if skipped > 0
    msg << ", #{failed} échec(s)" if failed > 0
    msg << " (#{errors.join(' ; ')})" if errors.any?

    respond_to do |format|
      format.html { redirect_to admin_merge_suggestions_path, notice: msg }
      format.turbo_stream do
        logs = ProfessionMergeLog.order(performed_at: :desc).limit(50)
        target_ids = logs.map(&:target_id).uniq
        targets_by_id = Profession.where(id: target_ids).pluck(:id, :name).to_h

        render turbo_stream: turbo_stream.replace(
          "logs",
          partial: "admin/merge_suggestions/logs",
          locals: { logs: logs, targets_by_id: targets_by_id }
        )
      end
    end
  end
end
