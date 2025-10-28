class AddIndexesAndConstraints < ActiveRecord::Migration[7.2]
  def change
    # Unicité du hash de fichier (une version par fichier)
    add_index :carrier_referentials, :file_sha256, unique: true

    # Recherche & dédoublonnage
    add_index :professions, :name_norm, unique: true
    add_index :carrier_professions, [:carrier_referential_id, :external_label_norm], unique: true

    # Un mapping unique entre une profession OGGO et une ligne importée
    add_index :profession_mappings, [:profession_id, :carrier_profession_id], unique: true

    # Index trigram (rapides pour la similarité)
    reversible do |dir|
      dir.up do
        execute 'CREATE INDEX index_professions_on_name_norm_trgm ON professions USING gin (name_norm gin_trgm_ops);'
        execute 'CREATE INDEX index_carrier_professions_on_label_norm_trgm ON carrier_professions USING gin (external_label_norm gin_trgm_ops);'
      end
      dir.down do
        execute 'DROP INDEX IF EXISTS index_professions_on_name_norm_trgm;'
        execute 'DROP INDEX IF EXISTS index_carrier_professions_on_label_norm_trgm;'
      end
    end
  end
end
