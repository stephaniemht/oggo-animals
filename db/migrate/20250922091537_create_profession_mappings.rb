class CreateProfessionMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :profession_mappings do |t|
      t.references :profession, null: false, foreign_key: true
      t.references :carrier_profession, null: false, foreign_key: true
      t.string :status
      t.float :confidence

      t.timestamps
    end
  end
end
