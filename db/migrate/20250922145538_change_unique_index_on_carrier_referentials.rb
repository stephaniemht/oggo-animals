class ChangeUniqueIndexOnCarrierReferentials < ActiveRecord::Migration[7.2]
  def change
    # on enlève l’index unique actuel
    remove_index :carrier_referentials, :file_sha256

    # on ajoute un index unique composite : compagnie + fichier + sha
    add_index :carrier_referentials,
              [:carrier_id, :source_filename, :file_sha256],
              unique: true,
              name: "index_carrier_refs_on_carrier_filename_sha"
  end
end
