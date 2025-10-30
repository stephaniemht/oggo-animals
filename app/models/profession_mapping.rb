class ProfessionMapping < ApplicationRecord
  belongs_to :profession, optional: true
  belongs_to :carrier_profession

  enum status: { pending: "pending", approved: "approved", rejected: "rejected" }, _default: "pending"
  validates :status, presence: true
  validates :confidence, numericality: true, allow_nil: true
  scope :visible_in_referential, -> { where.not(status: "rejected") }

end
