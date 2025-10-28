class CreateCarrierProfessions < ActiveRecord::Migration[7.2]
  def change
    create_table :carrier_professions do |t|
      t.references :carrier_referential, null: false, foreign_key: true
      t.string :external_code
      t.string :external_label
      t.string :external_label_norm

      t.timestamps
    end
  end
end
