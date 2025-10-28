class Carrier < ApplicationRecord
  has_many :carrier_referentials, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end

