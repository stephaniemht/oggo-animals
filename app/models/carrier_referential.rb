class CarrierReferential < ApplicationRecord
  belongs_to :carrier
  has_many :carrier_professions, dependent: :destroy

  validates :file_sha256, presence: true,
                          uniqueness: { scope: [:carrier_id, :source_filename] }
end

