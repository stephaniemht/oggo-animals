class CarrierProfession < ApplicationRecord
  belongs_to :carrier_referential
  has_many :profession_mappings, dependent: :destroy

  validates :external_label, presence: true
  validates :external_label_norm, presence: true
end
