class ProfessionMergeLog < ApplicationRecord
  validates :source_id, :target_id, :performed_at, presence: true

  scope :recent,   -> { order(id: :desc) }
  scope :undoable, -> { where(undone_at: nil) }
end
