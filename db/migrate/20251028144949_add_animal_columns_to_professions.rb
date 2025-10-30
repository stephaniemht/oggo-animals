class AddAnimalColumnsToProfessions < ActiveRecord::Migration[7.2]
  def change
    add_column :professions, :animal_species, :string   # "dog" ou "cat"
    add_column :professions, :animal_kind, :string      
    add_index  :professions, :animal_species
    add_index  :professions, :animal_kind
  end
end
