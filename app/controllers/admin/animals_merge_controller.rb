class Admin::AnimalsMergeController < ApplicationController
  def index
    @species = params[:species].presence_in(%w[dog cat]) || "dog"    # onglet par défaut = chiens
    @q       = params[:q].to_s.strip.presence

    # pagination simple
    @per_page = (params[:per_page] || 100).to_i.clamp(20, 500)
    @page     = [params[:page].to_i, 1].max
    offset    = (@page - 1) * @per_page

    # base : uniquement les animaux (par espèce)
    base = Profession.where(animal_species: @species)

    # recherche facultative (sur name_norm)
    if @q
      norm = @q.downcase.gsub(/\s+/, " ").strip
      base = base.where("name_norm ILIKE ?", "%#{norm}%")
    end

    # groupes avec doublons (même name_norm) → count > 1
    grouped = base
      .select("name_norm, COUNT(*) AS c")
      .where.not(name_norm: [nil, ""])
      .group("name_norm")
      .having("COUNT(*) > 1")
      .order("c DESC, name_norm ASC")

    @total = ActiveRecord::Base.connection.exec_query(
      "SELECT COUNT(*) AS n FROM (#{grouped.to_sql}) t"
    ).first["n"].to_i

    @total_pages = (@total.to_f / @per_page).ceil
    @page = @total_pages if @page > @total_pages && @total_pages > 0
    offset = (@page - 1) * @per_page

    @groups = grouped.offset(offset).limit(@per_page)

    # charge les items de chaque groupe
    @items_by_norm = {}
    if @groups.any?
      norms = @groups.map { |g| g.name_norm }
      items = base.where(name_norm: norms).order(:name)
      @items_by_norm = items.group_by(&:name_norm)
    end

    # compte pour onglets
    @count_dogs = Profession.where(animal_species: "dog").count
    @count_cats = Profession.where(animal_species: "cat").count
  end
end
