class Profession < ApplicationRecord
  has_many :profession_mappings, dependent: :destroy
  has_many :profession_synonyms, dependent: :destroy


  validates :name, presence: true
  validates :name_norm, presence: true, uniqueness: true

  # Pour éviter les fautes de frappe et faciliter les filtres
  ANIMAL_SPECIES = %w[dog cat].freeze
  ANIMAL_KINDS   = %w[species breed].freeze

  validates :animal_species, inclusion: { in: ANIMAL_SPECIES }, allow_nil: true
  validates :animal_kind,   inclusion: { in: ANIMAL_KINDS },   allow_nil: true

  scope :animals, -> { where.not(animal_species: nil) }
  scope :dogs,    -> { where(animal_species: "dog") }
  scope :cats,    -> { where(animal_species: "cat") }
end
