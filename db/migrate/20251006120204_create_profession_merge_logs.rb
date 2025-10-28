class CreateProfessionMergeLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :profession_merge_logs do |t|
      t.integer  :source_id, null: false
      t.integer  :target_id, null: false
      t.jsonb    :source_attrs, null: false, default: {}
      t.integer  :mapping_ids, array: true, default: []
      t.integer  :synonym_ids, array: true, default: []
      t.integer  :alias_created_id
      t.datetime :performed_at, null: false
      t.datetime :undone_at
      t.timestamps
    end

    add_index :profession_merge_logs, :source_id
    add_index :profession_merge_logs, :target_id
    add_index :profession_merge_logs, :performed_at
  end
end
