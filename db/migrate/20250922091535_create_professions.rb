class CreateProfessions < ActiveRecord::Migration[7.2]
  def change
    create_table :professions do |t|
      t.string :name
      t.string :name_norm

      t.timestamps
    end
  end
end
