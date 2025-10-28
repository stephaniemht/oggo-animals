class CreateProfessionSynonyms < ActiveRecord::Migration[7.1]
  def change
    create_table :profession_synonyms do |t|
      t.references :profession, null: false, foreign_key: true
      t.string :alias, null: false
      t.string :alias_norm, null: false
      t.timestamps
    end
    add_index :profession_synonyms, :alias_norm, unique: true
  end
end

