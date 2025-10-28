class CreateCarriers < ActiveRecord::Migration[7.2]
  def change
    create_table :carriers do |t|
      t.string :name

      t.timestamps
    end
  end
end
