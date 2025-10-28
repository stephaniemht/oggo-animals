class Profession < ApplicationRecord
  has_many :profession_mappings, dependent: :destroy
  has_many :profession_synonyms, dependent: :destroy


  validates :name, presence: true
  validates :name_norm, presence: true, uniqueness: true
end
