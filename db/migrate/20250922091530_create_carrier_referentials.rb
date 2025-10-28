class CreateCarrierReferentials < ActiveRecord::Migration[7.2]
  def change
    create_table :carrier_referentials do |t|
      t.references :carrier, null: false, foreign_key: true
      t.string :version_label
      t.datetime :imported_at
      t.string :source_filename
      t.string :file_sha256

      t.timestamps
    end
  end
end
