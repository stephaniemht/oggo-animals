class AddSpeciesToCarrierProfessions < ActiveRecord::Migration[7.2]
  def change
    add_column :carrier_professions, :species, :string
    # pour aller plus vite ensuite en requête
    add_index  :carrier_professions, :species
  end
end

