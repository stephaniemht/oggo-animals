class AllowNullProfessionIdOnProfessionMappings < ActiveRecord::Migration[7.2]
  def up
    # Autorise profession_id à être NULL (utile pour les mappings "pending" non encore assignés)
    change_column_null :profession_mappings, :profession_id, true
  end

  def down
    # Si tu reviens en arrière, on réimpose NOT NULL
    change_column_null :profession_mappings, :profession_id, false
  end
end
