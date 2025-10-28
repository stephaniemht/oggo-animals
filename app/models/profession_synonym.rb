class ProfessionSynonym < ApplicationRecord
  belongs_to :profession
  before_validation :set_norm

  validates :alias, presence: true
  validates :alias_norm, presence: true, uniqueness: true

  private
  def set_norm
    self.alias_norm = LabelNormalizer.call(self.alias) if self.alias.present?
  end
end
